import Foundation
import StoreKit

/// RevanieKit's entry point.
///
/// ```swift
/// Revanie.configure(apiKey: "rv_pk_…")                       // at launch, before any UI
/// let offerings = try await Revanie.shared.offerings()
/// let result = try await Revanie.shared.purchase(offerings.current!.packages[0])
/// if try await Revanie.shared.customerInfo().isActive("pro") { … }
/// ```
public final class Revanie: Sendable {
    public static let version = "0.1.0"

    /// Who finishes StoreKit transactions. `.myApp` (observer mode) lets Revanie run next to your own purchase code or
    /// another SDK: Revanie records every transaction but never finishes one.
    public enum PurchasesCompletedBy: Sendable { case revanie, myApp }

    public enum FetchPolicy: Sendable {
        /// The cached answer if it is younger than five minutes, else the server's (falling back to the cache offline).
        case cachedOrFetched
        /// Always ask the server.
        case fetchCurrent
    }

    private static let holder = Holder()
    private let engine: Engine

    /// The configured instance. Call `configure` first.
    public static var shared: Revanie {
        guard let r = holder.value else { preconditionFailure("RevanieKit: call Revanie.configure(apiKey:) before Revanie.shared") }
        return r
    }
    public static var isConfigured: Bool { holder.value != nil }

    /// Starts RevanieKit: listens for StoreKit transactions (renewals, Ask to Buy, refunds, offer codes) and sends them to
    /// Revanie. Call once, as early as possible. `appUserID`: your own user id if you have one; otherwise an anonymous id is
    /// made and kept, and `logIn` can attach it to an account later.
    @discardableResult
    public static func configure(apiKey: String, appUserID: String? = nil, purchasesCompletedBy: PurchasesCompletedBy = .revanie) -> Revanie {
        configure(api: API(apiKey: apiKey), appUserID: appUserID, purchasesCompletedBy: purchasesCompletedBy, suite: "com.revanie.kit")
    }

    @discardableResult
    static func configure(api: API, appUserID: String?, purchasesCompletedBy: PurchasesCompletedBy, suite: String,
                          listen: Bool = true) -> Revanie {
        if let r = holder.value { return r }
        let r = Revanie(engine: Engine(api: api, appUserID: appUserID, completedBy: purchasesCompletedBy, suite: suite))
        holder.value = r
        if listen { Task { await r.engine.start() } }
        return r
    }

    private init(engine: Engine) { self.engine = engine }

    /// The current user's id (yours after `logIn`, else the anonymous one).
    public var appUserID: String { get async { await engine.appUserID } }
    public var isAnonymous: Bool { get async { await engine.appUserID.hasPrefix(Engine.anonPrefix) } }

    public func customerInfo(fetchPolicy: FetchPolicy = .cachedOrFetched) async throws -> CustomerInfo {
        try await engine.customerInfo(policy: fetchPolicy)
    }

    /// Every new CustomerInfo: after purchases, renewals arriving through StoreKit, restores, logins.
    public var customerInfoUpdates: AsyncStream<CustomerInfo> { get async { await engine.updates() } }

    /// The offerings set up in Revanie, with their StoreKit products loaded. Packages whose product StoreKit doesn't know
    /// (not yet approved, wrong id) are left out.
    public func offerings() async throws -> Offerings { try await engine.offerings() }

    public func purchase(_ package: Package) async throws -> PurchaseResult { try await engine.purchase(package.product) }
    public func purchase(product: Product) async throws -> PurchaseResult { try await engine.purchase(product) }

    /// Asks the App Store for every purchase of this Apple account (it may ask the user to sign in), then tells Revanie.
    /// Call only from a "Restore purchases" button.
    public func restorePurchases() async throws -> CustomerInfo { try await engine.restore() }

    /// Sends the purchases StoreKit already knows on this device, without prompting. Use when moving to RevanieKit from
    /// your own code.
    public func syncPurchases() async throws -> CustomerInfo { try await engine.sync() }

    /// Switches to your user. What the anonymous user bought on this device goes with them.
    public func logIn(_ appUserID: String) async throws -> CustomerInfo { try await engine.logIn(appUserID) }

    /// Back to a fresh anonymous user (e.g. when your user signs out).
    public func logOut() async throws -> CustomerInfo { try await engine.logOut() }

    /// Your own key–value notes on the customer, shown in Revanie (`nil` removes one). At most 50 keys.
    public func setAttributes(_ attributes: [String: String?]) async throws { try await engine.setAttributes(attributes) }
}

private final class Holder: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Revanie?
    var value: Revanie? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

// MARK: - engine

actor Engine {
    static let anonPrefix = "$rv_anon_"
    private let api: API
    private let completedBy: Revanie.PurchasesCompletedBy
    private let defaults: UserDefaults
    private(set) var appUserID: String
    private var cached: CustomerInfo?
    private var cachedAt: Date?
    private var listeners: [UUID: AsyncStream<CustomerInfo>.Continuation] = [:]
    private var listener: Task<Void, Never>?

    init(api: API, appUserID: String?, completedBy: Revanie.PurchasesCompletedBy, suite: String) {
        self.api = api
        self.completedBy = completedBy
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        self.defaults = defaults
        let saved = defaults.string(forKey: "appUserID")
        self.appUserID = appUserID ?? saved ?? Engine.anonPrefix + UUID().uuidString.lowercased()
        defaults.set(self.appUserID, forKey: "appUserID")
        if let d = defaults.data(forKey: "customerInfo"), let info = try? JSONDecoder().decode(CustomerInfo.self, from: d), info.appUserID == self.appUserID {
            cached = info
        }
    }

    func start() {
        guard listener == nil else { return }
        // Transactions that never got through (no network, app killed mid-purchase) come first, then everything new.
        listener = Task.detached(priority: .utility) { [weak self] in
            for await result in StoreKit.Transaction.unfinished { await self?.handle(result) }
            for await result in StoreKit.Transaction.updates { await self?.handle(result) }
        }
    }

    // MARK: customer info

    func customerInfo(policy: Revanie.FetchPolicy) async throws -> CustomerInfo {
        if policy == .cachedOrFetched, let cached, let at = cachedAt, Date().timeIntervalSince(at) < 300 { return cached }
        do {
            let info = try await api.customer(appUserID)
            publish(info)
            return info
        } catch {
            // offline or Revanie unreachable: the last signed answer is still the truth we have
            if let cached, case RevanieError.network = error { return cached }
            throw error
        }
    }

    func updates() -> AsyncStream<CustomerInfo> {
        let id = UUID()
        return AsyncStream { c in
            self.listeners[id] = c
            if let cached = self.cached { c.yield(cached) }
            c.onTermination = { _ in Task { await self.drop(id) } }
        }
    }

    private func drop(_ id: UUID) { listeners[id] = nil }

    private func publish(_ info: CustomerInfo) {
        cached = info
        cachedAt = Date()
        if let d = try? JSONEncoder().encode(info) { defaults.set(d, forKey: "customerInfo") }
        for c in listeners.values { c.yield(info) }
    }

    // MARK: offerings

    func offerings() async throws -> Offerings {
        let doc = try await api.offerings()
        let ids = Set(doc.offerings.flatMap { $0.packages.map(\.productId) })
        let products = Dictionary(uniqueKeysWithValues: try await Product.products(for: ids).map { ($0.id, $0) })
        var all: [String: Offering] = [:]
        for o in doc.offerings {
            let packages = o.packages.compactMap { p in products[p.productId].map { Package(identifier: p.identifier, offeringIdentifier: o.identifier, product: $0) } }
            all[o.identifier] = Offering(identifier: o.identifier, name: o.name, metadata: (o.metadata ?? [:]).mapValues(\.text), packages: packages)
        }
        return Offerings(current: doc.current.flatMap { all[$0] }, all: all)
    }

    // MARK: purchases

    func purchase(_ product: Product) async throws -> PurchaseResult {
        // the customer's token goes on the purchase, so Apple ties every renewal and refund to them for good
        let info = try await customerInfo(policy: .cachedOrFetched)
        var options: Set<Product.PurchaseOption> = []
        if let token = UUID(uuidString: info.appAccountToken) { options.insert(.appAccountToken(token)) }
        switch try await product.purchase(options: options) {
        case .success(let result):
            guard case .verified(let tx) = result else { throw RevanieError.unverifiedTransaction }
            let updated = try await send([result.jwsRepresentation])
            if completedBy == .revanie { await tx.finish() }
            return .purchased(updated, tx)
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: return .pending
        }
    }

    /// From the StoreKit listener: tell Revanie, then finish (unless the app finishes its own).
    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let tx) = result else { return }      // StoreKit's own check failed: never granted, never sent
        do {
            _ = try await send([result.jwsRepresentation])
            if completedBy == .revanie { await tx.finish() }
        } catch {
            // left unfinished: StoreKit hands it back through `unfinished` on the next launch
        }
    }

    private func send(_ jws: [String]) async throws -> CustomerInfo {
        let info = try await api.post(transactions: jws, for: appUserID)
        publish(info)
        return info
    }

    func restore() async throws -> CustomerInfo {
        try await AppStore.sync()
        return try await sync()
    }

    func sync() async throws -> CustomerInfo {
        var jws: [String] = []
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified = result { jws.append(result.jwsRepresentation) }
        }
        if jws.isEmpty { return try await customerInfo(policy: .fetchCurrent) }
        return try await send(jws)
    }

    // MARK: identity

    func logIn(_ next: String) async throws -> CustomerInfo {
        guard next != appUserID else { return try await customerInfo(policy: .fetchCurrent) }
        let info = try await api.logIn(from: appUserID, to: next)
        appUserID = next
        defaults.set(next, forKey: "appUserID")
        publish(info)
        return info
    }

    func logOut() async throws -> CustomerInfo {
        appUserID = Engine.anonPrefix + UUID().uuidString.lowercased()
        defaults.set(appUserID, forKey: "appUserID")
        cached = nil
        cachedAt = nil
        defaults.removeObject(forKey: "customerInfo")
        return try await customerInfo(policy: .fetchCurrent)
    }

    func setAttributes(_ a: [String: String?]) async throws { try await api.setAttributes(a, for: appUserID) }
}

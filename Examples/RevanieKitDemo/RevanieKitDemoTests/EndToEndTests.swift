import XCTest
import StoreKit
import StoreKitTest
@_spi(Testing) import RevanieKit

/// RevanieKit against a real Revanie server running locally (`wrangler dev --env dev` in revenue-console/backend, seeded
/// with this demo app, its SDK key, a "pro" entitlement and this Mac's StoreKit testing certificate), with StoreKit
/// testing (Demo.storekit). Skipped when no local server answers.
final class EndToEndTests: XCTestCase {
    static let base = URL(string: "http://127.0.0.1:8787")!
    static let key = "rv_pk_demo_local_0123456789"
    static let serverKey = "9Md+iuaqwOItYoed8JQVFf8TRfA0WnIknvzoh9L4K6Y="   // the local server's throwaway SDK signing key

    override func setUp() async throws {
        let up = try? await URLSession.shared.data(from: Self.base.appendingPathComponent("health"))
        try XCTSkipIf(up == nil, "local Revanie server not running")
    }

    func testPurchaseUnlocksAndRefundLocks() async throws {
        let session = try SKTestSession(configurationFileNamed: "Demo")
        session.resetToDefaultState(); session.disableDialogs = true; session.clearTransactions()
        let revanie = Revanie.configure(apiKey: Self.key, baseURL: Self.base, publicKeyBase64: Self.serverKey,
                                        appUserID: "e2e-\(UUID().uuidString.prefix(8))")

        // a new customer: nothing unlocked, a token for StoreKit
        let before = try await revanie.customerInfo(fetchPolicy: .fetchCurrent)
        XCTAssertFalse(before.isActive("pro"))
        XCTAssertNotNil(UUID(uuidString: before.appAccountToken))

        // offerings come from Revanie, products from StoreKit
        let offerings = try await revanie.offerings()
        XCTAssertEqual(offerings.current?.identifier, "default")
        XCTAssertEqual(offerings.current?.packages.map(\.identifier), ["monthly", "lifetime"])
        XCTAssertEqual(offerings.current?.packages.first?.product.displayName, "Pro Monthly")

        // a purchase made outside RevanieKit's purchase() (like a renewal or Ask to Buy approval) reaches Revanie through
        // the transaction listener and unlocks "pro"
        let updates = await revanie.customerInfoUpdates
        try await session.buyProduct(identifier: "demo.pro.monthly")
        let unlocked = try await first(updates, within: 20) { $0.isActive("pro") }
        XCTAssertEqual(unlocked.entitlements["pro"]?.productIdentifier, "demo.pro.monthly")
        XCTAssertEqual(unlocked.entitlements["pro"]?.isSandbox, true)
        XCTAssertEqual(unlocked.activeSubscriptions, ["demo.pro.monthly"])

        // the same answer from the server, signed, on a fresh request
        let fresh = try await revanie.customerInfo(fetchPolicy: .fetchCurrent)
        XCTAssertTrue(fresh.isActive("pro"))

        // StoreKit refunds it: the revoked transaction comes through the listener, Revanie locks "pro" again
        var txId: UInt64?
        for await r in Transaction.currentEntitlements { if case .verified(let t) = r, t.productID == "demo.pro.monthly" { txId = t.id } }
        try session.refundTransaction(identifier: UInt(try XCTUnwrap(txId)))
        let locked = try await first(updates, within: 20) { !$0.isActive("pro") }
        XCTAssertFalse(locked.isActive("pro"))
    }

    /// The first value from the stream that matches, or a failure after `seconds`.
    private func first(_ s: AsyncStream<CustomerInfo>, within seconds: Double, where ok: @escaping @Sendable (CustomerInfo) -> Bool) async throws -> CustomerInfo {
        try await withThrowingTaskGroup(of: CustomerInfo?.self) { g in
            g.addTask { for await i in s where ok(i) { return i }; return nil }
            g.addTask { try await Task.sleep(for: .seconds(seconds)); return nil }
            let r = try await g.next() ?? nil
            g.cancelAll()
            return try XCTUnwrap(r, "no matching CustomerInfo within \(seconds)s")
        }
    }
}

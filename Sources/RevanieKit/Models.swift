import Foundation
import StoreKit

/// What a customer has, as Revanie's server last confirmed it (signed, checked by the SDK).
public struct CustomerInfo: Codable, Sendable, Equatable {
    public let appUserID: String
    /// The UUID StoreKit carries on every purchase of this customer (set automatically on `purchase`).
    public let appAccountToken: String
    /// Every entitlement the customer has ever had, keyed by identifier ("pro"); check `.active`.
    public let entitlements: [String: EntitlementInfo]
    public let activeSubscriptions: [String]
    public let allPurchasedProductIdentifiers: [String]
    /// When the server answered (ms since 1970).
    public let requestDate: Double

    /// The entitlements that unlock something right now.
    public var activeEntitlements: [String: EntitlementInfo] { entitlements.filter { $0.value.active } }
    /// `true` when the entitlement is active: `info.isActive("pro")`.
    public func isActive(_ entitlement: String) -> Bool { entitlements[entitlement]?.active == true }
}

public struct EntitlementInfo: Codable, Sendable, Equatable {
    public enum PeriodType: String, Codable, Sendable { case trial, normal }
    public let identifier: String
    public let active: Bool
    public let productIdentifier: String
    /// ms since 1970; nil for lifetime purchases.
    public let expiresDate: Double?
    public let willRenew: Bool
    public let periodType: PeriodType
    public let store: String
    public let isSandbox: Bool
    public let latestPurchaseDate: Double

    public var expiration: Date? { expiresDate.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

/// Everything the paywall may show; `current` is the one set as current in Revanie.
public struct Offerings: Sendable {
    public let current: Offering?
    public let all: [String: Offering]
    public subscript(identifier: String) -> Offering? { all[identifier] }
}

public struct Offering: Sendable, Identifiable {
    public let identifier: String
    public let name: String
    public let metadata: [String: String]
    public let packages: [Package]
    public var id: String { identifier }
    public func package(_ identifier: String) -> Package? { packages.first { $0.identifier == identifier } }
}

/// One choice on the paywall: an identifier you pick in Revanie ("annual") and the StoreKit product behind it.
public struct Package: Sendable, Identifiable {
    public let identifier: String
    public let offeringIdentifier: String
    public let product: Product
    public var id: String { "\(offeringIdentifier)/\(identifier)" }
}

public enum PurchaseResult: Sendable {
    /// Paid (or trial started); `customerInfo` already includes it.
    case purchased(CustomerInfo, StoreKit.Transaction)
    /// The customer closed the sheet.
    case cancelled
    /// Waiting for Ask to Buy or a bank: the result arrives later through `customerInfoUpdates`.
    case pending
}

public enum RevanieError: Error, Sendable, Equatable {
    case notConfigured
    /// The server's answer was not signed by Revanie (or was changed on the way): it was ignored.
    case untrustedResponse
    case server(status: Int, code: String?)
    case network(String)
    /// StoreKit said the transaction failed its own verification.
    case unverifiedTransaction
    case productNotFound(String)
}

// MARK: - wire formats

struct OfferingsDoc: Decodable {
    struct Off: Decodable {
        struct Pkg: Decodable { let identifier: String; let productId: String }
        let identifier: String
        let name: String
        let isCurrent: Bool
        let metadata: [String: JSONValue]?
        let packages: [Pkg]
    }
    let current: String?
    let offerings: [Off]
}

/// Offering metadata is free-form JSON; strings stay strings, everything else becomes its JSON text.
enum JSONValue: Decodable {
    case string(String), other(String)
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) }
        else if let n = try? c.decode(Double.self) { self = .other(String(n)) }
        else if let b = try? c.decode(Bool.self) { self = .other(String(b)) }
        else { self = .other("") }
    }
    var text: String { switch self { case .string(let s), .other(let s): s } }
}

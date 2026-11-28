import CryptoKit
import Foundation
import Testing
@testable import RevanieKit

// A stub server: answers every request from `handler`, signing with a test key the way api.revanie.app does.
final class Stub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data, Bool))?
    nonisolated(unsafe) static var key = Curve25519.Signing.PrivateKey()
    nonisolated(unsafe) static var seen: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Stub.seen.append(request)
        do {
            guard let (status, body, sign) = try Stub.handler?(request) else { throw URLError(.notConnectedToInternet) }
            var headers = ["content-type": "application/json"]
            if sign, let nonce = request.value(forHTTPHeaderField: "x-revanie-nonce") {
                var m = Data((nonce + ".").utf8); m.append(body)
                headers["x-revanie-signature"] = try Stub.key.signature(for: m).base64EncodedString()
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!,
                                cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

func stubAPI() -> API {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [Stub.self]
    return API(apiKey: "rv_pk_test_0123456789abcdef", base: URL(string: "https://api.test")!,
               publicKeyBase64: Stub.key.publicKey.rawRepresentation.base64EncodedString(), session: URLSession(configuration: config))
}

// What the server sends (backend/src/sdk.ts customerInfo), byte for byte in shape.
let serverInfo = """
{"appUserID":"alice","appAccountToken":"0b5c3a1e-1c2d-4e5f-8a9b-0c1d2e3f4a5b","entitlements":{"pro":{"identifier":"pro","active":true,"productIdentifier":"eph.pro.annual","expiresDate":1890000000000,"willRenew":true,"periodType":"trial","store":"app_store","isSandbox":false,"latestPurchaseDate":1764000000000},"old":{"identifier":"old","active":false,"productIdentifier":"eph.old","expiresDate":null,"willRenew":false,"periodType":"normal","store":"app_store","isSandbox":true,"latestPurchaseDate":1700000000000}},"activeSubscriptions":["eph.pro.annual"],"allPurchasedProductIdentifiers":["eph.pro.annual","eph.old"],"requestDate":1764300000000}
"""

@Suite(.serialized) struct RevanieKitTests {
    @Test func signatureCheck() throws {
        let key = Curve25519.Signing.PrivateKey()
        let body = Data(serverInfo.utf8)
        var m = Data("n1.".utf8); m.append(body)
        let sig = try key.signature(for: m).base64EncodedString()
        #expect(API.verify(body: body, nonce: "n1", signature: sig, key: key.publicKey))
        #expect(!API.verify(body: body, nonce: "n2", signature: sig, key: key.publicKey))                       // replayed
        #expect(!API.verify(body: Data(serverInfo.replacingOccurrences(of: "\"active\":false", with: "\"active\":true").utf8),
                            nonce: "n1", signature: sig, key: key.publicKey))                                    // changed
        #expect(!API.verify(body: body, nonce: "n1", signature: sig, key: Curve25519.Signing.PrivateKey().publicKey))  // not Revanie
    }

    @Test func decodesServerCustomerInfo() throws {
        let info = try JSONDecoder().decode(CustomerInfo.self, from: Data(serverInfo.utf8))
        #expect(info.isActive("pro"))
        #expect(!info.isActive("old"))
        #expect(!info.isActive("missing"))
        #expect(info.activeEntitlements.keys.sorted() == ["pro"])
        #expect(info.entitlements["pro"]?.periodType == .trial)
        #expect(info.entitlements["old"]?.expiration == nil)
    }

    @Test func clientSendsKeyAndNonceAndTrustsOnlySignedAnswers() async throws {
        Stub.seen = []
        Stub.handler = { _ in (200, Data(serverInfo.utf8), true) }
        let info = try await stubAPI().customer("alice")
        #expect(info.appUserID == "alice")
        let req = try #require(Stub.seen.last)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer rv_pk_test_0123456789abcdef")
        #expect((req.value(forHTTPHeaderField: "x-revanie-nonce") ?? "").count >= 16)
        #expect(req.url?.path == "/sdk/v1/customers/alice")

        Stub.handler = { _ in (200, Data(serverInfo.utf8), false) }      // unsigned: someone in the middle
        await #expect(throws: RevanieError.untrustedResponse) { try await stubAPI().customer("alice") }

        Stub.handler = { _ in (400, Data(#"{"error":"bundle_mismatch"}"#.utf8), false) }
        await #expect(throws: RevanieError.server(status: 400, code: "bundle_mismatch")) { try await stubAPI().post(transactions: ["x"], for: "alice") }
    }

    @Test func anonymousIdIsKeptAndCacheServesOffline() async throws {
        let suite = "revaniekit.test.\(UUID().uuidString)"
        Stub.handler = { req in
            let id = req.url!.lastPathComponent.removingPercentEncoding!
            return (200, Data(serverInfo.replacingOccurrences(of: "\"alice\"", with: "\"\(id)\"").utf8), true)
        }
        let engine = Engine(api: stubAPI(), appUserID: nil, completedBy: .revanie, suite: suite)
        let anon = await engine.appUserID
        #expect(anon.hasPrefix("$rv_anon_"))
        let first = try await engine.customerInfo(policy: .fetchCurrent)
        #expect(first.isActive("pro"))

        // a new launch keeps the same anonymous user and its last signed answer
        let again = Engine(api: stubAPI(), appUserID: nil, completedBy: .revanie, suite: suite)
        #expect(await again.appUserID == anon)
        Stub.handler = { _ in throw URLError(.notConnectedToInternet) }
        let offline = try await again.customerInfo(policy: .fetchCurrent)
        #expect(offline.isActive("pro"))
        Stub.handler = { _ in (429, Data(#"{"error":"rate_limited"}"#.utf8), false) }
        #expect(try await again.customerInfo(policy: .fetchCurrent).isActive("pro"))      // busy: still the cache
        Stub.handler = { _ in (503, Data(), false) }
        #expect(try await again.customerInfo(policy: .fetchCurrent).isActive("pro"))      // down: still the cache
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func logInSwitchesUserAndLogOutStartsFresh() async throws {
        let suite = "revaniekit.test.\(UUID().uuidString)"
        Stub.handler = { req in
            if req.url!.path.hasSuffix("/login") { return (200, Data(serverInfo.utf8), true) }
            let id = req.url!.lastPathComponent.removingPercentEncoding!
            return (200, Data(serverInfo.replacingOccurrences(of: "\"alice\"", with: "\"\(id)\"").utf8), true)
        }
        let engine = Engine(api: stubAPI(), appUserID: nil, completedBy: .revanie, suite: suite)
        let info = try await engine.logIn("alice")
        #expect(info.appUserID == "alice")
        #expect(await engine.appUserID == "alice")
        _ = try await engine.logOut()
        #expect(await engine.appUserID.hasPrefix("$rv_anon_"))
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

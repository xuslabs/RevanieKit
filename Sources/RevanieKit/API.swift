import CryptoKit
import Foundation

/// Talks to api.revanie.app. Every answer must carry Revanie's Ed25519 signature over the request's nonce and the
/// exact body; anything else is treated as if the network failed (Trusted Entitlements).
struct API: Sendable {
    /// Revanie's SDK signing key (public half). The private half lives only on the server.
    static let revaniePublicKey = "ZIquI7IVWtkUWuNvXfJqWENJfPQKElFxxwDwPNVXuy0="

    let apiKey: String
    let base: URL
    let publicKey: Curve25519.Signing.PublicKey
    let session: URLSession

    init(apiKey: String, base: URL = URL(string: "https://api.revanie.app")!, publicKeyBase64: String = API.revaniePublicKey,
         session: URLSession = .shared) {
        self.apiKey = apiKey
        self.base = base
        // A malformed key would make every answer untrusted; that is the safe failure.
        self.publicKey = (try? Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: publicKeyBase64) ?? Data()))
            ?? (try! Curve25519.Signing.PublicKey(rawRepresentation: Data(repeating: 0, count: 32)))
        self.session = session
    }

    func customer(_ appUserID: String) async throws -> CustomerInfo {
        try await signedCall("GET", "sdk/v1/customers/\(escape(appUserID))", body: nil)
    }

    func post(transactions: [String], for appUserID: String) async throws -> CustomerInfo {
        try await signedCall("POST", "sdk/v1/customers/\(escape(appUserID))/transactions", body: ["transactions": transactions])
    }

    func logIn(from current: String, to next: String) async throws -> CustomerInfo {
        try await signedCall("POST", "sdk/v1/customers/\(escape(current))/login", body: ["newAppUserID": next])
    }

    func offerings() async throws -> OfferingsDoc {
        try await signedCall("GET", "sdk/v1/offerings", body: nil)
    }

    func setAttributes(_ attributes: [String: String?], for appUserID: String) async throws {
        let body = attributes.mapValues { $0 as Any? ?? NSNull() }
        _ = try await raw("POST", "sdk/v1/customers/\(escape(appUserID))/attributes", body: ["attributes": body], nonce: nil)
    }

    // MARK: -

    private func escape(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~$@:+"))) ?? s }

    private func signedCall<T: Decodable>(_ method: String, _ path: String, body: [String: Any]?) async throws -> T {
        let nonce = Self.nonce()
        let (data, response) = try await raw(method, path, body: body, nonce: nonce)
        guard let sig = response.value(forHTTPHeaderField: "x-revanie-signature"),
              Self.verify(body: data, nonce: nonce, signature: sig, key: publicKey) else { throw RevanieError.untrustedResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func raw(_ method: String, _ path: String, body: [String: Any]?, nonce: String?) async throws -> (Data, HTTPURLResponse) {
        var r = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        r.httpMethod = method
        r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("RevanieKit/\(Revanie.version)", forHTTPHeaderField: "X-Revanie-SDK")
        if let nonce { r.setValue(nonce, forHTTPHeaderField: "x-revanie-nonce") }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: r) } catch { throw RevanieError.network(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw RevanieError.network("no response") }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw RevanieError.server(status: http.statusCode, code: code)
        }
        return (data, http)
    }

    static func nonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 18)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }

    static func verify(body: Data, nonce: String, signature: String, key: Curve25519.Signing.PublicKey) -> Bool {
        guard let sig = Data(base64Encoded: signature) else { return false }
        var message = Data((nonce + ".").utf8)
        message.append(body)
        return key.isValidSignature(sig, for: message)
    }
}

import Foundation

struct OAuthTokens: Codable, Hashable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double?
    var meta: [String: String]?
}

struct BasicCredentials: Codable, Hashable, Sendable {
    var identifier: String
    var secret: String
    var meta: [String: String]?
    var accessJwt: String?
    var refreshJwt: String?
}

enum Credentials {
    static func makeRef(kind: String, owner: String) -> String {
        "\(kind).\(owner).\(Time.newId())"
    }

    static func store<T: Encodable>(_ ref: String, value: T) throws {
        try Keychain.store.set(ref: ref, secret: JSONCodec.encode(value))
    }

    static func read<T: Decodable>(_ type: T.Type, ref: String?) -> T? {
        guard let ref, let raw = Keychain.store.get(ref: ref) else { return nil }
        return try? JSONCodec.decoder.decode(type, from: Data(raw.utf8))
    }

    static func delete(ref: String?) {
        guard let ref else { return }
        Keychain.store.remove(ref: ref)
    }
}

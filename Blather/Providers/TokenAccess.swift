import Foundation

enum TokenAccess {
    static func loadTokens(accountId: String, database: AppDatabase) -> OAuthTokens? {
        guard let conn = try? database.connections.get(accountId) else { return nil }
        return Credentials.read(OAuthTokens.self, ref: conn.credentialRef)
    }

    static func saveTokens(
        accountId: String,
        network: Network,
        tokens: OAuthTokens,
        database: AppDatabase
    ) throws {
        guard let conn = try database.connections.get(accountId),
              let ref = conn.credentialRef
        else {
            throw ProviderError(network: network, "\(network.rawValue): account credentials are unavailable")
        }
        try Credentials.store(ref, value: tokens)
    }

    static func requireTokens(accountId: String, network: Network, database: AppDatabase) throws -> OAuthTokens {
        guard let tokens = loadTokens(accountId: accountId, database: database), !tokens.accessToken.isEmpty else {
            throw ProviderError(network: network, "\(network.rawValue): not connected")
        }
        return tokens
    }

    static func tokenExpiringSoon(_ tokens: OAuthTokens, skewMs: Double = 5 * 60 * 1000) -> Bool {
        guard let expiresAt = tokens.expiresAt else { return false }
        return expiresAt - Date().timeIntervalSince1970 * 1000 < skewMs
    }

    static func mediaURL(id: String, database: AppDatabase) throws -> URL {
        guard let relative = try database.media.pathOf(id) else {
            throw ProviderError(network: .x, "Media \(id) not found")
        }
        return MediaStore.fileURL(for: relative)
    }

    static func fileChunks(url: URL, size: Int) throws -> [Data] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var chunks: [Data] = []
        while true {
            let chunk = try handle.read(upToCount: size) ?? Data()
            if chunk.isEmpty { break }
            chunks.append(chunk)
        }
        return chunks
    }
}

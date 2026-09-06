import Foundation

enum ConnectionStore {
    static func storeOAuth(
        network: Network,
        tokens: OAuthTokens,
        accountLabel: String?,
        meta: [String: String] = [:],
        database: AppDatabase
    ) throws {
        let existing = try database.connections.get(network)
        Credentials.delete(ref: existing.credentialRef)
        let ref = Credentials.makeRef(kind: "oauth", owner: network.rawValue)
        try Credentials.store(ref, value: tokens)
        try database.connections.upsert(
            network: network,
            state: .connected,
            credentialRef: ref,
            accountLabel: accountLabel,
            meta: meta,
            error: nil
        )
    }

    static func storeBasic(
        network: Network,
        credentials: BasicCredentials,
        accountLabel: String,
        meta: [String: String] = [:],
        database: AppDatabase
    ) throws {
        let existing = try database.connections.get(network)
        Credentials.delete(ref: existing.credentialRef)
        let ref = Credentials.makeRef(kind: "basic", owner: network.rawValue)
        try Credentials.store(ref, value: credentials)
        try database.connections.upsert(
            network: network,
            state: .connected,
            credentialRef: ref,
            accountLabel: accountLabel,
            meta: meta,
            error: nil
        )
    }

    static func markError(network: Network, error: String, database: AppDatabase) throws {
        try database.connections.upsert(network: network, state: .error, error: error)
    }

    static func disconnect(network: Network, database: AppDatabase) throws {
        let conn = try database.connections.get(network)
        Credentials.delete(ref: conn.credentialRef)
        try database.connections.clear(network)
    }

    static func stashPending(state: String, config: [String: String]) throws {
        try Credentials.store("pending.\(state)", value: config)
    }

    static func popPending(state: String) -> [String: String]? {
        let ref = "pending.\(state)"
        let value = Credentials.read([String: String].self, ref: ref)
        Credentials.delete(ref: ref)
        return value
    }
}

import Foundation

enum ConnectionStore {
    @discardableResult
    static func storeOAuth(
        network: Network,
        tokens: OAuthTokens,
        providerAccountId: String,
        accountLabel: String?,
        meta: [String: String] = [:],
        expectedAccountId: String? = nil,
        database: AppDatabase
    ) throws -> ConnectionInfo {
        try storeCredential(
            kind: "oauth",
            value: tokens,
            network: network,
            providerAccountId: providerAccountId,
            accountLabel: accountLabel,
            meta: meta,
            expectedAccountId: expectedAccountId,
            database: database
        )
    }

    @discardableResult
    static func storeBasic(
        network: Network,
        credentials: BasicCredentials,
        providerAccountId: String,
        accountLabel: String,
        meta: [String: String] = [:],
        expectedAccountId: String? = nil,
        database: AppDatabase
    ) throws -> ConnectionInfo {
        try storeCredential(
            kind: "basic",
            value: credentials,
            network: network,
            providerAccountId: providerAccountId,
            accountLabel: accountLabel,
            meta: meta,
            expectedAccountId: expectedAccountId,
            database: database
        )
    }

    private static func storeCredential<T: Encodable>(
        kind: String,
        value: T,
        network: Network,
        providerAccountId: String,
        accountLabel: String?,
        meta: [String: String],
        expectedAccountId: String?,
        database: AppDatabase
    ) throws -> ConnectionInfo {
        let existing = try targetAccount(
            network: network,
            providerAccountId: providerAccountId,
            expectedAccountId: expectedAccountId,
            database: database
        )
        let accountId = existing?.id ?? Time.newId()
        let ref = Credentials.makeRef(kind: kind, owner: accountId)
        try Credentials.store(ref, value: value)
        do {
            try database.connections.upsert(
                accountId: accountId,
                network: network,
                providerAccountId: providerAccountId,
                state: .connected,
                credentialRef: ref,
                accountLabel: accountLabel,
                meta: meta,
                error: nil
            )
        } catch {
            Credentials.delete(ref: ref)
            throw error
        }
        Credentials.delete(ref: existing?.credentialRef)
        guard let stored = try database.connections.get(accountId) else {
            throw ProviderError(network: network, "\(network.rawValue): failed to store account")
        }
        return stored
    }

    static func markError(accountId: String, error: String, database: AppDatabase) throws {
        guard let account = try database.connections.get(accountId) else { return }
        try database.connections.upsert(
            accountId: account.id,
            network: account.network,
            providerAccountId: account.providerAccountId,
            state: .error,
            accountLabel: account.accountLabel,
            meta: account.meta,
            error: error
        )
    }

    static func disconnect(accountId: String, database: AppDatabase) throws {
        guard let conn = try database.connections.get(accountId) else { return }
        Credentials.delete(ref: conn.credentialRef)
        try database.connections.clear(accountId)
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

    private static func targetAccount(
        network: Network,
        providerAccountId: String,
        expectedAccountId: String?,
        database: AppDatabase
    ) throws -> ConnectionInfo? {
        if let expectedAccountId {
            guard let expected = try database.connections.get(expectedAccountId),
                  expected.network == network
            else {
                throw ProviderError(network: network, "\(network.rawValue): account no longer exists")
            }
            if let storedIdentity = expected.providerAccountId,
               storedIdentity != providerAccountId
            {
                throw ProviderError(
                    network: network,
                    "\(network.rawValue): the authorized account does not match \(expected.accountLabel ?? "the selected account")"
                )
            }
            if let duplicate = try database.connections.find(
                network: network,
                providerAccountId: providerAccountId
            ), duplicate.id != expected.id {
                throw ProviderError(
                    network: network,
                    "\(network.rawValue): this identity is already connected as \(duplicate.accountLabel ?? "another account")"
                )
            }
            return expected
        }
        return try database.connections.find(network: network, providerAccountId: providerAccountId)
    }
}

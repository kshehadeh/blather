import Foundation

struct AccountConnectSettings: Hashable, Sendable {
    var clientId: String = ""
    var pds: String = AccountSettings.defaultPDS
    var handle: String = ""
    var hasStoredSecret: Bool = false
}

enum AccountSavePlan: Equatable, Sendable {
    case noOp
    case reconnectBluesky(pds: String, handle: String, appPassword: String)
    case reconnectX(clientId: String)
    case reconnectThreads(clientId: String, clientSecret: String)
    case reconnectInstagram(clientId: String, clientSecret: String)
}

enum AccountSettings {
    static let defaultPDS = "https://bsky.social"

    static func load(network: Network, database: AppDatabase) -> AccountConnectSettings {
        let conn = (try? database.connections.get(network))
            ?? ConnectionInfo(network: network, state: .disconnected, meta: [:])
        switch network {
        case .bluesky:
            let creds = Credentials.read(BasicCredentials.self, ref: conn.credentialRef)
            let pds = normalizePDS(conn.meta["pds"] ?? creds?.meta?["pds"] ?? defaultPDS)
            let identifier = creds?.identifier.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let handle = identifier.isEmpty ? handle(from: conn.accountLabel) : identifier
            return AccountConnectSettings(
                pds: pds,
                handle: handle,
                hasStoredSecret: !(creds?.secret ?? "").isEmpty
            )
        case .x, .threads, .instagram:
            let tokens = TokenAccess.loadTokens(network: network, database: database)
            return AccountConnectSettings(
                clientId: tokens?.meta?["clientId"] ?? "",
                hasStoredSecret: !(tokens?.accessToken ?? "").isEmpty
            )
        }
    }

    static func plan(
        network: Network,
        clientId: String,
        clientSecret: String,
        pds: String,
        handle: String,
        appPassword: String,
        stored: AccountConnectSettings,
        storedAppPassword: String?,
        storedClientSecret: String?
    ) -> AccountSavePlan {
        let clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let pds = normalizePDS(pds)

        switch network {
        case .x:
            if clientId.isEmpty || clientId == stored.clientId { return .noOp }
            return .reconnectX(clientId: clientId)
        case .bluesky:
            let storedPDS = normalizePDS(stored.pds)
            if handle == stored.handle, pds == storedPDS, appPassword.isEmpty {
                return .noOp
            }
            let password = appPassword.isEmpty ? (storedAppPassword ?? "") : appPassword
            if handle.isEmpty || password.isEmpty { return .noOp }
            return .reconnectBluesky(pds: pds, handle: handle, appPassword: password)
        case .threads:
            if clientId == stored.clientId, clientSecret.isEmpty { return .noOp }
            let secret = clientSecret.isEmpty ? (storedClientSecret ?? "") : clientSecret
            if clientId.isEmpty || secret.isEmpty { return .noOp }
            return .reconnectThreads(clientId: clientId, clientSecret: secret)
        case .instagram:
            if clientId == stored.clientId, clientSecret.isEmpty { return .noOp }
            let secret = clientSecret.isEmpty ? (storedClientSecret ?? "") : clientSecret
            if clientId.isEmpty || secret.isEmpty { return .noOp }
            return .reconnectInstagram(clientId: clientId, clientSecret: secret)
        }
    }

    static func normalizePDS(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? defaultPDS : trimmed
        return base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func handle(from accountLabel: String?) -> String {
        guard let accountLabel, !accountLabel.isEmpty else { return "" }
        return accountLabel.hasPrefix("@") ? String(accountLabel.dropFirst()) : accountLabel
    }
}

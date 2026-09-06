import AppKit
import Foundation

enum ConnectService {
    static let callbackTimeout: TimeInterval = 120

    static func connectX(clientId: String, database: AppDatabase) async throws {
        let pkce = PKCE.generate()
        let state = PKCE.state()
        try database.oauthStates.create(provider: "x", state: state, verifier: pkce.verifier)
        try ConnectionStore.stashPending(state: state, config: ["clientId": clientId])
        let redirect = "\(OAuthCallbackServer.origin)/api/connect/x/callback"
        var url = URLComponents(string: "https://x.com/i/oauth2/authorize")!
        url.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: "tweet.read tweet.write users.read offline.access media.write"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        try await runBrowserFlow(authorizeURL: url.url!, title: "X", database: database) { callback in
            try await completeX(url: callback, database: database)
        }
    }

    static func connectThreads(clientId: String, clientSecret: String, database: AppDatabase) async throws {
        try await connectMeta(
            network: .threads,
            authorizeBase: "https://threads.net/oauth/authorize",
            scope: "threads_basic,threads_content_publish",
            clientId: clientId,
            clientSecret: clientSecret,
            database: database
        )
    }

    static func connectInstagram(clientId: String, clientSecret: String, database: AppDatabase) async throws {
        try await connectMeta(
            network: .instagram,
            authorizeBase: "https://www.instagram.com/oauth/authorize",
            scope: "instagram_business_basic,instagram_business_content_publish",
            clientId: clientId,
            clientSecret: clientSecret,
            database: database
        )
    }

    static func connectBluesky(pds: String, handle: String, appPassword: String, database: AppDatabase) async throws {
        let trimmed = pds.isEmpty ? "https://bsky.social" : pds.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let session = try await BlueskyAdapter.createSession(pds: trimmed, identifier: handle, appPassword: appPassword)
        try ConnectionStore.storeBasic(
            network: .bluesky,
            credentials: BasicCredentials(
                identifier: handle,
                secret: appPassword,
                meta: ["pds": trimmed, "did": session.did],
                accessJwt: session.accessJwt,
                refreshJwt: session.refreshJwt
            ),
            accountLabel: "@\(session.handle)",
            meta: ["pds": trimmed, "did": session.did],
            database: database
        )
    }

    static func disconnect(network: Network, database: AppDatabase) throws {
        try ConnectionStore.disconnect(network: network, database: database)
    }

    static func runHealthChecks(database: AppDatabase) async {
        for network in Network.allCases {
            let state = (try? database.connections.get(network).state) ?? .disconnected
            guard state != .disconnected else { continue }
            let adapter = AdapterRegistry.adapter(for: network, database: database)
            let result = await adapter.health()
            if result.ok {
                let existing = (try? database.connections.get(network))?.meta ?? [:]
                try? database.connections.upsert(
                    network: network,
                    state: .connected,
                    accountLabel: result.accountLabel,
                    meta: result.meta.isEmpty ? existing : result.meta,
                    error: nil
                )
            } else {
                try? ConnectionStore.markError(
                    network: network,
                    error: result.error ?? "Health check failed",
                    database: database
                )
            }
        }
    }

    private static func connectMeta(
        network: Network,
        authorizeBase: String,
        scope: String,
        clientId: String,
        clientSecret: String,
        database: AppDatabase
    ) async throws {
        let state = PKCE.state()
        try database.oauthStates.create(provider: network.rawValue, state: state, verifier: "pkce-not-used")
        try ConnectionStore.stashPending(state: state, config: ["clientId": clientId, "clientSecret": clientSecret])
        let redirect = "\(OAuthCallbackServer.origin)/api/connect/\(network.rawValue)/callback"
        var url = URLComponents(string: authorizeBase)!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
        ]
        try await runBrowserFlow(authorizeURL: url.url!, title: network.title, database: database) { callback in
            if network == .threads {
                try await completeThreads(url: callback, database: database)
            } else {
                try await completeInstagram(url: callback, database: database)
            }
        }
    }

    private static func runBrowserFlow(
        authorizeURL: URL,
        title: String,
        database: AppDatabase,
        complete: @escaping (URL) async throws -> Void
    ) async throws {
        let server = OAuthCallbackServer()
        defer { server.stop() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = CompletionBox(continuation: continuation)
            do {
                try server.start { incoming in
                    do {
                        try await complete(incoming)
                        box.resume(with: .success(()))
                        return oauthResultHTML(network: title, error: nil)
                    } catch {
                        box.resume(with: .failure(error))
                        return oauthResultHTML(network: title, error: error.localizedDescription)
                    }
                }
            } catch {
                box.resume(with: .failure(error))
                return
            }
            NSWorkspace.shared.open(authorizeURL)
            DispatchQueue.global().asyncAfter(deadline: .now() + callbackTimeout) {
                box.resume(with: .failure(OAuthServerError.timeout))
            }
        }
    }

    private static func completeX(url: URL, database: AppDatabase) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
        if let error = query["error"] { throw OAuthServerError.denied("x: authorization denied (\(error))") }
        guard let code = query["code"], let state = query["state"] else { throw OAuthServerError.missingCode }
        guard let verifier = try database.oauthStates.consume(provider: "x", state: state) else {
            throw OAuthServerError.invalidState
        }
        guard let config = ConnectionStore.popPending(state: state), let clientId = config["clientId"] else {
            throw OAuthServerError.missingConfig
        }
        let redirect = "\(OAuthCallbackServer.origin)/api/connect/x/callback"
        let tokenRes = try await ProviderHTTP.fetchJSON(
            network: .x,
            url: URL(string: "https://api.x.com/2/oauth2/token")!,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: ProviderHTTP.form([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirect,
                "code_verifier": verifier,
                "client_id": clientId,
            ])
        )
        let access = JSONValue.string(tokenRes, "access_token") ?? ""
        let refresh = JSONValue.string(tokenRes, "refresh_token")
        let expires = Double(JSONValue.string(tokenRes, "expires_in") ?? "7200") ?? 7200
        let me = try await ProviderHTTP.fetchJSON(
            network: .x,
            url: URL(string: "https://api.x.com/2/users/me")!,
            headers: ["Authorization": "Bearer \(access)"]
        )
        let username = JSONValue.string(me, "data", "username")
        let userId = JSONValue.string(me, "data", "id") ?? ""
        try ConnectionStore.storeOAuth(
            network: .x,
            tokens: OAuthTokens(
                accessToken: access,
                refreshToken: refresh,
                expiresAt: Date().timeIntervalSince1970 * 1000 + expires * 1000,
                meta: ["clientId": clientId, "userId": userId, "username": username ?? ""]
            ),
            accountLabel: username.map { "@\($0)" },
            meta: ["userId": userId],
            database: database
        )
    }

    private static func completeThreads(url: URL, database: AppDatabase) async throws {
        let query = queryItems(url)
        if let error = query["error"] { throw OAuthServerError.denied("threads: authorization denied (\(error))") }
        guard let code = query["code"], let state = query["state"] else { throw OAuthServerError.missingCode }
        _ = try database.oauthStates.consume(provider: "threads", state: state)
        guard let config = ConnectionStore.popPending(state: state),
              let clientId = config["clientId"],
              let clientSecret = config["clientSecret"]
        else { throw OAuthServerError.missingConfig }
        let redirect = "\(OAuthCallbackServer.origin)/api/connect/threads/callback"
        let shortRes = try await ProviderHTTP.fetchJSON(
            network: .threads,
            url: URL(string: "https://graph.threads.net/oauth/access_token")!,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: ProviderHTTP.form([
                "client_id": clientId,
                "client_secret": clientSecret,
                "grant_type": "authorization_code",
                "redirect_uri": redirect,
                "code": code,
            ])
        )
        let shortToken = JSONValue.string(shortRes, "access_token") ?? ""
        let longRes = try await ProviderHTTP.fetchJSON(
            network: .threads,
            url: URL(string: "https://graph.threads.net/access_token?grant_type=th_exchange_token&client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&access_token=\(shortToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        )
        let access = JSONValue.string(longRes, "access_token") ?? shortToken
        let expires = Double(JSONValue.string(longRes, "expires_in") ?? "5184000") ?? 5_184_000
        let me = try await ProviderHTTP.fetchJSON(
            network: .threads,
            url: URL(string: "https://graph.threads.net/v1.0/me?fields=id,username&access_token=\(access.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        )
        let userId = JSONValue.string(me, "id") ?? ""
        let username = JSONValue.string(me, "username")
        try ConnectionStore.storeOAuth(
            network: .threads,
            tokens: OAuthTokens(
                accessToken: access,
                expiresAt: Date().timeIntervalSince1970 * 1000 + expires * 1000,
                meta: ["clientId": clientId, "clientSecret": clientSecret, "userId": userId]
            ),
            accountLabel: username.map { "@\($0)" },
            meta: ["userId": userId],
            database: database
        )
    }

    private static func completeInstagram(url: URL, database: AppDatabase) async throws {
        let query = queryItems(url)
        if let error = query["error"] { throw OAuthServerError.denied("instagram: authorization denied (\(error))") }
        guard var code = query["code"], let state = query["state"] else { throw OAuthServerError.missingCode }
        if code.hasSuffix("#_") { code = String(code.dropLast(2)) }
        _ = try database.oauthStates.consume(provider: "instagram", state: state)
        guard let config = ConnectionStore.popPending(state: state),
              let clientId = config["clientId"],
              let clientSecret = config["clientSecret"]
        else { throw OAuthServerError.missingConfig }
        let redirect = "\(OAuthCallbackServer.origin)/api/connect/instagram/callback"
        let shortRes = try await ProviderHTTP.fetchJSON(
            network: .instagram,
            url: URL(string: "https://api.instagram.com/oauth/access_token")!,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: ProviderHTTP.form([
                "client_id": clientId,
                "client_secret": clientSecret,
                "grant_type": "authorization_code",
                "redirect_uri": redirect,
                "code": code,
            ])
        )
        let shortToken = JSONValue.string(shortRes, "access_token") ?? ""
        let shortUserId = JSONValue.string(shortRes, "user_id") ?? ""
        let longRes = try await ProviderHTTP.fetchJSON(
            network: .instagram,
            url: URL(string: "https://graph.instagram.com/access_token?grant_type=ig_exchange_token&client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&access_token=\(shortToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        )
        let access = JSONValue.string(longRes, "access_token") ?? shortToken
        let expires = Double(JSONValue.string(longRes, "expires_in") ?? "5184000") ?? 5_184_000
        let me = try await ProviderHTTP.fetchJSON(
            network: .instagram,
            url: URL(string: "https://graph.instagram.com/v21.0/me?fields=user_id,username,account_type&access_token=\(access.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        )
        let igUserId = JSONValue.string(me, "user_id") ?? shortUserId
        let username = JSONValue.string(me, "username")
        let accountType = JSONValue.string(me, "account_type") ?? "unknown"
        try ConnectionStore.storeOAuth(
            network: .instagram,
            tokens: OAuthTokens(
                accessToken: access,
                expiresAt: Date().timeIntervalSince1970 * 1000 + expires * 1000,
                meta: ["clientId": clientId, "clientSecret": clientSecret, "igUserId": igUserId]
            ),
            accountLabel: username.map { "@\($0)" },
            meta: ["igUserId": igUserId, "accountType": accountType],
            database: database
        )
    }

    private static func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
    }
}

private final class CompletionBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Void, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        guard let cont else { return }
        switch result {
        case .success: cont.resume()
        case .failure(let error): cont.resume(throwing: error)
        }
    }
}

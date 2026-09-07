import Foundation

struct ThreadsAdapter: ProviderAdapter {
    let accountId: String
    let database: AppDatabase
    var network: Network { .threads }

    private let graph = "https://graph.threads.net/v1.0"

    func isConnected() -> Bool {
        TokenAccess.loadTokens(accountId: accountId, database: database)?.accessToken.isEmpty == false
    }

    func refreshIfNeeded() async throws {
        let tokens = TokenAccess.loadTokens(accountId: accountId, database: database)
        guard let tokens, TokenAccess.tokenExpiringSoon(tokens, skewMs: 24 * 60 * 60 * 1000) else { return }
        let url = URL(string: "https://graph.threads.net/refresh_access_token?grant_type=th_refresh_token&access_token=\(tokens.accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tokens.accessToken)")!
        let res = try await ProviderHTTP.fetchJSON(network: .threads, url: url)
        if let access = JSONValue.string(res, "access_token") {
            var next = tokens
            next.accessToken = access
            if let expires = JSONValue.string(res, "expires_in"), let seconds = Double(expires) {
                next.expiresAt = Date().timeIntervalSince1970 * 1000 + seconds * 1000
            }
            try TokenAccess.saveTokens(accountId: accountId, network: .threads, tokens: next, database: database)
        }
    }

    func validate(content: ResolvedContent) throws {
        try ContentValidation.validate(.threads, content: content)
    }

    func publish(content: ResolvedContent, context: any PublishContext) async throws -> PublishResult {
        try await refreshIfNeeded()
        let tokens = try TokenAccess.requireTokens(accountId: accountId, network: .threads, database: database)
        guard let userId = tokens.meta?["userId"], !userId.isEmpty else {
            throw ProviderError(network: .threads, "threads: missing user id; reconnect")
        }
        var staged: [String] = []
        defer {
            Task {
                for key in staged {
                    await context.removeStaged(key: key)
                }
            }
        }
        let creationId = try await createContainer(
            content: content,
            context: context,
            userId: userId,
            accessToken: tokens.accessToken,
            staged: &staged
        )
        try await waitForContainer(creationId, accessToken: tokens.accessToken)
        let res = try await ProviderHTTP.fetchJSON(
            network: .threads,
            url: URL(string: "\(graph)/\(userId)/threads_publish")!,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: ProviderHTTP.form(["creation_id": creationId, "access_token": tokens.accessToken])
        )
        let id = JSONValue.string(res, "id")
        return await GraphPermalink.publishResult(
            network: .threads,
            graphBase: graph,
            mediaId: id,
            accessToken: tokens.accessToken
        )
    }

    func lookupPermalink(mediaId: String) async -> String? {
        try? await refreshIfNeeded()
        guard let tokens = TokenAccess.loadTokens(accountId: accountId, database: database),
              !tokens.accessToken.isEmpty
        else { return nil }
        return await GraphPermalink.fetch(
            network: .threads,
            graphBase: graph,
            mediaId: mediaId,
            accessToken: tokens.accessToken,
            attempts: 1
        )
    }

    func normalizeError(_ error: Error) -> String {
        ProviderErrors.sanitize(network: .threads, error)
    }

    func health() async -> HealthResult {
        do {
            try await refreshIfNeeded()
            let tokens = try TokenAccess.requireTokens(accountId: accountId, network: .threads, database: database)
            let res = try await ProviderHTTP.fetchJSON(
                network: .threads,
                url: URL(string: "\(graph)/me?fields=id,username&access_token=\(tokens.accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
            )
            let userId = JSONValue.string(res, "id")
            let username = JSONValue.string(res, "username")
            return HealthResult(
                ok: true,
                accountLabel: username.map { "@\($0)" },
                meta: userId.map { ["userId": $0] } ?? [:],
                error: nil
            )
        } catch {
            return HealthResult(ok: false, meta: [:], error: normalizeError(error))
        }
    }

    private func createContainer(
        content: ResolvedContent,
        context: any PublishContext,
        userId: String,
        accessToken: String,
        staged: inout [String]
    ) async throws -> String {
        func post(_ params: [String: String]) async throws -> String {
            let res = try await ProviderHTTP.fetchJSON(
                network: .threads,
                url: URL(string: "\(graph)/\(userId)/threads")!,
                method: "POST",
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: ProviderHTTP.form(params.merging(["access_token": accessToken]) { _, new in new })
            )
            return JSONValue.string(res, "id") ?? ""
        }
        func stage(_ mediaId: String) async throws -> String {
            let result = try await context.stageMedia(mediaId: mediaId, attemptId: context.attemptId)
            staged.append(result.key)
            return result.url
        }

        if content.media.isEmpty {
            return try await post(["media_type": "TEXT", "text": content.text])
        }
        if content.media.count == 1, let video = content.media.first(where: { $0.kind == .video }) {
            return try await post(["media_type": "VIDEO", "video_url": try await stage(video.id), "text": content.text])
        }
        if content.media.count == 1, let image = content.media.first {
            return try await post(["media_type": "IMAGE", "image_url": try await stage(image.id), "text": content.text])
        }
        var children: [String] = []
        for item in content.media {
            let url = try await stage(item.id)
            children.append(
                try await post(
                    item.kind == .video
                        ? ["media_type": "VIDEO", "video_url": url, "is_carousel_item": "true"]
                        : ["media_type": "IMAGE", "image_url": url, "is_carousel_item": "true"]
                )
            )
        }
        var parent = ["media_type": "CAROUSEL", "children": children.joined(separator: ",")]
        if !content.text.isEmpty { parent["text"] = content.text }
        return try await post(parent)
    }

    private func waitForContainer(_ containerId: String, accessToken: String) async throws {
        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            let res = try await ProviderHTTP.fetchJSON(
                network: .threads,
                url: URL(string: "\(graph)/\(containerId)?fields=status&access_token=\(accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
            )
            let status = JSONValue.string(res, "status")
            if status == "FINISHED" { return }
            if status == "ERROR" || status == "EXPIRED" {
                throw ProviderError(network: .threads, "threads: media container failed (\(status ?? "ERROR"))")
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw ProviderError(network: .threads, "threads: media processing timed out")
    }
}

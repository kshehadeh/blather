import Foundation

struct InstagramAdapter: ProviderAdapter {
    let database: AppDatabase
    var network: Network { .instagram }

    private let graph = "https://graph.instagram.com/v21.0"

    func isConnected() -> Bool {
        TokenAccess.loadTokens(network: .instagram, database: database)?.accessToken.isEmpty == false
    }

    func refreshIfNeeded() async throws {
        let tokens = TokenAccess.loadTokens(network: .instagram, database: database)
        guard let tokens, TokenAccess.tokenExpiringSoon(tokens, skewMs: 24 * 60 * 60 * 1000) else { return }
        let url = URL(string: "https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=\(tokens.accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        let res = try await ProviderHTTP.fetchJSON(network: .instagram, url: url)
        if let access = JSONValue.string(res, "access_token") {
            var next = tokens
            next.accessToken = access
            if let expires = JSONValue.string(res, "expires_in"), let seconds = Double(expires) {
                next.expiresAt = Date().timeIntervalSince1970 * 1000 + seconds * 1000
            }
            try TokenAccess.saveTokens(network: .instagram, tokens: next, database: database)
        }
    }

    func validate(content: ResolvedContent) throws {
        try ContentValidation.validate(.instagram, content: content)
        for video in content.media.filter({ $0.kind == .video }) {
            if let duration = video.durationSeconds, duration < 3 || duration > 900 {
                throw ProviderError(network: .instagram, "instagram: video must be 3-900 seconds long")
            }
            if let width = video.width, let height = video.height, height > 0 {
                let ratio = Double(width) / Double(height)
                if ratio < 0.01 || ratio > 10 {
                    throw ProviderError(network: .instagram, "instagram: video aspect ratio out of range")
                }
            }
        }
    }

    func publish(content: ResolvedContent, context: any PublishContext) async throws -> PublishResult {
        try await refreshIfNeeded()
        let tokens = try TokenAccess.requireTokens(network: .instagram, database: database)
        guard let igUserId = tokens.meta?["igUserId"], !igUserId.isEmpty else {
            throw ProviderError(network: .instagram, "instagram: missing user id; reconnect")
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
            igUserId: igUserId,
            accessToken: tokens.accessToken,
            staged: &staged
        )
        try await waitForContainer(creationId, accessToken: tokens.accessToken)
        let res = try await ProviderHTTP.fetchJSON(
            network: .instagram,
            url: URL(string: "\(graph)/\(igUserId)/media_publish")!,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: ProviderHTTP.form(["creation_id": creationId, "access_token": tokens.accessToken])
        )
        let id = JSONValue.string(res, "id")
        return await GraphPermalink.publishResult(
            network: .instagram,
            graphBase: graph,
            mediaId: id,
            accessToken: tokens.accessToken
        )
    }

    func lookupPermalink(mediaId: String) async -> String? {
        try? await refreshIfNeeded()
        guard let tokens = TokenAccess.loadTokens(network: .instagram, database: database),
              !tokens.accessToken.isEmpty
        else { return nil }
        return await GraphPermalink.fetch(
            network: .instagram,
            graphBase: graph,
            mediaId: mediaId,
            accessToken: tokens.accessToken,
            attempts: 1
        )
    }

    func normalizeError(_ error: Error) -> String {
        ProviderErrors.sanitize(network: .instagram, error)
    }

    func health() async -> HealthResult {
        do {
            try await refreshIfNeeded()
            let tokens = try TokenAccess.requireTokens(network: .instagram, database: database)
            let res = try await ProviderHTTP.fetchJSON(
                network: .instagram,
                url: URL(string: "\(graph)/me?fields=user_id,username,account_type&access_token=\(tokens.accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
            )
            let username = JSONValue.string(res, "username")
            let accountType = JSONValue.string(res, "account_type")
            var meta: [String: String] = [:]
            if let accountType { meta["accountType"] = accountType }
            let normalized = accountType?.uppercased()
            let isProfessional = normalized == nil
                || normalized == "BUSINESS"
                || normalized == "CREATOR"
                || normalized == "MEDIA_CREATOR"
            if !isProfessional {
                return HealthResult(
                    ok: false,
                    accountLabel: username.map { "@\($0)" },
                    meta: meta,
                    error: "instagram: publishing requires a professional (Business/Creator) account"
                )
            }
            return HealthResult(ok: true, accountLabel: username.map { "@\($0)" }, meta: meta, error: nil)
        } catch {
            return HealthResult(ok: false, meta: [:], error: normalizeError(error))
        }
    }

    private func createContainer(
        content: ResolvedContent,
        context: any PublishContext,
        igUserId: String,
        accessToken: String,
        staged: inout [String]
    ) async throws -> String {
        func post(_ params: [String: String]) async throws -> String {
            let res = try await ProviderHTTP.fetchJSON(
                network: .instagram,
                url: URL(string: "\(graph)/\(igUserId)/media")!,
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

        if content.media.count == 1, let video = content.media.first(where: { $0.kind == .video }) {
            return try await post(["media_type": "REELS", "video_url": try await stage(video.id), "caption": content.text])
        }
        if content.media.count == 1, let image = content.media.first {
            return try await post(["image_url": try await stage(image.id), "caption": content.text])
        }
        var children: [String] = []
        for item in content.media {
            let url = try await stage(item.id)
            children.append(
                try await post(
                    item.kind == .video
                        ? ["media_type": "VIDEO", "video_url": url, "is_carousel_item": "true"]
                        : ["image_url": url, "is_carousel_item": "true"]
                )
            )
        }
        return try await post(["media_type": "CAROUSEL", "children": children.joined(separator: ","), "caption": content.text])
    }

    private func waitForContainer(_ containerId: String, accessToken: String) async throws {
        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            let res = try await ProviderHTTP.fetchJSON(
                network: .instagram,
                url: URL(string: "\(graph)/\(containerId)?fields=status_code&access_token=\(accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
            )
            let status = JSONValue.string(res, "status_code")
            if status == "FINISHED" { return }
            if status == "ERROR" || status == "EXPIRED" {
                throw ProviderError(network: .instagram, "instagram: media container failed")
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw ProviderError(network: .instagram, "instagram: media processing timed out")
    }
}

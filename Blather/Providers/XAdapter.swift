import Foundation

struct XAdapter: ProviderAdapter {
    let accountId: String
    let database: AppDatabase
    var network: Network { .x }

    private let api = URL(string: "https://api.x.com")!
    private let chunkSize = 4 * 1024 * 1024

    func isConnected() -> Bool {
        TokenAccess.loadTokens(accountId: accountId, database: database)?.accessToken.isEmpty == false
    }

    func refreshIfNeeded() async throws {
        let tokens = TokenAccess.loadTokens(accountId: accountId, database: database)
        guard let tokens, let refresh = tokens.refreshToken, TokenAccess.tokenExpiringSoon(tokens) else { return }
        guard let clientId = tokens.meta?["clientId"] else {
            throw ProviderError(network: .x, "x: missing client id for token refresh")
        }
        let body = try await ProviderHTTP.fetchJSON(
            network: .x,
            url: api.appendingPathComponent("2/oauth2/token"),
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: ProviderHTTP.form([
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "client_id": clientId,
            ])
        )
        var next = tokens
        next.accessToken = JSONValue.string(body, "access_token") ?? tokens.accessToken
        next.refreshToken = JSONValue.string(body, "refresh_token") ?? tokens.refreshToken
        if let expires = JSONValue.string(body, "expires_in"), let seconds = Double(expires) {
            next.expiresAt = Date().timeIntervalSince1970 * 1000 + seconds * 1000
        }
        try TokenAccess.saveTokens(accountId: accountId, network: .x, tokens: next, database: database)
    }

    func validate(content: ResolvedContent) throws {
        try ContentValidation.validate(.x, content: content)
    }

    func publish(content: ResolvedContent, context: any PublishContext) async throws -> PublishResult {
        try await refreshIfNeeded()
        let tokens = try TokenAccess.requireTokens(accountId: accountId, network: .x, database: database)
        let auth = ["Authorization": "Bearer \(tokens.accessToken)"]
        var mediaIds: [String] = []
        for item in content.media {
            mediaIds.append(try await uploadMedia(auth: auth, item: item))
        }
        var payload: [String: Any] = ["text": content.text]
        if !mediaIds.isEmpty {
            payload["media"] = ["media_ids": mediaIds]
        }
        if content.text.isEmpty, !mediaIds.isEmpty {
            payload["text"] = ""
        }
        let res = try await ProviderHTTP.fetchJSON(
            network: .x,
            url: api.appendingPathComponent("2/tweets"),
            method: "POST",
            headers: auth.merging(["Content-Type": "application/json"]) { _, new in new },
            body: try JSONSerialization.data(withJSONObject: payload)
        )
        let id = JSONValue.string(res, "data", "id")
        let username = tokens.meta?["username"]
        let postURL: String?
        if let id, let username, !username.isEmpty {
            postURL = "https://x.com/\(username)/status/\(id)"
        } else {
            postURL = nil
        }
        return PublishResult(providerPostId: id, providerPostUrl: postURL)
    }

    func normalizeError(_ error: Error) -> String {
        ProviderErrors.sanitize(network: .x, error)
    }

    func health() async -> HealthResult {
        do {
            try await refreshIfNeeded()
            let tokens = try TokenAccess.requireTokens(accountId: accountId, network: .x, database: database)
            let res = try await ProviderHTTP.fetchJSON(
                network: .x,
                url: api.appendingPathComponent("2/users/me"),
                headers: ["Authorization": "Bearer \(tokens.accessToken)"]
            )
            let username = JSONValue.string(res, "data", "username")
            let userId = JSONValue.string(res, "data", "id")
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

    private func uploadMedia(auth: [String: String], item: MediaItem) async throws -> String {
        do {
            let url = try TokenAccess.mediaURL(id: item.id, database: database)
            let total = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? item.size
            let category = item.kind == .video ? "tweet_video" : item.mimeType == "image/gif" ? "tweet_gif" : "tweet_image"
            let initRes = try await ProviderHTTP.fetchJSON(
                network: .x,
                url: api.appendingPathComponent("2/media/upload/initialize"),
                method: "POST",
                headers: auth.merging(["Content-Type": "application/json"]) { _, new in new },
                body: try JSONSerialization.data(withJSONObject: [
                    "total_bytes": total,
                    "media_type": item.mimeType,
                    "media_category": category,
                ])
            )
            guard let uploadId = JSONValue.string(initRes, "data", "id"), !uploadId.isEmpty else {
                throw ProviderError(network: .x, "x: media upload did not return an id")
            }
            let chunks = try TokenAccess.fileChunks(url: url, size: chunkSize)
            for (segment, chunk) in chunks.enumerated() {
                let multipart = MultipartForm.body(
                    fields: [
                        "command": "APPEND",
                        "media_id": uploadId,
                        "segment_index": String(segment),
                    ],
                    fileName: "chunk",
                    fileType: item.mimeType,
                    fileData: chunk
                )
                _ = try await ProviderHTTP.fetchJSON(
                    network: .x,
                    url: api.appendingPathComponent("2/media/upload/\(uploadId)/append"),
                    method: "POST",
                    headers: auth.merging(["Content-Type": multipart.contentType]) { _, new in new },
                    body: multipart.data
                )
            }
            let finRes = try await ProviderHTTP.fetchJSON(
                network: .x,
                url: api.appendingPathComponent("2/media/upload/\(uploadId)/finalize"),
                method: "POST",
                headers: auth
            )
            let finData = JSONValue.object(JSONValue.object(finRes)["data"])
            guard finData["id"] != nil else {
                throw ProviderError(network: .x, "x: media upload did not return an id")
            }
            if let processing = finData["processing_info"] as? [String: Any] {
                try await waitForProcessing(auth: auth, mediaId: uploadId, initial: processing)
            }
            return uploadId
        } catch let error as ProviderError where error.status == 403 {
            throw ProviderError(
                network: .x,
                "x: media upload was denied. Reconnect X to grant the media.write permission, then try again.",
                status: 403
            )
        }
    }

    private func waitForProcessing(auth: [String: String], mediaId: String, initial: [String: Any]) async throws {
        var info = initial
        let deadline = Date().addingTimeInterval(10 * 60)
        while ["pending", "in_progress"].contains(info["state"] as? String ?? "") {
            if Date() > deadline {
                throw ProviderError(network: .x, "x: media processing timed out")
            }
            let wait = (info["check_after_secs"] as? NSNumber)?.doubleValue ?? 5
            try await Task.sleep(for: .seconds(wait))
            let res = try await ProviderHTTP.fetchJSON(
                network: .x,
                url: URL(string: "https://api.x.com/2/media/upload?media_id=\(mediaId)")!,
                headers: auth
            )
            guard let next = JSONValue.object(JSONValue.object(res)["data"])["processing_info"] as? [String: Any] else {
                throw ProviderError(network: .x, "x: media processing status was unavailable")
            }
            info = next
            if info["state"] as? String == "failed" {
                throw ProviderError(network: .x, "x: media processing failed")
            }
        }
    }
}

import Foundation

struct LinkedInAdapter: ProviderAdapter {
    let accountId: String
    let database: AppDatabase
    var network: Network { .linkedin }

    /// Pinned version of LinkedIn's versioned REST gateway. Versions are
    /// supported for at least a year; bump this when migrating.
    static let apiVersion = "202608"

    private let rest = URL(string: "https://api.linkedin.com/rest")!
    private let userinfo = URL(string: "https://api.linkedin.com/v2/userinfo")!

    func isConnected() -> Bool {
        TokenAccess.loadTokens(accountId: accountId, database: database)?.accessToken.isEmpty == false
    }

    /// Self-serve LinkedIn apps receive 60-day access tokens with no refresh
    /// token, so an expired session can only be fixed by reconnecting.
    func refreshIfNeeded() async throws {
        let tokens = TokenAccess.loadTokens(accountId: accountId, database: database)
        guard let tokens else { return }
        guard TokenAccess.tokenExpiringSoon(tokens, skewMs: 0) else { return }
        throw ProviderError(
            network: .linkedin,
            "linkedin: the LinkedIn session has expired. Reconnect LinkedIn to publish again."
        )
    }

    func validate(content: ResolvedContent) throws {
        try ContentValidation.validate(.linkedin, content: content)
    }

    func publish(content: ResolvedContent, context: any PublishContext) async throws -> PublishResult {
        do {
            return try await publishPost(content: content)
        } catch let error as ProviderError where error.status == 401 {
            throw ProviderError(
                network: .linkedin,
                "linkedin: \(error.message). Reconnect LinkedIn to publish again.",
                status: 401
            )
        }
    }

    func normalizeError(_ error: Error) -> String {
        ProviderErrors.sanitize(network: .linkedin, error)
    }

    func health() async -> HealthResult {
        do {
            try await refreshIfNeeded()
            let tokens = try TokenAccess.requireTokens(accountId: accountId, network: .linkedin, database: database)
            let res = try await ProviderHTTP.fetchJSON(
                network: .linkedin,
                url: userinfo,
                headers: authHeaders(tokens.accessToken)
            )
            let sub = JSONValue.string(res, "sub")
            let name = JSONValue.string(res, "name")
            return HealthResult(
                ok: true,
                accountLabel: name ?? "LinkedIn member",
                meta: sub.map { ["userId": $0] } ?? [:],
                error: nil
            )
        } catch {
            return HealthResult(ok: false, meta: [:], error: normalizeError(error))
        }
    }

    private func publishPost(content: ResolvedContent) async throws -> PublishResult {
        try await refreshIfNeeded()
        let tokens = try TokenAccess.requireTokens(accountId: accountId, network: .linkedin, database: database)
        guard let sub = tokens.meta?["userId"], !sub.isEmpty else {
            throw ProviderError(network: .linkedin, "linkedin: missing member id; reconnect LinkedIn")
        }
        let author = "urn:li:person:\(sub)"

        var postContent: [String: Any]?
        let images = content.media.filter { $0.kind == .image }
        let videos = content.media.filter { $0.kind == .video }
        if let video = videos.first {
            let urn = try await uploadVideo(video, author: author, token: tokens.accessToken)
            postContent = ["media": ["id": urn]]
        } else if images.count == 1 {
            let urn = try await uploadImage(images[0], author: author, token: tokens.accessToken)
            postContent = ["media": ["id": urn]]
        } else if images.count > 1 {
            var thumbnails: [[String: Any]] = []
            for image in images {
                let urn = try await uploadImage(image, author: author, token: tokens.accessToken)
                thumbnails.append(["id": urn])
            }
            postContent = ["multiImage": ["thumbnails": thumbnails]]
        }

        var payload: [String: Any] = [
            "author": author,
            "commentary": content.text,
            "visibility": "PUBLIC",
            "distribution": [
                "feedDistribution": "MAIN_FEED",
                "targetEntities": [],
                "thirdPartyDistributionChannels": [],
            ] as [String: Any],
            "lifecycleState": "PUBLISHED",
            "isReshareDisabledByAuthor": false,
        ]
        if let postContent {
            payload["content"] = postContent
        }
        let res = try await ProviderHTTP.fetch(
            network: .linkedin,
            url: rest.appendingPathComponent("posts"),
            method: "POST",
            headers: authHeaders(tokens.accessToken).merging(["Content-Type": "application/json"]) { _, new in new },
            body: try JSONSerialization.data(withJSONObject: payload)
        )
        // A 201 means LinkedIn accepted the post. The header is how we learn
        // its URN; a missing header must not turn success into a retryable
        // failure (the post would be duplicated on retry).
        let postUrn = res.header("x-restli-id")
        let postURL = postUrn.map { "https://www.linkedin.com/feed/update/\($0)" }
        return PublishResult(providerPostId: postUrn, providerPostUrl: postURL)
    }

    private func authHeaders(_ token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "LinkedIn-Version": Self.apiVersion,
            "X-Restli-Protocol-Version": "2.0.0",
        ]
    }

    private func uploadImage(_ item: MediaItem, author: String, token: String) async throws -> String {
        let initRes = try await ProviderHTTP.fetch(
            network: .linkedin,
            url: URL(string: "\(rest.absoluteString)/images?action=initializeUpload")!,
            method: "POST",
            headers: authHeaders(token).merging(["Content-Type": "application/json"]) { _, new in new },
            body: try JSONSerialization.data(withJSONObject: ["initializeUploadRequest": ["owner": author]])
        )
        guard let uploadURLString = JSONValue.string(initRes.body, "value", "uploadUrl"),
              let imageUrn = JSONValue.string(initRes.body, "value", "image"),
              !imageUrn.isEmpty,
              let uploadURL = URL(string: uploadURLString)
        else {
            throw ProviderError(network: .linkedin, "linkedin: image upload registration did not return an upload URL")
        }
        let fileURL = try TokenAccess.mediaURL(id: item.id, database: database)
        let data = try Data(contentsOf: fileURL)
        // The upload URL is pre-signed; no Authorization header is sent.
        _ = try await ProviderHTTP.fetch(
            network: .linkedin,
            url: uploadURL,
            method: "PUT",
            headers: ["Content-Type": "application/octet-stream"],
            body: data
        )
        return imageUrn
    }

    private func uploadVideo(_ item: MediaItem, author: String, token: String) async throws -> String {
        let fileURL = try TokenAccess.mediaURL(id: item.id, database: database)
        let total = (try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? item.size
        let initRes = try await ProviderHTTP.fetch(
            network: .linkedin,
            url: URL(string: "\(rest.absoluteString)/videos?action=initializeUpload")!,
            method: "POST",
            headers: authHeaders(token).merging(["Content-Type": "application/json"]) { _, new in new },
            body: try JSONSerialization.data(withJSONObject: [
                "initializeUploadRequest": [
                    "owner": author,
                    "fileSizeBytes": total,
                    "uploadCaptions": false,
                    "uploadThumbnail": false,
                ] as [String: Any],
            ])
        )
        guard let videoUrn = JSONValue.string(initRes.body, "value", "video"),
              !videoUrn.isEmpty,
              let instructions = (JSONValue.object(initRes.body)["value"] as? [String: Any])?["uploadInstructions"]
                  as? [[String: Any]],
              !instructions.isEmpty
        else {
            throw ProviderError(network: .linkedin, "linkedin: video upload registration did not return upload instructions")
        }

        var partIds: [String] = []
        let ordered = instructions.sorted { lhs, rhs in
            let left = (lhs["firstByte"] as? NSNumber)?.intValue ?? 0
            let right = (rhs["firstByte"] as? NSNumber)?.intValue ?? 0
            return left < right
        }
        for instruction in ordered {
            guard let firstByte = (instruction["firstByte"] as? NSNumber)?.intValue,
                  let lastByte = (instruction["lastByte"] as? NSNumber)?.intValue,
                  let uploadURLString = instruction["uploadUrl"] as? String,
                  let uploadURL = URL(string: uploadURLString)
            else {
                throw ProviderError(network: .linkedin, "linkedin: video upload instructions were incomplete")
            }
            let part = try readRange(of: fileURL, firstByte: firstByte, lastByte: lastByte)
            let partRes = try await ProviderHTTP.fetch(
                network: .linkedin,
                url: uploadURL,
                method: "PUT",
                headers: ["Content-Type": "application/octet-stream"],
                body: part
            )
            guard let etag = partRes.header("etag"), !etag.isEmpty else {
                throw ProviderError(network: .linkedin, "linkedin: video part upload did not return an ETag")
            }
            partIds.append(etag)
        }

        _ = try await ProviderHTTP.fetch(
            network: .linkedin,
            url: URL(string: "\(rest.absoluteString)/videos?action=finalizeUpload")!,
            method: "POST",
            headers: authHeaders(token).merging(["Content-Type": "application/json"]) { _, new in new },
            body: try JSONSerialization.data(withJSONObject: [
                "finalizeUploadRequest": [
                    "video": videoUrn,
                    "uploadedPartIds": partIds,
                ] as [String: Any],
            ])
        )
        try await waitForVideo(videoUrn: videoUrn, token: token)
        return videoUrn
    }

    /// Reads a closed byte range from disk without loading the whole file.
    private func readRange(of url: URL, firstByte: Int, lastByte: Int) throws -> Data {
        let length = lastByte - firstByte + 1
        guard length > 0 else { return Data() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(firstByte))
        var data = Data()
        while data.count < length {
            let chunk = try handle.read(upToCount: min(64 * 1024, length - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count == length else {
            throw ProviderError(network: .linkedin, "linkedin: video file is shorter than expected")
        }
        return data
    }

    private func waitForVideo(videoUrn: String, token: String) async throws {
        let videoId = videoUrn.replacingOccurrences(of: "urn:li:video:", with: "")
        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            do {
                let res = try await ProviderHTTP.fetch(
                    network: .linkedin,
                    url: URL(string: "\(rest.absoluteString)/videos/\(videoId)")!,
                    headers: authHeaders(token)
                )
                let status = JSONValue.string(res.body, "status")
                if status == "AVAILABLE" { return }
                if status == "PROCESSING_FAILED" {
                    let reason = JSONValue.string(res.body, "processingFailureReason")
                    let detail = reason.map { " (\($0))" } ?? ""
                    throw ProviderError(network: .linkedin, "linkedin: video processing failed\(detail)")
                }
            } catch let error as ProviderError where error.status == 403 {
                // Self-serve tokens are write-only for some versioned reads.
                // LinkedIn still processes the video and publishes it with
                // the post, so continue without polling.
                return
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw ProviderError(network: .linkedin, "linkedin: video processing timed out", retryable: true)
    }
}

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct BlueskyAdapter: ProviderAdapter {
    let accountId: String
    let database: AppDatabase
    var network: Network { .bluesky }

    private let maxImageBytes = 1_000_000

    func isConnected() -> Bool {
        let conn = try? database.connections.get(accountId)
        return conn?.state == .connected && conn?.credentialRef != nil
    }

    func refreshIfNeeded() async throws {
        _ = try await session()
    }

    func validate(content: ResolvedContent) throws {
        try ContentValidation.validate(.bluesky, content: content)
    }

    func publish(content: ResolvedContent, context: any PublishContext) async throws -> PublishResult {
        let sess = try await session()
        var record: [String: Any] = [
            "$type": "app.bsky.feed.post",
            "text": content.text,
            "facets": Self.buildFacets(content.text),
            "createdAt": Time.now(),
        ]
        let images = content.media.filter { $0.kind == .image }
        let video = content.media.first { $0.kind == .video }
        if !images.isEmpty {
            var uploaded: [[String: Any]] = []
            for image in images {
                var entry: [String: Any] = ["alt": "", "image": try await uploadBlob(session: sess, media: image)]
                if let width = image.width, let height = image.height {
                    entry["aspectRatio"] = ["width": width, "height": height]
                }
                uploaded.append(entry)
            }
            record["embed"] = ["$type": "app.bsky.embed.images", "images": uploaded]
        } else if let video {
            var embed: [String: Any] = [
                "$type": "app.bsky.embed.video",
                "video": try await uploadVideo(session: sess, media: video),
            ]
            if let width = video.width, let height = video.height {
                embed["aspectRatio"] = ["width": width, "height": height]
            }
            record["embed"] = embed
        }
        let res = try await ProviderHTTP.fetchJSON(
            network: .bluesky,
            url: URL(string: "\(sess.pds)/xrpc/com.atproto.repo.createRecord")!,
            method: "POST",
            headers: [
                "Authorization": "Bearer \(sess.accessJwt)",
                "Content-Type": "application/json",
            ],
            body: try JSONSerialization.data(withJSONObject: [
                "repo": sess.did,
                "collection": "app.bsky.feed.post",
                "record": record,
            ])
        )
        let uri = JSONValue.string(res, "uri")
        let rkey = uri?.split(separator: "/").last.map(String.init)
        return PublishResult(
            providerPostId: uri,
            providerPostUrl: rkey.map { "https://bsky.app/profile/\(sess.handle)/post/\($0)" }
        )
    }

    func normalizeError(_ error: Error) -> String {
        ProviderErrors.sanitize(network: .bluesky, error)
    }

    func health() async -> HealthResult {
        do {
            let sess = try await session()
            return HealthResult(ok: true, accountLabel: "@\(sess.handle)", meta: ["did": sess.did, "pds": sess.pds], error: nil)
        } catch {
            return HealthResult(ok: false, meta: [:], error: normalizeError(error))
        }
    }

    static func createSession(pds: String, identifier: String, appPassword: String) async throws -> BlueskySession {
        let res = try await ProviderHTTP.fetchJSON(
            network: .bluesky,
            url: URL(string: "\(pds)/xrpc/com.atproto.server.createSession")!,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: ["identifier": identifier, "password": appPassword])
        )
        guard let access = JSONValue.string(res, "accessJwt"),
              let refresh = JSONValue.string(res, "refreshJwt"),
              let did = JSONValue.string(res, "did"),
              let handle = JSONValue.string(res, "handle")
        else {
            throw ProviderError(network: .bluesky, "bluesky: session response was incomplete")
        }
        return BlueskySession(accessJwt: access, refreshJwt: refresh, did: did, handle: handle, pds: pds)
    }

    static func buildFacets(_ text: String) -> [[String: Any]] {
        var facets: [[String: Any]] = []
        func add(_ regex: NSRegularExpression, feature: (NSTextCheckingResult) -> [String: Any], usesGroup2: Bool) {
            let ns = text as NSString
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match else { return }
                let matchedRange = usesGroup2 && match.numberOfRanges > 2 ? match.range(at: 2) : match.range(at: 0)
                guard matchedRange.location != NSNotFound else { return }
                let prefixLength = usesGroup2 && match.numberOfRanges > 1 ? match.range(at: 1).length : 0
                let charStart = match.range.location + prefixLength
                let matched = ns.substring(with: matchedRange)
                facets.append([
                    "index": [
                        "byteStart": (text as NSString).substring(to: charStart).utf8.count,
                        "byteEnd": (text as NSString).substring(to: charStart + matched.count).utf8.count,
                    ],
                    "features": [feature(match)],
                ])
            }
        }
        if let links = try? NSRegularExpression(pattern: #"https?://[^\s]+"#) {
            add(links, feature: { match in
                ["$type": "app.bsky.richtext.facet#link", "uri": (text as NSString).substring(with: match.range)]
            }, usesGroup2: false)
        }
        if let mentions = try? NSRegularExpression(pattern: #"(^|\s)(@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,})"#) {
            add(mentions, feature: { match in
                let handle = (text as NSString).substring(with: match.range(at: 2))
                return ["$type": "app.bsky.richtext.facet#mention", "did": String(handle.dropFirst())]
            }, usesGroup2: true)
        }
        if let tags = try? NSRegularExpression(pattern: #"(^|\s)(#[\p{L}\p{N}_]+)"#) {
            add(tags, feature: { match in
                let tag = (text as NSString).substring(with: match.range(at: 2))
                return ["$type": "app.bsky.richtext.facet#tag", "tag": String(tag.dropFirst())]
            }, usesGroup2: true)
        }
        return facets.filter { facet in
            let feature = (facet["features"] as? [[String: Any]])?.first
            return feature?["$type"] as? String != "app.bsky.richtext.facet#mention" || feature?["did"] != nil
        }
    }

    private func session() async throws -> BlueskySession {
        guard let conn = try database.connections.get(accountId),
              let creds = Credentials.read(BasicCredentials.self, ref: conn.credentialRef)
        else {
            throw ProviderError(network: .bluesky, "bluesky: not connected")
        }
        let pds = creds.meta?["pds"] ?? "https://bsky.social"
        if let access = creds.accessJwt, !jwtExpiringSoon(access) {
            return BlueskySession(
                accessJwt: access,
                refreshJwt: creds.refreshJwt ?? "",
                did: creds.meta?["did"] ?? "",
                handle: creds.identifier,
                pds: pds
            )
        }
        if let refresh = creds.refreshJwt {
            do {
                let res = try await ProviderHTTP.fetchJSON(
                    network: .bluesky,
                    url: URL(string: "\(pds)/xrpc/com.atproto.server.refreshSession")!,
                    method: "POST",
                    headers: ["Authorization": "Bearer \(refresh)"]
                )
                guard let access = JSONValue.string(res, "accessJwt"), let newRefresh = JSONValue.string(res, "refreshJwt") else {
                    throw ProviderError(network: .bluesky, "bluesky: refreshed session was incomplete")
                }
                return try saveSession(
                    creds: creds,
                    ref: conn.credentialRef!,
                    pds: pds,
                    session: BlueskySession(
                        accessJwt: access,
                        refreshJwt: newRefresh,
                        did: JSONValue.string(res, "did") ?? creds.meta?["did"] ?? "",
                        handle: JSONValue.string(res, "handle") ?? creds.identifier,
                        pds: pds
                    )
                )
            } catch {
                // Fall through to app-password login.
            }
        }
        let fresh = try await Self.createSession(pds: pds, identifier: creds.identifier, appPassword: creds.secret)
        return try saveSession(creds: creds, ref: conn.credentialRef!, pds: pds, session: fresh)
    }

    private func saveSession(creds: BasicCredentials, ref: String, pds: String, session: BlueskySession) throws -> BlueskySession {
        var next = creds
        next.accessJwt = session.accessJwt
        next.refreshJwt = session.refreshJwt
        var meta = next.meta ?? [:]
        meta["pds"] = pds
        meta["did"] = session.did
        next.meta = meta
        try Credentials.store(ref, value: next)
        return session
    }

    private func jwtExpiringSoon(_ jwt: String, skewSeconds: TimeInterval = 60) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return false }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double
        else { return false }
        return exp - Date().timeIntervalSince1970 < skewSeconds
    }

    private func uploadBlob(session: BlueskySession, media: MediaItem) async throws -> [String: Any] {
        let prepared = try blueskyImageData(media)
        do {
            let res = try await ProviderHTTP.fetchJSON(
                network: .bluesky,
                url: URL(string: "\(session.pds)/xrpc/com.atproto.repo.uploadBlob")!,
                method: "POST",
                headers: [
                    "Authorization": "Bearer \(session.accessJwt)",
                    "Content-Type": prepared.mimeType,
                    "Content-Length": String(prepared.data.count),
                ],
                body: prepared.data
            )
            guard let blob = JSONValue.object(res)["blob"] as? [String: Any] else {
                throw ProviderError(network: .bluesky, "bluesky: blob upload returned no blob")
            }
            return blob
        } catch let error as ProviderError where error.status == 400 {
            throw ProviderError(network: .bluesky, "\(error.message). Bluesky post images must be 1 MB or smaller.", status: 400)
        }
    }

    private func blueskyImageData(_ media: MediaItem) throws -> (data: Data, mimeType: String) {
        let url = try TokenAccess.mediaURL(id: media.id, database: database)
        if media.size <= maxImageBytes {
            return (try Data(contentsOf: url), media.mimeType)
        }
        if media.mimeType == "image/gif" {
            throw ProviderError(
                network: .bluesky,
                "bluesky: \(media.name) is an animated GIF over the 1MB limit and cannot be converted without losing animation"
            )
        }
        let profiles: [(quality: CGFloat, maxDimension: Int)] = [
            (0.80, 0), (0.65, 0), (0.70, 2000), (0.65, 1600), (0.60, 1200),
        ]
        for profile in profiles {
            if let data = jpegData(from: url, quality: profile.quality, maxDimension: profile.maxDimension),
               data.count <= maxImageBytes
            {
                return (data, "image/jpeg")
            }
        }
        throw ProviderError(network: .bluesky, "bluesky: \(media.name) could not be reduced below the 1MB image limit")
    }

    private func jpegData(from url: URL, quality: CGFloat, maxDimension: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard var image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else { return nil }
        if maxDimension > 0 {
            let width = image.width
            let height = image.height
            let longest = max(width, height)
            if longest > maxDimension {
                let scale = CGFloat(maxDimension) / CGFloat(longest)
                let size = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(size.width),
                    pixelsHigh: Int(size.height),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )
                if let rep {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    NSImage(cgImage: image, size: size).draw(in: NSRect(origin: .zero, size: size))
                    NSGraphicsContext.restoreGraphicsState()
                    if let cg = rep.cgImage { image = cg }
                }
            }
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func uploadVideo(session: BlueskySession, media: MediaItem) async throws -> [String: Any] {
        let url = try TokenAccess.mediaURL(id: media.id, database: database)
        let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? media.size
        let limits = try await ProviderHTTP.fetchJSON(
            network: .bluesky,
            url: URL(string: "\(session.pds)/xrpc/app.bsky.video.getUploadLimits")!,
            headers: ["Authorization": "Bearer \(session.accessJwt)"]
        )
        let canUpload = JSONValue.object(limits)["canUpload"] as? Bool
        let remaining = JSONValue.object(limits)["remainingDailyBytes"] as? Int ?? 1
        if canUpload == false || remaining < size {
            throw ProviderError(network: .bluesky, "bluesky: daily video upload limit reached")
        }
        let pdsHost = URL(string: session.pds)?.host ?? "bsky.social"
        var authURL = URLComponents(string: "\(session.pds)/xrpc/com.atproto.server.getServiceAuth")!
        authURL.queryItems = [
            URLQueryItem(name: "aud", value: "did:web:\(pdsHost)"),
            URLQueryItem(name: "lxm", value: "com.atproto.repo.uploadBlob"),
            URLQueryItem(name: "exp", value: String(Int(Date().timeIntervalSince1970) + 1800)),
        ]
        let authRes = try await ProviderHTTP.fetchJSON(
            network: .bluesky,
            url: authURL.url!,
            headers: ["Authorization": "Bearer \(session.accessJwt)"]
        )
        let serviceToken = JSONValue.string(authRes, "token") ?? ""
        let fileData = try Data(contentsOf: url)
        let uploadURL = URL(string: "https://video.bsky.app/xrpc/app.bsky.video.uploadVideo?did=\(session.did.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? session.did)&name=\(url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "video.mp4")")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(serviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue(media.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        request.httpBody = fileData
        let (data, response) = try await ProviderHTTP.client.data(for: request)
        let body = try? JSONSerialization.jsonObject(with: data)
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError(network: .bluesky, "bluesky: video upload failed (HTTP \(response.statusCode))")
        }
        if let blob = JSONValue.object(body)["blob"] as? [String: Any] {
            return blob
        }
        guard let jobId = JSONValue.string(body, "jobId") else {
            throw ProviderError(network: .bluesky, "bluesky: video upload failed (HTTP \(response.statusCode))")
        }
        let deadline = Date().addingTimeInterval(10 * 60)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(5))
            let status = try await ProviderHTTP.fetchJSON(
                network: .bluesky,
                url: URL(string: "https://video.bsky.app/xrpc/app.bsky.video.getJobStatus?jobId=\(jobId)")!,
                headers: ["Authorization": "Bearer \(serviceToken)"]
            )
            let job = JSONValue.object(JSONValue.object(status)["jobStatus"])
            if job["state"] as? String == "JOB_STATE_COMPLETED", let blob = job["blob"] as? [String: Any] {
                return blob
            }
            if job["state"] as? String == "JOB_STATE_FAILED" {
                throw ProviderError(network: .bluesky, "bluesky: video processing failed (\(job["error"] as? String ?? "unknown"))")
            }
        }
        throw ProviderError(network: .bluesky, "bluesky: video processing timed out")
    }
}

struct BlueskySession: Sendable {
    var accessJwt: String
    var refreshJwt: String
    var did: String
    var handle: String
    var pds: String
}

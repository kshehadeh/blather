import Foundation

enum GraphPermalink {
    static var maxAttempts = 4
    static var retryDelay: Duration = .milliseconds(400)

    static func parse(_ value: Any?) -> String? {
        guard let raw = JSONValue.string(value, "permalink") else { return nil }
        let permalink = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !permalink.isEmpty else { return nil }
        let lower = permalink.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://") else { return nil }
        guard URL(string: permalink) != nil else { return nil }
        return permalink
    }

    /// Fetches Graph `permalink`. Missing/empty ids and request errors return nil.
    /// Retries because permalinks can lag immediately after publish.
    static func fetch(
        network: Network,
        graphBase: String,
        mediaId: String,
        accessToken: String,
        attempts: Int? = nil
    ) async -> String? {
        let mediaId = mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mediaId.isEmpty else { return nil }
        let encodedId = mediaId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? mediaId
        let encodedToken = accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? accessToken
        guard let url = URL(string: "\(graphBase)/\(encodedId)?fields=permalink&access_token=\(encodedToken)") else {
            return nil
        }
        let tries = max(1, attempts ?? maxAttempts)
        for index in 0..<tries {
            do {
                let body = try await ProviderHTTP.fetchJSON(network: network, url: url)
                if let permalink = parse(body) {
                    return permalink
                }
            } catch {
                // Publish already succeeded; the public URL is optional.
            }
            if index + 1 < tries {
                try? await Task.sleep(for: retryDelay)
            }
        }
        return nil
    }

    static func publishResult(
        network: Network,
        graphBase: String,
        mediaId: String?,
        accessToken: String
    ) async -> PublishResult {
        let postId = mediaId.flatMap { id in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let postId else {
            return PublishResult(providerPostId: nil, providerPostUrl: nil)
        }
        let permalink = await fetch(
            network: network,
            graphBase: graphBase,
            mediaId: postId,
            accessToken: accessToken
        )
        return PublishResult(providerPostId: postId, providerPostUrl: permalink)
    }
}

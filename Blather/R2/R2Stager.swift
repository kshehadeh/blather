import Foundation

struct R2Credentials: Codable, Hashable, Sendable {
    var accessKeyId: String
    var secretAccessKey: String
}

struct StagedObject: Hashable, Sendable {
    var key: String
    var url: String
}

protocol R2Stager: Sendable {
    func stage(mediaId: String, attemptId: String?) async throws -> StagedObject
    func remove(key: String) async throws
    func testConnection() async throws
    var bucket: String { get }
}

enum R2 {
    static let presignTTL: TimeInterval = 60 * 60
    static let cleanupWindow: TimeInterval = 24 * 60 * 60
    static var overrideStager: (any R2Stager)?

    static func stager(database: AppDatabase) throws -> any R2Stager {
        if let overrideStager { return overrideStager }
        guard let settings = try database.r2.get(), !settings.accountId.isEmpty else {
            throw R2Error.notConfigured
        }
        if settings.publicUrlStrategy == "public", (settings.publicBaseUrl ?? "").isEmpty {
            throw R2Error.notConfigured
        }
        if ProcessInfo.processInfo.environment["BLATHER_R2"] == "fake" {
            return FakeR2Stager(database: database, settings: settings)
        }
        guard let creds = Credentials.read(R2Credentials.self, ref: settings.credentialRef) else {
            throw R2Error.missingCredentials
        }
        return CloudflareR2Stager(database: database, settings: settings, credentials: creds)
    }

    static func cleanupOrphans(database: AppDatabase, now: Date = Date()) async -> Int {
        let cutoff = Time.isoFormatter.string(from: now.addingTimeInterval(-cleanupWindow))
        guard let orphans = try? database.staged.olderThan(cutoff), !orphans.isEmpty else { return 0 }
        guard let stager = try? stager(database: database) else { return 0 }
        var removed = 0
        for object in orphans {
            do {
                try await stager.remove(key: object.key)
                try database.staged.remove(object.id)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }
}

enum R2Error: Error, LocalizedError {
    case notConfigured
    case missingCredentials
    case mediaNotFound
    case publicURLMissing
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "R2 staging is not configured (see Settings)"
        case .missingCredentials: "R2 credentials missing (see Settings)"
        case .mediaNotFound: "Media not found"
        case .publicURLMissing: "A public R2 bucket URL is required for public media URLs"
        case .requestFailed(let message): message
        }
    }
}

enum R2Endpoint {
    static let jurisdictions: Set<String> = ["eu", "us", "fedramp"]

    struct Parsed: Equatable, Sendable {
        var accountId: String
        var jurisdiction: String?
    }

    static func parse(accountId raw: String, jurisdiction selected: String? = nil) -> Parsed {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix("/") { value.removeLast() }
        if let host = URL(string: value)?.host, value.contains("://") {
            value = host
        }
        let parts = value.split(separator: ".").map(String.init)
        if parts.count >= 4,
           parts[parts.count - 3].lowercased() == "r2",
           parts[parts.count - 2].lowercased() == "cloudflarestorage",
           parts[parts.count - 1].lowercased() == "com"
        {
            let accountId = parts[0]
            if parts.count >= 5, jurisdictions.contains(parts[1].lowercased()) {
                return Parsed(accountId: accountId, jurisdiction: parts[1].lowercased())
            }
            return Parsed(accountId: accountId, jurisdiction: Self.normalizeJurisdiction(selected))
        }
        return Parsed(accountId: value, jurisdiction: Self.normalizeJurisdiction(selected))
    }

    static func host(accountId: String, jurisdiction: String?) -> String {
        if let jurisdiction, !jurisdiction.isEmpty {
            return "\(accountId).\(jurisdiction).r2.cloudflarestorage.com"
        }
        return "\(accountId).r2.cloudflarestorage.com"
    }

    static func normalizeJurisdiction(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard jurisdictions.contains(trimmed) else { return nil }
        return trimmed
    }

    static func normalizeBucket(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum R2APIError {
    static func message(status: Int, body: Data, operation: String) -> String {
        let text = String(data: body, encoding: .utf8) ?? ""
        let code = xmlTag(text, "Code")
        let detail = xmlTag(text, "Message")
        if let mapped = friendlyMessage(code: code, detail: detail) {
            return mapped
        }
        if let code, let detail, !detail.isEmpty {
            return "R2 \(operation) failed (\(code)): \(detail)"
        }
        if let detail, !detail.isEmpty {
            return "R2 \(operation) failed: \(detail)"
        }
        return "R2 \(operation) failed (HTTP \(status))"
    }

    static func xmlTag(_ xml: String, _ tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<\(tag)>([^<]*)</\(tag)>", options: .caseInsensitive),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml)
        else { return nil }
        let value = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func friendlyMessage(code: String?, detail: String?) -> String? {
        switch code {
        case "AuthorizationHeaderMalformed":
            "R2 rejected the signed request. Check the Account ID, and that the Access Key ID and Secret are R2 S3 credentials — not a Cloudflare API token. If the bucket was created with a jurisdiction (EU, US, FedRAMP), select that jurisdiction."
        case "InvalidAccessKeyId":
            "R2 did not recognize the Access Key ID. Create an R2 API token and paste its Access Key ID and Secret Access Key."
        case "SignatureDoesNotMatch":
            "R2 credentials do not match. Recreate the R2 API token and paste both the Access Key ID and Secret Access Key."
        case "AccessDenied":
            "R2 access was denied. Use Object Read & Write on the R2 API token, restricted to this bucket."
        case "NoSuchBucket", "PermanentRedirect", "IllegalLocationConstraintException":
            "R2 could not find this bucket on the account. Check the bucket name, Account ID, and jurisdiction (EU/US/FedRAMP buckets need that jurisdiction selected)."
        case "InvalidBucketName":
            "R2 bucket name is invalid. Use the exact bucket name (3–63 lowercase letters, numbers, and hyphens), not a URL."
        case "InvalidArgument":
            if let detail, !detail.isEmpty {
                "R2 rejected the request: \(detail)"
            } else {
                "R2 rejected the request (invalid argument). Check the Account ID, bucket name, and credentials."
            }
        default:
            nil
        }
    }
}

struct CloudflareR2Stager: R2Stager {
    let database: AppDatabase
    let settings: StoredR2Settings
    let credentials: R2Credentials

    var bucket: String { settings.bucket }

    private func objectURL(key: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = R2Endpoint.host(accountId: settings.accountId, jurisdiction: settings.jurisdiction)
        let path = key.map { "/\(settings.bucket)/\($0)" } ?? "/\(settings.bucket)"
        components.percentEncodedPath = path.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? path
        return components.url!
    }

    func stage(mediaId: String, attemptId: String?) async throws -> StagedObject {
        guard let item = try database.media.get(mediaId),
              let relative = try database.media.pathOf(mediaId)
        else { throw R2Error.mediaNotFound }
        let safeName = item.name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        let key = "blather-staging/\(attemptId ?? "unlinked")/\(mediaId)-\(safeName)"
        let fileURL = MediaStore.fileURL(for: relative)
        let body = try Data(contentsOf: fileURL)
        try await send("PUT", url: objectURL(key: key), extraHeaders: ["content-type": item.mimeType], body: body, operation: "upload")
        _ = try database.staged.add(attemptId: attemptId, bucket: settings.bucket, key: key)
        return StagedObject(key: key, url: try publicURL(for: key))
    }

    func remove(key: String) async throws {
        _ = try await send("DELETE", url: objectURL(key: key), body: Data(), operation: "delete", requireSuccess: false)
    }

    func testConnection() async throws {
        let key = "blather-staging/.connection-test"
        try await send(
            "PUT",
            url: objectURL(key: key),
            extraHeaders: ["content-type": "application/octet-stream"],
            body: Data("blather-r2-ok".utf8),
            operation: "connection"
        )
        try await remove(key: key)
    }

    @discardableResult
    private func send(
        _ method: String,
        url: URL,
        extraHeaders: [String: String] = [:],
        body: Data?,
        operation: String,
        requireSuccess: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let headers = SigV4.signedHeaders(
            method: method,
            url: url,
            region: "auto",
            service: "s3",
            accessKeyId: credentials.accessKeyId,
            secretAccessKey: credentials.secretAccessKey,
            extraHeaders: extraHeaders,
            body: body ?? Data()
        )
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = (body?.isEmpty == false) ? body : nil
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await ProviderHTTP.client.data(for: request)
        if requireSuccess, !(200..<300).contains(response.statusCode) {
            throw R2Error.requestFailed(R2APIError.message(status: response.statusCode, body: data, operation: operation))
        }
        return (data, response)
    }

    private func publicURL(for key: String) throws -> String {
        if settings.publicUrlStrategy == "presigned" {
            return SigV4.presignedGET(
                url: objectURL(key: key),
                region: "auto",
                service: "s3",
                accessKeyId: credentials.accessKeyId,
                secretAccessKey: credentials.secretAccessKey,
                expires: Int(R2.presignTTL)
            ).absoluteString
        }
        guard var base = settings.publicBaseUrl, !base.isEmpty else { throw R2Error.publicURLMissing }
        if base.hasSuffix("/") { base.removeLast() }
        return "\(base)/\(key)"
    }
}

struct FakeR2Stager: R2Stager {
    let database: AppDatabase
    let settings: StoredR2Settings?

    var bucket: String { settings?.bucket ?? "fake-bucket" }

    func stage(mediaId: String, attemptId: String?) async throws -> StagedObject {
        guard let item = try database.media.get(mediaId) else { throw R2Error.mediaNotFound }
        let key = "blather-staging/\(attemptId ?? "unlinked")/\(mediaId)-\(item.name)"
        _ = try database.staged.add(attemptId: attemptId, bucket: bucket, key: key)
        let base: String
        if settings?.publicUrlStrategy == "public", let publicBase = settings?.publicBaseUrl, !publicBase.isEmpty {
            base = publicBase.hasSuffix("/") ? String(publicBase.dropLast()) : publicBase
        } else {
            base = "https://fake-r2.local/\(bucket)"
        }
        return StagedObject(key: key, url: "\(base)/\(key)")
    }

    func remove(key: String) async throws {}

    func testConnection() async throws {
        guard settings != nil else { throw R2Error.notConfigured }
    }
}

struct R2PublishContext: PublishContext {
    let attemptId: String
    let database: AppDatabase

    func stageMedia(mediaId: String, attemptId: String?) async throws -> (key: String, url: String) {
        let staged = try await R2.stager(database: database).stage(mediaId: mediaId, attemptId: attemptId ?? self.attemptId)
        return (staged.key, staged.url)
    }

    func removeStaged(key: String) async {
        try? await R2.stager(database: database).remove(key: key)
        if let rows = try? database.staged.forAttempt(attemptId) {
            for row in rows where row.key == key {
                try? database.staged.remove(row.id)
            }
        }
    }
}

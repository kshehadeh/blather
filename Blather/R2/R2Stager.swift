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

struct CloudflareR2Stager: R2Stager {
    let database: AppDatabase
    let settings: StoredR2Settings
    let credentials: R2Credentials

    var bucket: String { settings.bucket }

    private func objectURL(key: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "\(settings.accountId).r2.cloudflarestorage.com"
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
        let objectURL = objectURL(key: key)
        let headers = SigV4.signedHeaders(
            method: "PUT",
            url: objectURL,
            region: "auto",
            service: "s3",
            accessKeyId: credentials.accessKeyId,
            secretAccessKey: credentials.secretAccessKey,
            extraHeaders: ["content-type": item.mimeType],
            body: body
        )
        var request = URLRequest(url: objectURL)
        request.httpMethod = "PUT"
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (_, response) = try await ProviderHTTP.client.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw R2Error.requestFailed("R2 upload failed (HTTP \(response.statusCode))")
        }
        _ = try database.staged.add(attemptId: attemptId, bucket: settings.bucket, key: key)
        return StagedObject(key: key, url: try publicURL(for: key))
    }

    func remove(key: String) async throws {
        let objectURL = objectURL(key: key)
        let headers = SigV4.signedHeaders(
            method: "DELETE",
            url: objectURL,
            region: "auto",
            service: "s3",
            accessKeyId: credentials.accessKeyId,
            secretAccessKey: credentials.secretAccessKey,
            body: Data()
        )
        var request = URLRequest(url: objectURL)
        request.httpMethod = "DELETE"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        _ = try await ProviderHTTP.client.data(for: request)
    }

    func testConnection() async throws {
        let url = objectURL()
        let headers = SigV4.signedHeaders(
            method: "HEAD",
            url: url,
            region: "auto",
            service: "s3",
            accessKeyId: credentials.accessKeyId,
            secretAccessKey: credentials.secretAccessKey,
            body: Data()
        )
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (_, response) = try await ProviderHTTP.client.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw R2Error.requestFailed("R2 connection failed (HTTP \(response.statusCode))")
        }
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

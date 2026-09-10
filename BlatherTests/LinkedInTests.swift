import Foundation
import Testing
@testable import Blather

@Suite(.serialized)
struct LinkedInTests {
    private func withHTTP<T>(_ client: MockHTTPClient, _ body: () async throws -> T) async rethrows -> T {
        let previous = ProviderHTTP.client
        let previousMocks = AdapterRegistry.useMocks
        ProviderHTTP.client = client
        AdapterRegistry.useMocks = false
        defer {
            ProviderHTTP.client = previous
            AdapterRegistry.useMocks = previousMocks
        }
        return try await body()
    }

    @discardableResult
    private func makeLinkedInAccount(
        _ db: AppDatabase,
        expiresAt: Double? = nil,
        userId: String = "sub-123"
    ) throws -> ConnectionInfo {
        Keychain.store = MemoryKeychainStore()
        return try ConnectionStore.storeOAuth(
            network: .linkedin,
            tokens: OAuthTokens(
                accessToken: "tok",
                refreshToken: nil,
                expiresAt: expiresAt,
                meta: ["clientId": "client-id", "clientSecret": "shh", "userId": userId]
            ),
            providerAccountId: userId,
            accountLabel: "Test Member",
            meta: ["userId": userId],
            database: db
        )
    }

    /// Redirects Blather's media directory to a throwaway folder for tests
    /// that must read real bytes back from disk.
    @discardableResult
    private func makeMediaDirectory() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("blather-linkedin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temp.appendingPathComponent("media", isDirectory: true),
            withIntermediateDirectories: true
        )
        AppPaths.overrideDataDirectory = temp
        return temp
    }

    @discardableResult
    private func createMediaFile(
        _ db: AppDatabase,
        kind: MediaKind,
        mimeType: String,
        data: Data,
        duration: Double? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) throws -> MediaItem {
        let ext = mimeType == "video/mp4" ? "mp4" : "png"
        let filename = "\(UUID().uuidString).\(ext)"
        try data.write(to: AppPaths.mediaDirectory.appendingPathComponent(filename))
        return try db.media.create(
            kind: kind,
            mimeType: mimeType,
            name: filename,
            size: data.count,
            width: width,
            height: height,
            durationSeconds: duration,
            path: filename
        )
    }

    private func mediaItem(
        kind: MediaKind,
        mimeType: String,
        size: Int = 100_000,
        duration: Double? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) -> MediaItem {
        MediaItem(
            id: "m",
            kind: kind,
            mimeType: mimeType,
            name: "clip.\(kind == .image ? "png" : "mp4")",
            size: size,
            width: width,
            height: height,
            durationSeconds: duration,
            createdAt: ""
        )
    }

    private func jsonBody(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Capabilities and validation

    @Test func linkedinCapabilities() {
        let caps = Capabilities.capabilities(for: .linkedin)
        #expect(caps.network == .linkedin)
        #expect(caps.maxChars == 3000)
        #expect(caps.maxImages == 20)
        #expect(caps.allowsVideo)
        #expect(!caps.allowsMixedMedia)
        #expect(!caps.requiresMedia)
    }

    @Test func linkedinValidationEnforcesTextAndMediaRules() throws {
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(text: String(repeating: "x", count: 3001), media: [])
            )
        }
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(text: "watch", media: [mediaItem(kind: .video, mimeType: "video/quicktime")])
            )
        }
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(
                    text: "watch",
                    media: [mediaItem(kind: .video, mimeType: "video/mp4", size: LinkedInLimits.videoMaxBytes + 1)]
                )
            )
        }
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(
                    text: "watch",
                    media: [mediaItem(kind: .video, mimeType: "video/mp4", size: LinkedInLimits.videoMinBytes - 1)]
                )
            )
        }
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(
                    text: "watch",
                    media: [mediaItem(kind: .video, mimeType: "video/mp4", duration: 2)]
                )
            )
        }
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(
                    text: "look",
                    media: [mediaItem(kind: .image, mimeType: "image/png", width: 7000, height: 6000)]
                )
            )
        }
        #expect(
            (try? ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(
                    text: "look",
                    media: [mediaItem(kind: .video, mimeType: "video/mp4", duration: 5)]
                )
            )) != nil
        )
        let images = (1...20).map { _ in mediaItem(kind: .image, mimeType: "image/png") }
        #expect(
            (try? ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(text: "look", media: images)
            )) != nil
        )
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(
                .linkedin,
                content: ResolvedContent(text: "look", media: images + [mediaItem(kind: .image, mimeType: "image/png")])
            )
        }
    }

    // MARK: Account settings

    @Test func linkedinAccountSettingsExposeClientIdAndReuseStoredSecret() throws {
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)

        let stored = AccountSettings.load(accountId: account.id, database: db)
        #expect(stored.clientId == "client-id")
        #expect(stored.hasStoredSecret)

        let plan = AccountSettings.plan(
            network: .linkedin,
            clientId: "new-id",
            clientSecret: "",
            pds: "",
            handle: "",
            appPassword: "",
            stored: AccountConnectSettings(clientId: "old-id", hasStoredSecret: true),
            storedAppPassword: nil,
            storedClientSecret: "stored-secret"
        )
        #expect(plan == .reconnectLinkedIn(clientId: "new-id", clientSecret: "stored-secret"))

        let unchanged = AccountSettings.plan(
            network: .linkedin,
            clientId: "old-id",
            clientSecret: "",
            pds: "",
            handle: "",
            appPassword: "",
            stored: AccountConnectSettings(clientId: "old-id", hasStoredSecret: true),
            storedAppPassword: nil,
            storedClientSecret: nil
        )
        #expect(unchanged == .noOp)
    }

    // MARK: Publishing

    @Test func textPostCapturesRestliIdAndBuildsPermalink() async throws {
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let client = MockHTTPClient([
            .json([:], status: 201, headers: ["x-restli-id": "urn:li:share:6844785523593134080"]),
        ])

        try await withHTTP(client) {
            let result = try await adapter.publish(
                content: ResolvedContent(text: "hello linkedin", media: []),
                context: NullPublishContext(attemptId: "att")
            )
            #expect(result.providerPostId == "urn:li:share:6844785523593134080")
            #expect(
                result.providerPostUrl == "https://www.linkedin.com/feed/update/urn:li:share:6844785523593134080"
            )
        }

        let request = try #require(client.requests.first)
        #expect(client.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.linkedin.com/rest/posts")
        #expect(request.value(forHTTPHeaderField: "LinkedIn-Version") == LinkedInAdapter.apiVersion)
        #expect(request.value(forHTTPHeaderField: "X-Restli-Protocol-Version") == "2.0.0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let body = try jsonBody(of: request)
        #expect(body["author"] as? String == "urn:li:person:sub-123")
        #expect(body["commentary"] as? String == "hello linkedin")
        #expect(body["visibility"] as? String == "PUBLIC")
        #expect(body["lifecycleState"] as? String == "PUBLISHED")
        #expect(body["content"] == nil)
    }

    @Test func postAcceptedWithoutRestliIdStillSucceeds() async throws {
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let client = MockHTTPClient([
            .json([:], status: 201),
        ])

        try await withHTTP(client) {
            let result = try await adapter.publish(
                content: ResolvedContent(text: "hello", media: []),
                context: NullPublishContext(attemptId: "att")
            )
            #expect(result.providerPostId == nil)
            #expect(result.providerPostUrl == nil)
        }
    }

    @Test func singleImagePostRegistersUploadsAndAttachesImage() async throws {
        let directory = try makeMediaDirectory()
        defer {
            AppPaths.overrideDataDirectory = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let imageData = Data(repeating: 0xAB, count: 2048)
        let item = try createMediaFile(db, kind: .image, mimeType: "image/png", data: imageData)

        let client = MockHTTPClient([
            .json(
                [
                    "value": [
                        "uploadUrl": "https://www.linkedin.com/dms-uploads/abc?ca=vector_feedshare&ut=secret",
                        "image": "urn:li:image:C55_1",
                    ]
                ],
                status: 201
            ),
            .empty(200),
            .json([:], status: 201, headers: ["x-restli-id": "urn:li:share:10"]),
        ])

        try await withHTTP(client) {
            let result = try await adapter.publish(
                content: ResolvedContent(text: "pic", media: [item]),
                context: NullPublishContext(attemptId: "att")
            )
            #expect(result.providerPostId == "urn:li:share:10")
        }

        #expect(client.requests.count == 3)

        let register = client.requests[0]
        #expect(register.url?.absoluteString.contains("api.linkedin.com/rest/images?action=initializeUpload") == true)
        let registerBody = try jsonBody(of: register)
        #expect((registerBody["initializeUploadRequest"] as? [String: Any])?["owner"] as? String == "urn:li:person:sub-123")

        let upload = client.requests[1]
        #expect(upload.httpMethod == "PUT")
        #expect(upload.url?.host == "www.linkedin.com")
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(upload.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(upload.httpBody == imageData)

        let post = client.requests[2]
        let postBody = try jsonBody(of: post)
        let content = try #require(postBody["content"] as? [String: Any])
        let media = try #require(content["media"] as? [String: Any])
        #expect(media["id"] as? String == "urn:li:image:C55_1")
    }

    @Test func multiImagePostUsesMultiImageContent() async throws {
        let directory = try makeMediaDirectory()
        defer {
            AppPaths.overrideDataDirectory = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let first = try createMediaFile(db, kind: .image, mimeType: "image/png", data: Data(repeating: 1, count: 16))
        let second = try createMediaFile(db, kind: .image, mimeType: "image/png", data: Data(repeating: 2, count: 16))

        func register(_ index: Int) -> MockHTTPClient.Exchange {
            .json(
                [
                    "value": [
                        "uploadUrl": "https://www.linkedin.com/dms-uploads/multi-\(index)?ut=secret\(index)",
                        "image": "urn:li:image:C55_multi_\(index)",
                    ]
                ],
                status: 201
            )
        }

        let client = MockHTTPClient([
            register(1),
            .empty(200),
            register(2),
            .empty(200),
            .json([:], status: 201, headers: ["x-restli-id": "urn:li:share:20"]),
        ])

        try await withHTTP(client) {
            let result = try await adapter.publish(
                content: ResolvedContent(text: "album", media: [first, second]),
                context: NullPublishContext(attemptId: "att")
            )
            #expect(result.providerPostId == "urn:li:share:20")
        }

        #expect(client.requests.count == 5)
        let post = client.requests[4]
        let postBody = try jsonBody(of: post)
        let content = try #require(postBody["content"] as? [String: Any])
        let multiImage = try #require(content["multiImage"] as? [String: Any])
        let thumbnails = try #require(multiImage["thumbnails"] as? [[String: Any]])
        #expect(thumbnails.map { $0["id"] as? String } == ["urn:li:image:C55_multi_1", "urn:li:image:C55_multi_2"])
    }

    @Test func videoPostUploadsPartsInOrderFinalizesAndWaitsForProcessing() async throws {
        let directory = try makeMediaDirectory()
        defer {
            AppPaths.overrideDataDirectory = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let videoData = Data((0..<5_000_000).map { UInt8($0 % 251) })
        let item = try createMediaFile(
            db,
            kind: .video,
            mimeType: "video/mp4",
            data: videoData,
            duration: 5
        )

        let client = MockHTTPClient([
            .json(
                [
                    "value": [
                        "video": "urn:li:video:C55_v",
                        "uploadInstructions": [
                            [
                                "firstByte": 4_194_304,
                                "lastByte": 4_999_999,
                                "uploadUrl": "https://www.linkedin.com/dms-uploads/v1?ut=part1",
                            ],
                            [
                                "firstByte": 0,
                                "lastByte": 4_194_303,
                                "uploadUrl": "https://www.linkedin.com/dms-uploads/v0?ut=part0",
                            ],
                        ],
                    ]
                ],
                status: 201
            ),
            .empty(200, headers: ["etag": "etag-0"]),
            .empty(200, headers: ["etag": "etag-1"]),
            .empty(200),
            .json(["status": "AVAILABLE"]),
            .json([:], status: 201, headers: ["x-restli-id": "urn:li:share:30"]),
        ])

        try await withHTTP(client) {
            let result = try await adapter.publish(
                content: ResolvedContent(text: "moving pictures", media: [item]),
                context: NullPublishContext(attemptId: "att")
            )
            #expect(result.providerPostId == "urn:li:share:30")
        }

        #expect(client.requests.count == 6)

        let register = client.requests[0]
        #expect(register.url?.absoluteString.contains("api.linkedin.com/rest/videos?action=initializeUpload") == true)
        let registerBody = try jsonBody(of: register)
        let registerRequest = try #require(registerBody["initializeUploadRequest"] as? [String: Any])
        #expect(registerRequest["owner"] as? String == "urn:li:person:sub-123")
        #expect((registerRequest["fileSizeBytes"] as? NSNumber)?.intValue == 5_000_000)

        let firstUpload = client.requests[1]
        #expect(firstUpload.url?.absoluteString.contains("dms-uploads/v0") == true)
        #expect(firstUpload.httpBody == videoData.subdata(in: 0..<4_194_304))
        let secondUpload = client.requests[2]
        #expect(secondUpload.url?.absoluteString.contains("dms-uploads/v1") == true)
        #expect(secondUpload.httpBody == videoData.subdata(in: 4_194_304..<5_000_000))

        let finalize = client.requests[3]
        #expect(finalize.url?.absoluteString.contains("api.linkedin.com/rest/videos?action=finalizeUpload") == true)
        let finalizeBody = try jsonBody(of: finalize)
        let finalizeRequest = try #require(finalizeBody["finalizeUploadRequest"] as? [String: Any])
        #expect(finalizeRequest["video"] as? String == "urn:li:video:C55_v")
        #expect(finalizeRequest["uploadedPartIds"] as? [String] == ["etag-0", "etag-1"])

        let poll = client.requests[4]
        #expect(poll.httpMethod == "GET")
        #expect(poll.url?.absoluteString == "https://api.linkedin.com/rest/videos/C55_v")

        let post = client.requests[5]
        let postBody = try jsonBody(of: post)
        let content = try #require(postBody["content"] as? [String: Any])
        let media = try #require(content["media"] as? [String: Any])
        #expect(media["id"] as? String == "urn:li:video:C55_v")
    }

    @Test func videoPollForbiddenStillCreatesPost() async throws {
        let directory = try makeMediaDirectory()
        defer {
            AppPaths.overrideDataDirectory = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let item = try createMediaFile(
            db,
            kind: .video,
            mimeType: "video/mp4",
            data: Data(repeating: 7, count: 200_000),
            duration: 5
        )

        let client = MockHTTPClient([
            .json(
                [
                    "value": [
                        "video": "urn:li:video:C55_p",
                        "uploadInstructions": [
                            [
                                "firstByte": 0,
                                "lastByte": 199_999,
                                "uploadUrl": "https://www.linkedin.com/dms-uploads/v?ut=part",
                            ],
                        ],
                    ]
                ],
                status: 201
            ),
            .empty(200, headers: ["etag": "etag-0"]),
            .empty(200),
            .json(["message": "Accessing this resource is forbidden"], status: 403),
            .json([:], status: 201, headers: ["x-restli-id": "urn:li:share:40"]),
        ])

        try await withHTTP(client) {
            let result = try await adapter.publish(
                content: ResolvedContent(text: "video", media: [item]),
                context: NullPublishContext(attemptId: "att")
            )
            #expect(result.providerPostId == "urn:li:share:40")
        }
        #expect(client.requests.count == 5)
    }

    @Test func videoProcessingFailureFailsPublish() async throws {
        let directory = try makeMediaDirectory()
        defer {
            AppPaths.overrideDataDirectory = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let item = try createMediaFile(
            db,
            kind: .video,
            mimeType: "video/mp4",
            data: Data(repeating: 9, count: 200_000),
            duration: 5
        )

        let client = MockHTTPClient([
            .json(
                [
                    "value": [
                        "video": "urn:li:video:C55_f",
                        "uploadInstructions": [
                            [
                                "firstByte": 0,
                                "lastByte": 199_999,
                                "uploadUrl": "https://www.linkedin.com/dms-uploads/v?ut=part",
                            ],
                        ],
                    ]
                ],
                status: 201
            ),
            .empty(200, headers: ["etag": "etag-0"]),
            .empty(200),
            .json(["status": "PROCESSING_FAILED", "processingFailureReason": "unsupported format"]),
        ])

        try await withHTTP(client) {
            do {
                _ = try await adapter.publish(
                    content: ResolvedContent(text: "video", media: [item]),
                    context: NullPublishContext(attemptId: "att")
                )
                Issue.record("expected publish to fail")
            } catch let error as ProviderError {
                #expect(error.message.contains("video processing failed"))
                #expect(error.message.contains("unsupported format"))
            }
        }
    }

    // MARK: Session expiry

    @Test func expiredSessionRequiresReconnectBeforePublishing() async throws {
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db, expiresAt: 1)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let client = MockHTTPClient([])

        try await withHTTP(client) {
            do {
                _ = try await adapter.publish(
                    content: ResolvedContent(text: "hello", media: []),
                    context: NullPublishContext(attemptId: "att")
                )
                Issue.record("expected publish to fail")
            } catch let error as ProviderError {
                #expect(error.message.contains("Reconnect LinkedIn"))
            }
        }
        #expect(client.requests.isEmpty)
    }

    @Test func unauthorizedPublishErrorAddsReconnectHint() async throws {
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let client = MockHTTPClient([
            .json(["message": "the token is expired or revoked"], status: 401),
        ])

        try await withHTTP(client) {
            do {
                _ = try await adapter.publish(
                    content: ResolvedContent(text: "hello", media: []),
                    context: NullPublishContext(attemptId: "att")
                )
                Issue.record("expected publish to fail")
            } catch let error as ProviderError {
                #expect(error.message.contains("the token is expired or revoked"))
                #expect(error.message.contains("Reconnect LinkedIn"))
            }
        }
    }

    // MARK: Health

    @Test func linkedinSignedUploadURLsAreRedacted() {
        let raw = "upload failed for https://www.linkedin.com/dms-uploads/abc?ca=vector&ut=link-signature&sau=SGVsbG8x"
        let redacted = Redaction.redact(raw)
        #expect(!redacted.contains("link-signature"))
        #expect(!redacted.contains("SGVsbG8x"))
        #expect(redacted.contains("dms-uploads/abc"))
    }

    @Test func healthReadsMemberProfile() async throws {
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let client = MockHTTPClient([
            .json(["sub": "sub-123", "name": "Alice Example"]),
        ])

        try await withHTTP(client) {
            let result = await adapter.health()
            #expect(result.ok)
            #expect(result.accountLabel == "Alice Example")
            #expect(result.meta["userId"] == "sub-123")
            #expect(result.error == nil)
        }
        let request = try #require(client.requests.first)
        #expect(request.url?.absoluteString == "https://api.linkedin.com/v2/userinfo")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func healthReportsExpiredSession() async throws {
        let db = try AppDatabase.inMemory()
        let account = try makeLinkedInAccount(db, expiresAt: 1)
        let adapter = LinkedInAdapter(accountId: account.id, database: db)
        let client = MockHTTPClient([])

        try await withHTTP(client) {
            let result = await adapter.health()
            #expect(!result.ok)
            #expect(result.error?.contains("Reconnect LinkedIn") == true)
        }
    }
}

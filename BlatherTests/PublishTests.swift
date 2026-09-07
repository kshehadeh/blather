import Foundation
import Testing
@testable import Blather

struct PublishTests {
    @Test func partialSuccessDoesNotRetrySuccess() async throws {
        let db = try AppDatabase.inMemory()
        AdapterRegistry.useMocks = true
        AdapterRegistry.mockFail = [.instagram]
        let media = try db.media.create(
            kind: .image,
            mimeType: "image/jpeg",
            name: "a.jpg",
            size: 1024,
            path: "a.jpg"
        )
        let draft = try db.drafts.create(
            text: "hello world",
            mediaIds: [media.id],
            networks: [.x, .bluesky, .instagram],
            overrides: [:]
        )
        let attempts = try await PublishOrchestrator.publishDraft(id: draft.id, database: db)
        #expect(attempts.count == 3)
        #expect(attempts.filter { $0.status == .success }.count == 2)
        #expect(attempts.first { $0.network == .instagram }?.status == .failed)

        let failed = attempts.first { $0.network == .instagram }!
        AdapterRegistry.mockFail = []
        let retried = try await PublishOrchestrator.retryAttempt(id: failed.id, database: db)
        #expect(retried.status == .success)
        let x = try db.attempts.forDraft(draft.id).first { $0.network == .x }
        #expect(x?.status == .success)
        #expect(x?.providerPostId == attempts.first { $0.network == .x }?.providerPostId)
    }

    @Test func refusesRetryOfSuccess() async throws {
        let db = try AppDatabase.inMemory()
        AdapterRegistry.useMocks = true
        AdapterRegistry.mockFail = []
        let draft = try db.drafts.create(text: "ok", mediaIds: [], networks: [.x], overrides: [:])
        let attempts = try await PublishOrchestrator.publishDraft(id: draft.id, database: db)
        await #expect(throws: PublishError.retryOnlyFailed) {
            try await PublishOrchestrator.retryAttempt(id: attempts[0].id, database: db)
        }
    }

    @Test @MainActor func publishDraftReportsProgress() async throws {
        let db = try AppDatabase.inMemory()
        AdapterRegistry.useMocks = true
        AdapterRegistry.mockFail = [.instagram]
        let media = try db.media.create(
            kind: .image,
            mimeType: "image/jpeg",
            name: "a.jpg",
            size: 1024,
            path: "a.jpg"
        )
        let draft = try db.drafts.create(
            text: "hello world",
            mediaIds: [media.id],
            networks: [.x, .instagram],
            overrides: [:]
        )
        var updates: [(Network, AttemptStatus)] = []
        let attempts = try await PublishOrchestrator.publishDraft(id: draft.id, database: db) { attempt in
            updates.append((attempt.network, attempt.status))
        }
        #expect(attempts.count == 2)
        #expect(updates.contains { $0 == (.x, .pending) })
        #expect(updates.contains { $0 == (.x, .publishing) })
        #expect(updates.contains { $0 == (.x, .success) })
        #expect(updates.contains { $0 == (.instagram, .pending) })
        #expect(updates.contains { $0 == (.instagram, .publishing) })
        #expect(updates.contains { $0 == (.instagram, .failed) })
        #expect(attempts.first { $0.network == .instagram }?.error != nil)
    }

    @Test @MainActor func appModelPublishFillsProgressThenFinishes() async throws {
        AdapterRegistry.useMocks = true
        AdapterRegistry.mockFail = [.instagram]
        let db = try AppDatabase.inMemory()
        let model = AppModel(database: db)
        model.session.text = "hello world"
        model.session.networks = [.x, .instagram]
        model.publish()
        for _ in 0..<100 {
            if model.publishProgress?.isFinished == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let progress = try #require(model.publishProgress)
        #expect(progress.isFinished)
        #expect(progress.items.first { $0.network == .x }?.status == .success)
        #expect(progress.items.first { $0.network == .instagram }?.status == .failed)
        #expect(progress.items.first { $0.network == .instagram }?.error != nil)
        #expect(progress.title == "Published with errors")
        #expect(model.session.text == "hello world")
        #expect(model.session.networks == [.x, .instagram])
        #expect(model.session.lastAttempts.count == 2)
    }

    @Test @MainActor func appModelPublishResetsComposerOnSuccess() async throws {
        AdapterRegistry.useMocks = true
        AdapterRegistry.mockFail = []
        let db = try AppDatabase.inMemory()
        let model = AppModel(database: db)
        model.session.text = "hello world"
        model.session.networks = [.x, .bluesky]
        model.session.overrides[.x] = NetworkOverride(text: "x copy", mediaIds: nil)
        model.publish()
        for _ in 0..<100 {
            if model.publishProgress?.isFinished == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let progress = try #require(model.publishProgress)
        #expect(progress.isFinished)
        #expect(progress.title == "Published")
        #expect(model.session.text.isEmpty)
        #expect(model.session.networks.isEmpty)
        #expect(model.session.media.isEmpty)
        #expect(model.session.overrides.isEmpty)
        #expect(model.session.lastAttempts.isEmpty)
        #expect(model.session.draftId == nil)
        #expect(model.statusMessage == "Published everywhere")
    }

    @Test @MainActor func publishProgressMarksInFlightItemsFailed() {
        let progress = PublishProgress(networks: [.x, .bluesky])
        progress.update(
            PublishAttempt(
                id: "1",
                draftId: "d",
                network: .x,
                status: .success,
                providerPostId: "p",
                providerPostUrl: nil,
                error: nil,
                textSnapshot: "hi",
                createdAt: "",
                updatedAt: ""
            )
        )
        progress.fail("Draft not found")
        #expect(progress.isFinished)
        #expect(progress.items.first { $0.network == .x }?.status == .success)
        #expect(progress.items.first { $0.network == .bluesky }?.status == .failed)
        #expect(progress.items.first { $0.network == .bluesky }?.error == "Draft not found")
        #expect(progress.title == "Published with errors")
    }

    @Test func recoveryMarksStuckPublishingFailed() throws {
        let db = try AppDatabase.inMemory()
        let draft = try db.drafts.create(text: "stuck", mediaIds: [], networks: [.x], overrides: [:])
        let attempt = try db.attempts.create(draftId: draft.id, network: .x, textSnapshot: "stuck")
        try db.attempts.setStatus(id: attempt.id, status: .publishing)
        try PublishOrchestrator.recoverInterrupted(database: db)
        let recovered = try db.attempts.get(attempt.id)
        #expect(recovered?.status == .failed)
        #expect(recovered?.error?.contains("interrupted") == true)
    }
}

@Suite(.serialized)
struct GraphPermalinkTests {
    private func withHTTP<T>(_ client: MockHTTPClient, _ body: () async throws -> T) async rethrows -> T {
        let previous = ProviderHTTP.client
        let previousDelay = GraphPermalink.retryDelay
        let previousAttempts = GraphPermalink.maxAttempts
        ProviderHTTP.client = client
        GraphPermalink.retryDelay = .zero
        defer {
            ProviderHTTP.client = previous
            GraphPermalink.retryDelay = previousDelay
            GraphPermalink.maxAttempts = previousAttempts
        }
        return try await body()
    }

    @Test func parseReadsPermalink() {
        #expect(GraphPermalink.parse(["permalink": "https://www.threads.net/t/abc"]) == "https://www.threads.net/t/abc")
        #expect(GraphPermalink.parse(["permalink": "https://www.instagram.com/p/xyz/"]) == "https://www.instagram.com/p/xyz/")
    }

    @Test func parseMissingOrEmptyIsNil() {
        #expect(GraphPermalink.parse(["id": "123"]) == nil)
        #expect(GraphPermalink.parse(["permalink": ""]) == nil)
        #expect(GraphPermalink.parse(["permalink": "   "]) == nil)
        #expect(GraphPermalink.parse(["permalink": "not a url"]) == nil)
        #expect(GraphPermalink.parse(nil) == nil)
    }

    @Test func fetchRetriesUntilPermalinkAppears() async {
        let client = MockHTTPClient([
            .json(["id": "1789"]),
            .json(["permalink": ""]),
            .json(["permalink": "https://www.threads.net/t/retry"]),
        ])
        await withHTTP(client) {
            let url = await GraphPermalink.fetch(
                network: .threads,
                graphBase: "https://graph.threads.net/v1.0",
                mediaId: "1789",
                accessToken: "tok"
            )
            #expect(url == "https://www.threads.net/t/retry")
            #expect(client.requests.count == 3)
            #expect(client.requests.last?.url?.absoluteString.contains("1789") == true)
            #expect(client.requests.last?.url?.absoluteString.contains("fields=permalink") == true)
        }
    }

    @Test func fetchFailureReturnsNil() async {
        let client = MockHTTPClient([
            .status(500),
            .status(500),
            .status(500),
            .status(500),
        ])
        await withHTTP(client) {
            let url = await GraphPermalink.fetch(
                network: .instagram,
                graphBase: "https://graph.instagram.com/v21.0",
                mediaId: "99",
                accessToken: "tok"
            )
            #expect(url == nil)
        }
    }

    @Test func emptyMediaIdDoesNotRequest() async {
        let client = MockHTTPClient([])
        await withHTTP(client) {
            let url = await GraphPermalink.fetch(
                network: .threads,
                graphBase: "https://graph.threads.net/v1.0",
                mediaId: "  ",
                accessToken: "tok"
            )
            #expect(url == nil)
            #expect(client.requests.isEmpty)
        }
    }

    @Test func publishResultKeepsIdWhenPermalinkMissing() async {
        let client = MockHTTPClient(Array(repeating: .json(["id": "1789"]), count: 4))
        await withHTTP(client) {
            let result = await GraphPermalink.publishResult(
                network: .threads,
                graphBase: "https://graph.threads.net/v1.0",
                mediaId: "1789",
                accessToken: "tok"
            )
            #expect(result.providerPostId == "1789")
            #expect(result.providerPostUrl == nil)
        }
    }

    @Test func backfillWritesPermalinkWhenConnected() async throws {
        Keychain.store = MemoryKeychainStore()
        AdapterRegistry.useMocks = false
        defer {
            AdapterRegistry.useMocks = true
            Keychain.store = MacOSKeychainStore()
        }
        let db = try AppDatabase.inMemory()
        try ConnectionStore.storeOAuth(
            network: .threads,
            tokens: OAuthTokens(accessToken: "tok", refreshToken: nil, expiresAt: nil, meta: ["userId": "1"]),
            accountLabel: "@me",
            meta: ["userId": "1"],
            database: db
        )
        try ConnectionStore.storeOAuth(
            network: .instagram,
            tokens: OAuthTokens(accessToken: "ig-tok", refreshToken: nil, expiresAt: nil, meta: ["igUserId": "1"]),
            accountLabel: "@ig",
            meta: ["igUserId": "1"],
            database: db
        )
        let draft = try db.drafts.create(text: "hi", mediaIds: [], networks: [.threads, .instagram], overrides: [:])
        let threads = try db.attempts.create(draftId: draft.id, network: .threads, textSnapshot: "hi")
        try db.attempts.setStatus(id: threads.id, status: .success, providerPostId: "1789")
        let instagram = try db.attempts.create(draftId: draft.id, network: .instagram, textSnapshot: "hi")
        try db.attempts.setStatus(id: instagram.id, status: .success, providerPostId: "99")

        let client = MockHTTPClient([])
        client.onRequest = { request in
            if request.url?.host == "graph.threads.net" {
                return .json(["permalink": "https://www.threads.net/t/backfill"])
            }
            return .json(["permalink": "https://www.instagram.com/p/backfill/"])
        }
        await withHTTP(client) {
            let changed = await PublishOrchestrator.backfillMissingPostURLs(database: db)
            #expect(changed)
            #expect(Set(client.requests.compactMap { $0.url?.host }) == ["graph.threads.net", "graph.instagram.com"])
        }
        #expect(try db.attempts.get(threads.id)?.providerPostUrl == "https://www.threads.net/t/backfill")
        #expect(try db.attempts.get(instagram.id)?.providerPostUrl == "https://www.instagram.com/p/backfill/")
    }

    @Test func backfillSkipsDisconnectedFailedAndOtherNetworks() async throws {
        Keychain.store = MemoryKeychainStore()
        AdapterRegistry.useMocks = false
        defer {
            AdapterRegistry.useMocks = true
            Keychain.store = MacOSKeychainStore()
        }
        let db = try AppDatabase.inMemory()
        let draft = try db.drafts.create(text: "hi", mediaIds: [], networks: [.threads, .instagram, .x], overrides: [:])

        let disconnected = try db.attempts.create(draftId: draft.id, network: .threads, textSnapshot: "hi")
        try db.attempts.setStatus(id: disconnected.id, status: .success, providerPostId: "1")

        try ConnectionStore.storeOAuth(
            network: .instagram,
            tokens: OAuthTokens(accessToken: "tok", refreshToken: nil, expiresAt: nil, meta: ["igUserId": "1"]),
            accountLabel: "@ig",
            meta: ["igUserId": "1"],
            database: db
        )
        let failed = try db.attempts.create(draftId: draft.id, network: .instagram, textSnapshot: "hi")
        try db.attempts.setStatus(id: failed.id, status: .failed, providerPostId: "2", error: "nope")

        let x = try db.attempts.create(draftId: draft.id, network: .x, textSnapshot: "hi")
        try db.attempts.setStatus(id: x.id, status: .success, providerPostId: "3")

        let client = MockHTTPClient([.json(["permalink": "https://www.instagram.com/p/should-not-run/"])])
        await withHTTP(client) {
            let changed = await PublishOrchestrator.backfillMissingPostURLs(database: db)
            #expect(!changed)
            #expect(client.requests.isEmpty)
        }
        #expect(try db.attempts.get(disconnected.id)?.providerPostUrl == nil)
        #expect(try db.attempts.get(failed.id)?.providerPostUrl == nil)
        #expect(try db.attempts.get(x.id)?.providerPostUrl == nil)
    }
}

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    struct Exchange {
        var status: Int
        var json: Any?
        var error: Error?
        var rawBody: Data? = nil

        static func json(_ value: Any, status: Int = 200) -> Exchange {
            Exchange(status: status, json: value, error: nil)
        }

        static func status(_ code: Int) -> Exchange {
            Exchange(status: code, json: ["error": ["message": "http \(code)"]], error: nil)
        }

        static func empty(_ status: Int = 200) -> Exchange {
            Exchange(status: status, json: nil, error: nil, rawBody: Data())
        }

        static func raw(_ body: Data, status: Int) -> Exchange {
            Exchange(status: status, json: nil, error: nil, rawBody: body)
        }
    }

    var exchanges: [Exchange]
    var onRequest: ((URLRequest) -> Exchange)?
    var requests: [URLRequest] = []

    init(_ exchanges: [Exchange]) {
        self.exchanges = exchanges
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let exchange: Exchange
        if let onRequest {
            exchange = onRequest(request)
        } else {
            guard !exchanges.isEmpty else {
                throw URLError(.badServerResponse)
            }
            exchange = exchanges.removeFirst()
        }
        if let error = exchange.error { throw error }
        let data: Data
        if let rawBody = exchange.rawBody {
            data = rawBody
        } else if let json = exchange.json {
            data = try JSONSerialization.data(withJSONObject: json)
        } else {
            data = Data()
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: exchange.status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

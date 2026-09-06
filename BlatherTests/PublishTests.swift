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

import Foundation
import Testing
@testable import Blather

struct PersistenceTests {
    private func database() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }

    @Test func draftRoundTrip() throws {
        let db = try database()
        let created = try db.drafts.create(
            text: "hello",
            mediaIds: [],
            networks: [.x, .bluesky],
            overrides: [.x: NetworkOverride(text: "short", mediaIds: nil)]
        )
        let fetched = try db.drafts.get(created.id)
        #expect(fetched?.text == "hello")
        #expect(fetched?.networks == [.x, .bluesky])
        #expect(fetched?.overrides[.x]?.text == "short")

        let updated = try db.drafts.update(id: created.id, text: "updated")
        #expect(updated?.text == "updated")
        #expect(try db.drafts.list().count == 1)
        try db.drafts.remove(created.id)
        #expect(try db.drafts.list().isEmpty)
    }

    @Test func attemptStatusAndStuckPublishing() throws {
        let db = try database()
        let draft = try db.drafts.create(text: "p", mediaIds: [], networks: [.x], overrides: [:])
        let attempt = try db.attempts.create(draftId: draft.id, network: .x, textSnapshot: "p")
        try db.attempts.setStatus(id: attempt.id, status: .publishing)
        #expect(try db.attempts.stuckPublishing().count == 1)
        try db.attempts.setStatus(id: attempt.id, status: .failed, error: "interrupted")
        #expect(try db.attempts.get(attempt.id)?.status == .failed)
        #expect(try db.attempts.stuckPublishing().isEmpty)
    }

    @Test func connectionUpsertPreservesCredentialRef() throws {
        let db = try database()
        try db.connections.upsert(
            network: .x,
            state: .connected,
            credentialRef: "oauth.x.abc",
            accountLabel: "@me",
            meta: ["userId": "1"]
        )
        try db.connections.upsert(network: .x, state: .error, error: "token expired")
        let conn = try db.connections.get(.x)
        #expect(conn.state == .error)
        #expect(conn.credentialRef == "oauth.x.abc")
        #expect(conn.accountLabel == "@me")
        try db.connections.clear(.x)
        #expect(try db.connections.get(.x).state == .disconnected)
    }

    @Test func r2ViewRequiresCredentials() throws {
        let db = try database()
        #expect(try db.r2.view().configured == false)
        try db.r2.save(StoredR2Settings(
            accountId: "acct",
            bucket: "media",
            publicUrlStrategy: "presigned",
            publicBaseUrl: nil,
            credentialRef: "r2.acct.1"
        ))
        #expect(try db.r2.view().configured)
        #expect(try db.r2.view().hasCredentials)
    }

    @Test func r2JurisdictionRoundTrip() throws {
        let db = try database()
        try db.r2.save(StoredR2Settings(
            accountId: "acct",
            bucket: "media",
            publicUrlStrategy: "presigned",
            publicBaseUrl: nil,
            credentialRef: "r2.acct.1",
            jurisdiction: "eu"
        ))
        #expect(try db.r2.get()?.jurisdiction == "eu")
        #expect(try db.r2.view().jurisdiction == "eu")
    }

    @Test func oauthStateIsSingleUse() throws {
        let db = try database()
        try db.oauthStates.create(provider: "x", state: "abc", verifier: "ver")
        let first = try db.oauthStates.consume(provider: "x", state: "abc")
        #expect(first == "ver")
        let second = try db.oauthStates.consume(provider: "x", state: "abc")
        #expect(second == nil)
    }

    @Test func memoryKeychainRoundTrip() throws {
        let store = MemoryKeychainStore()
        try store.set(ref: "oauth.x.1", secret: #"{"accessToken":"tok"}"#)
        #expect(store.get(ref: "oauth.x.1") == #"{"accessToken":"tok"}"#)
        store.remove(ref: "oauth.x.1")
        #expect(store.get(ref: "oauth.x.1") == nil)
    }

    @Test func credentialsStoreJSON() throws {
        Keychain.store = MemoryKeychainStore()
        let ref = Credentials.makeRef(kind: "oauth", owner: "x")
        try Credentials.store(ref, value: OAuthTokens(accessToken: "a", refreshToken: "b", expiresAt: 1, meta: ["k": "v"]))
        let tokens = Credentials.read(OAuthTokens.self, ref: ref)
        #expect(tokens?.accessToken == "a")
        #expect(tokens?.meta?["k"] == "v")
        Credentials.delete(ref: ref)
        #expect(Credentials.read(OAuthTokens.self, ref: ref) == nil)
    }

    @Test func redactStripsTokens() {
        let raw = #"Bearer abc.def Authorization access_token=supersecret X-Amz-Signature=deadbeef"#
        let redacted = Redaction.redact(raw)
        #expect(!redacted.contains("supersecret"))
        #expect(!redacted.contains("deadbeef"))
        #expect(redacted.contains("[redacted]"))
    }
}

struct ValidationTests {
    private func image(_ over: (inout MediaItem) -> Void = { _ in }) -> MediaItem {
        var item = MediaItem(
            id: UUID().uuidString,
            kind: .image,
            mimeType: "image/jpeg",
            name: "a.jpg",
            size: 1024,
            createdAt: Time.now()
        )
        over(&item)
        return item
    }

    @Test func acceptsPlainTextOnTextNetworks() throws {
        for network: Network in [.x, .bluesky, .threads] {
            try ContentValidation.validate(network, content: ResolvedContent(text: "hello", media: []))
        }
    }

    @Test func instagramRequiresMedia() {
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(.instagram, content: ResolvedContent(text: "hi", media: []))
        }
        try! ContentValidation.validate(.instagram, content: ResolvedContent(text: "hi", media: [image()]))
    }

    @Test func enforcesCharacterLimits() {
        let text = String(repeating: "x", count: 281)
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(.x, content: ResolvedContent(text: text, media: []))
        }
    }

    @Test func rejectsMixedMediaWhenUnsupported() {
        let video = MediaItem(
            id: UUID().uuidString,
            kind: .video,
            mimeType: "video/mp4",
            name: "v.mp4",
            size: 1024,
            createdAt: Time.now()
        )
        #expect(throws: ProviderError.self) {
            try ContentValidation.validate(.x, content: ResolvedContent(text: "hi", media: [image(), video]))
        }
    }

    @Test func overrideInheritsBaseText() {
        let media = image()
        let resolved = Overrides.resolveContent(
            text: "base",
            mediaIds: [media.id],
            overrides: [.x: NetworkOverride(text: "override", mediaIds: nil)],
            network: .x,
            mediaById: [media.id: media]
        )
        #expect(resolved.text == "override")
        #expect(resolved.media.map(\.id) == [media.id])
        let inherited = Overrides.resolveContent(
            text: "base",
            mediaIds: [media.id],
            overrides: [:],
            network: .bluesky,
            mediaById: [media.id: media]
        )
        #expect(inherited.text == "base")
    }
}

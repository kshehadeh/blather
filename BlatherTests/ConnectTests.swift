import Foundation
import Testing
@testable import Blather

struct ConnectTests {
    @Test func pkceVerifierAndChallengeAreBase64URL() {
        let pair = PKCE.generate()
        #expect(!pair.verifier.contains("+"))
        #expect(!pair.verifier.contains("/"))
        #expect(!pair.challenge.contains("="))
        #expect(pair.verifier.count >= 32)
        #expect(pair.challenge.count == 43)
    }

    @Test func oauthConnectionRoundTrip() throws {
        Keychain.store = MemoryKeychainStore()
        let db = try AppDatabase.inMemory()
        try ConnectionStore.storeOAuth(
            network: .x,
            tokens: OAuthTokens(accessToken: "tok", refreshToken: "ref", expiresAt: 1, meta: ["clientId": "abc"]),
            accountLabel: "@me",
            meta: ["userId": "1"],
            database: db
        )
        let conn = try db.connections.get(.x)
        #expect(conn.state == .connected)
        #expect(conn.accountLabel == "@me")
        let tokens = TokenAccess.loadTokens(network: .x, database: db)
        #expect(tokens?.accessToken == "tok")
        #expect(tokens?.meta?["clientId"] == "abc")
        try ConnectionStore.disconnect(network: .x, database: db)
        #expect(TokenAccess.loadTokens(network: .x, database: db) == nil)
        #expect(try db.connections.get(.x).state == .disconnected)
    }

    @Test func pendingConfigIsSingleUse() throws {
        Keychain.store = MemoryKeychainStore()
        try ConnectionStore.stashPending(state: "s1", config: ["clientId": "abc"])
        #expect(ConnectionStore.popPending(state: "s1")?["clientId"] == "abc")
        #expect(ConnectionStore.popPending(state: "s1") == nil)
    }

    @Test func blueskyFacetsDetectLinksAndTags() {
        let facets = BlueskyAdapter.buildFacets("hello https://example.com and #tag")
        #expect(facets.count == 2)
    }

    @Test func jsonErrorMessagePrefersNestedError() {
        let body: [String: Any] = ["error": ["message": "nope"]]
        #expect(JSONValue.message(from: body, fallback: "x") == "nope")
    }

    @Test func fakeR2StagesURL() async throws {
        let db = try AppDatabase.inMemory()
        let media = try db.media.create(kind: .image, mimeType: "image/png", name: "a.png", size: 10, path: "a.png")
        let stager = FakeR2Stager(
            database: db,
            settings: StoredR2Settings(accountId: "acct", bucket: "bucket", publicUrlStrategy: "presigned", publicBaseUrl: nil, credentialRef: nil)
        )
        let staged = try await stager.stage(mediaId: media.id, attemptId: "att")
        #expect(staged.url.contains("fake-r2.local"))
        #expect(staged.key.contains(media.id))
    }
}

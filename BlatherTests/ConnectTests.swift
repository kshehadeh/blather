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

    @Test func connectedAccountExposesNonSecretSettings() throws {
        Keychain.store = MemoryKeychainStore()
        let db = try AppDatabase.inMemory()
        try ConnectionStore.storeOAuth(
            network: .threads,
            tokens: OAuthTokens(
                accessToken: "tok",
                meta: ["clientId": "app-id", "clientSecret": "shh", "userId": "1"]
            ),
            accountLabel: "@foo",
            meta: ["userId": "1"],
            database: db
        )
        let threads = AccountSettings.load(network: .threads, database: db)
        #expect(threads.clientId == "app-id")
        #expect(threads.hasStoredSecret)

        try ConnectionStore.storeBasic(
            network: .bluesky,
            credentials: BasicCredentials(
                identifier: "me.bsky.social",
                secret: "app-pass",
                meta: ["pds": "https://bsky.social", "did": "did:plc:1"]
            ),
            accountLabel: "@me.bsky.social",
            meta: ["pds": "https://bsky.social", "did": "did:plc:1"],
            database: db
        )
        let bluesky = AccountSettings.load(network: .bluesky, database: db)
        #expect(bluesky.pds == "https://bsky.social")
        #expect(bluesky.handle == "me.bsky.social")
        #expect(bluesky.hasStoredSecret)
        #expect(AccountSettings.handle(from: "@foo") == "foo")
    }

    @Test func blankSecretSaveIsNoOpAndKeepsKeychainItem() throws {
        Keychain.store = MemoryKeychainStore()
        let db = try AppDatabase.inMemory()
        try ConnectionStore.storeOAuth(
            network: .x,
            tokens: OAuthTokens(accessToken: "tok", refreshToken: "ref", expiresAt: 1, meta: ["clientId": "abc"]),
            accountLabel: "@me",
            meta: ["userId": "1"],
            database: db
        )
        let ref = try db.connections.get(.x).credentialRef
        let stored = AccountSettings.load(network: .x, database: db)
        let plan = AccountSettings.plan(
            network: .x,
            clientId: "abc",
            clientSecret: "",
            pds: "",
            handle: "",
            appPassword: "",
            stored: stored,
            storedAppPassword: nil,
            storedClientSecret: nil
        )
        #expect(plan == .noOp)
        #expect(try db.connections.get(.x).credentialRef == ref)
        #expect(TokenAccess.loadTokens(network: .x, database: db)?.accessToken == "tok")
    }

    @Test func blueskyBlankPasswordReusesStoredSecretWhenFieldsChange() {
        let stored = AccountConnectSettings(pds: "https://bsky.social", handle: "me.bsky.social", hasStoredSecret: true)
        let plan = AccountSettings.plan(
            network: .bluesky,
            clientId: "",
            clientSecret: "",
            pds: "https://custom.pds",
            handle: "me.bsky.social",
            appPassword: "",
            stored: stored,
            storedAppPassword: "old-pass",
            storedClientSecret: nil
        )
        #expect(plan == .reconnectBluesky(pds: "https://custom.pds", handle: "me.bsky.social", appPassword: "old-pass"))
    }

    @Test func blueskyUnchangedBlankPasswordIsNoOp() {
        let stored = AccountConnectSettings(pds: "https://bsky.social", handle: "me.bsky.social", hasStoredSecret: true)
        let plan = AccountSettings.plan(
            network: .bluesky,
            clientId: "",
            clientSecret: "",
            pds: "https://bsky.social/",
            handle: "me.bsky.social",
            appPassword: "",
            stored: stored,
            storedAppPassword: "old-pass",
            storedClientSecret: nil
        )
        #expect(plan == .noOp)
    }

    @Test func metaAppIdChangeReusesStoredSecret() {
        let stored = AccountConnectSettings(clientId: "old-id", hasStoredSecret: true)
        let plan = AccountSettings.plan(
            network: .threads,
            clientId: "new-id",
            clientSecret: "",
            pds: "",
            handle: "",
            appPassword: "",
            stored: stored,
            storedAppPassword: nil,
            storedClientSecret: "stored-secret"
        )
        #expect(plan == .reconnectThreads(clientId: "new-id", clientSecret: "stored-secret"))
    }

    @Test func disconnectDoesNotDeleteDraftsOrHistory() throws {
        Keychain.store = MemoryKeychainStore()
        let db = try AppDatabase.inMemory()
        try ConnectionStore.storeOAuth(
            network: .x,
            tokens: OAuthTokens(accessToken: "tok", refreshToken: "ref", expiresAt: 1, meta: ["clientId": "abc"]),
            accountLabel: "@me",
            meta: ["userId": "1"],
            database: db
        )
        let draft = try db.drafts.create(text: "hello", mediaIds: [], networks: [.x], overrides: [:])
        _ = try db.attempts.create(draftId: draft.id, network: .x, textSnapshot: "hello")
        try ConnectionStore.disconnect(network: .x, database: db)
        #expect(try db.connections.get(.x).state == .disconnected)
        #expect(TokenAccess.loadTokens(network: .x, database: db) == nil)
        #expect(try db.drafts.get(draft.id)?.text == "hello")
        #expect(try db.attempts.list().count == 1)
        #expect(try db.attempts.list().first?.network == .x)
    }

    @Test @MainActor func saveAccountWithBlankSecretKeepsKeychainItem() throws {
        Keychain.store = MemoryKeychainStore()
        let db = try AppDatabase.inMemory()
        try ConnectionStore.storeOAuth(
            network: .x,
            tokens: OAuthTokens(accessToken: "tok", refreshToken: "ref", expiresAt: 1, meta: ["clientId": "abc"]),
            accountLabel: "@me",
            meta: ["userId": "1"],
            database: db
        )
        let ref = try db.connections.get(.x).credentialRef
        let model = AppModel(database: db)
        model.saveAccount(
            network: .x,
            clientId: "abc",
            clientSecret: "",
            pds: "",
            handle: "",
            appPassword: ""
        )
        #expect(try db.connections.get(.x).credentialRef == ref)
        #expect(TokenAccess.loadTokens(network: .x, database: db)?.accessToken == "tok")
        #expect(model.statusMessage == "No changes to save")
        #expect(model.connection(for: .x).state == .connected)
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

    @Test func r2EndpointParsesAccountIdAndJurisdiction() {
        #expect(R2Endpoint.parse(accountId: "  abcdef1234  ").accountId == "abcdef1234")
        #expect(R2Endpoint.parse(accountId: "abcdef1234").jurisdiction == nil)

        let fromURL = R2Endpoint.parse(accountId: "https://abcdef1234.r2.cloudflarestorage.com/")
        #expect(fromURL.accountId == "abcdef1234")
        #expect(fromURL.jurisdiction == nil)

        let eu = R2Endpoint.parse(accountId: "https://abcdef1234.eu.r2.cloudflarestorage.com")
        #expect(eu.accountId == "abcdef1234")
        #expect(eu.jurisdiction == "eu")

        let selected = R2Endpoint.parse(accountId: "abcdef1234", jurisdiction: "US")
        #expect(selected.jurisdiction == "us")
        #expect(R2Endpoint.host(accountId: "abcdef1234", jurisdiction: "eu") == "abcdef1234.eu.r2.cloudflarestorage.com")
    }

    @Test func r2APIErrorSurfacesXMLCode() {
        let xml = Data("<Error><Code>AuthorizationHeaderMalformed</Code><Message>Wrong region</Message></Error>".utf8)
        let message = R2APIError.message(status: 400, body: xml, operation: "connection")
        #expect(message.contains("R2 S3 credentials"))
        #expect(message.contains("jurisdiction"))
    }

    @Test func sigV4MatchesAWSHeaderExample() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2013, month: 5, day: 24))!
        let headers = SigV4.signedHeaders(
            method: "GET",
            url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!,
            region: "us-east-1",
            service: "s3",
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            extraHeaders: ["range": "bytes=0-9"],
            body: Data(),
            now: now
        )
        #expect(headers["authorization"] == nil)
        #expect(
            headers["Authorization"]
                == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"
        )
    }

    @Test func r2TestConnectionUploadsProbeAndReportsXMLError() async throws {
        let db = try AppDatabase.inMemory()
        let stager = CloudflareR2Stager(
            database: db,
            settings: StoredR2Settings(
                accountId: "acct",
                bucket: "media",
                publicUrlStrategy: "presigned",
                publicBaseUrl: nil,
                credentialRef: "ref",
                jurisdiction: "eu"
            ),
            credentials: R2Credentials(accessKeyId: "AKID", secretAccessKey: "secret")
        )
        let xml = Data("<Error><Code>NoSuchBucket</Code><Message>The specified bucket does not exist.</Message></Error>".utf8)
        let client = MockHTTPClient([.raw(xml, status: 400)])
        let previous = ProviderHTTP.client
        ProviderHTTP.client = client
        defer { ProviderHTTP.client = previous }

        do {
            try await stager.testConnection()
            Issue.record("expected R2 connection failure")
        } catch let error as R2Error {
            #expect(error.localizedDescription.contains("jurisdiction"))
        }

        #expect(client.requests.count == 1)
        #expect(client.requests.first?.httpMethod == "PUT")
        #expect(client.requests.first?.url?.host == "acct.eu.r2.cloudflarestorage.com")
        #expect(client.requests.first?.url?.path.contains("blather-staging/.connection-test") == true)
    }

    @Test func r2TestConnectionSucceedsOnPutAndDelete() async throws {
        let db = try AppDatabase.inMemory()
        let stager = CloudflareR2Stager(
            database: db,
            settings: StoredR2Settings(
                accountId: "acct",
                bucket: "media",
                publicUrlStrategy: "presigned",
                publicBaseUrl: nil,
                credentialRef: "ref"
            ),
            credentials: R2Credentials(accessKeyId: "AKID", secretAccessKey: "secret")
        )
        let client = MockHTTPClient([.empty(200), .empty(204)])
        let previous = ProviderHTTP.client
        ProviderHTTP.client = client
        defer { ProviderHTTP.client = previous }
        try await stager.testConnection()
        #expect(client.requests.map(\.httpMethod) == ["PUT", "DELETE"])
    }
}

import AppKit
import Testing
@testable import Blather

struct SmokeTests {
    @Test func networksHaveCapabilities() {
        for network in Network.allCases {
            let caps = Capabilities.capabilities(for: network)
            #expect(caps.network == network)
            #expect(caps.maxChars > 0)
        }
    }

    @Test func instagramRequiresMedia() {
        #expect(Capabilities.capabilities(for: .instagram).requiresMedia)
        #expect(!Capabilities.capabilities(for: .x).requiresMedia)
    }

    @Test func draftSessionHasNoChangesUntilEdited() {
        let session = DraftSession()
        #expect(!session.hasChanges)

        session.text = "hello"
        #expect(session.hasChanges)

        session.text = ""
        #expect(!session.hasChanges)

        let x = ConnectionInfo(id: "x-1", network: .x, state: .connected, meta: [:])
        session.setAccount(x, enabled: true)
        #expect(session.hasChanges)

        session.setAccount(x, enabled: false)
        session.overrides[.x] = NetworkOverride(text: "override", mediaIds: nil)
        #expect(session.hasChanges)

        session.overrides = [:]
        session.draftId = "d1"
        #expect(session.hasChanges)
    }

    @Test @MainActor func discardDraftClearsComposerChanges() throws {
        let db = try AppDatabase.inMemory()
        let model = AppModel(database: db)
        let x = try makeTestAccount(db, network: .x)
        model.reload()
        #expect(!model.session.hasChanges)

        model.session.text = "hello"
        model.session.setAccount(x, enabled: true)
        model.saveDraft()
        #expect(model.session.hasChanges)
        #expect(model.session.draftId != nil)

        model.discardDraft()
        #expect(!model.session.hasChanges)
        #expect(model.session.draftId == nil)
        #expect(model.drafts.isEmpty)
    }

    @Test func draftSessionWarnsOnOverLimit() {
        let session = DraftSession()
        session.text = String(repeating: "x", count: 281)
        let warnings = session.warnings(for: .x)
        #expect(warnings.contains { $0.contains("over limit") })
    }

    @Test func draftSessionHidesOverridesWhenOnlyOneDestination() {
        let session = DraftSession()
        session.text = "shared"
        let x = ConnectionInfo(id: "x-1", network: .x, state: .connected, meta: [:])
        let bluesky = ConnectionInfo(id: "b-1", network: .bluesky, state: .connected, meta: [:])
        session.setAccount(x, enabled: true)
        session.overrides[.x] = NetworkOverride(text: "x only", mediaIds: nil)
        #expect(!session.showsDestinationOverrides)
        #expect(session.resolvedContent(for: .x).text == "shared")

        session.setAccount(bluesky, enabled: true)
        session.overrides[.x] = NetworkOverride(text: "x only", mediaIds: nil)
        #expect(session.showsDestinationOverrides)
        #expect(session.resolvedContent(for: .x).text == "x only")
        #expect(session.resolvedContent(for: .bluesky).text == "shared")

        session.setAccount(bluesky, enabled: false)
        #expect(!session.showsDestinationOverrides)
        #expect(session.overrides.isEmpty)
        #expect(session.resolvedContent(for: .x).text == "shared")
    }

    @Test func draftSessionDropsOverridesWhenOpeningSingleDestinationDraft() {
        let draft = Draft(
            id: "d1",
            text: "shared",
            mediaIds: [],
            accountIds: ["x-1"],
            networks: [.x],
            overrides: [.x: NetworkOverride(text: "x only", mediaIds: nil)],
            createdAt: "",
            updatedAt: ""
        )
        let account = ConnectionInfo(id: "x-1", network: .x, state: .connected, meta: [:])
        let session = DraftSession(draft: draft, media: [], accounts: [account])
        #expect(!session.showsDestinationOverrides)
        #expect(session.overrides.isEmpty)
        #expect(session.resolvedContent(for: .x).text == "shared")
    }

    @Test func sidebarHasComposeAndHistory() {
        #expect(SidebarItem.allCases.map(\.rawValue) == ["compose", "history"])
    }

    @Test @MainActor func focusingAccountBumpsGeneration() {
        let nav = SettingsNavigation.shared
        nav.clearAccountFocus()
        let start = nav.focusGeneration
        nav.focusAccount(.threads)
        #expect(nav.focusedNetwork == .threads)
        #expect(nav.focusGeneration == start + 1)
        nav.focusAccount(.instagram)
        #expect(nav.focusedNetwork == .instagram)
        #expect(nav.focusGeneration == start + 2)
        nav.focusAccount(.instagram)
        #expect(nav.focusGeneration == start + 3)
        nav.clearAccountFocus()
        #expect(nav.focusedNetwork == nil)
        #expect(nav.focusGeneration == start + 3)
    }

    @Test func networksHaveBrandImages() {
        let names = Network.allCases.map(\.imageName)
        #expect(Set(names).count == names.count)
        for network in Network.allCases {
            #expect(!network.imageName.isEmpty)
            #expect(NSImage(named: NSImage.Name(network.imageName)) != nil)
        }
    }

    @Test func accountFieldsExplainExpectedValues() {
        let guidance = [
            AccountFieldGuidance.xClientId,
            AccountFieldGuidance.blueskyPDS,
            AccountFieldGuidance.blueskyHandle,
            AccountFieldGuidance.blueskyAppPassword,
            AccountFieldGuidance.metaAppId(for: .threads),
            AccountFieldGuidance.metaAppSecret(for: .threads),
            AccountFieldGuidance.metaAppId(for: .instagram),
            AccountFieldGuidance.metaAppSecret(for: .instagram),
        ]
        #expect(guidance.allSatisfy { !$0.example.isEmpty && !$0.help.isEmpty })
        #expect(AccountFieldGuidance.blueskyHandle.example.contains("alice.bsky.social"))
        #expect(AccountFieldGuidance.blueskyHandle.help.contains("alice@example.com"))
        #expect(AccountFieldGuidance.blueskyAppPassword.help.contains("normal account password"))
    }

    @Test func accountSetupHelpCoversEveryNetwork() {
        for network in Network.allCases {
            let content = AccountSetupHelpContent.forNetwork(network)
            #expect(!content.title.isEmpty)
            #expect(!content.intro.isEmpty)
            #expect(content.steps.count == 4)
            #expect(content.steps.allSatisfy { !$0.isEmpty })
            #expect(!content.linkTitle.isEmpty)
        }

        let x = AccountSetupHelpContent.forNetwork(.x)
        #expect(x.title.contains("Client ID"))
        #expect(x.steps.contains { $0.contains("/api/connect/x/callback") })
        #expect(x.steps.contains { $0.contains("OAuth 2.0 Client ID") })
        #expect(x.linkURL.host == "developer.x.com")

        let bluesky = AccountSetupHelpContent.forNetwork(.bluesky)
        #expect(bluesky.steps.contains { $0.contains("App passwords") })
        #expect(bluesky.steps.contains { $0.contains("normal account password") })
        #expect(bluesky.linkURL.absoluteString.contains("app-passwords"))

        let threads = AccountSetupHelpContent.forNetwork(.threads)
        #expect(threads.steps.contains { $0.contains("/api/connect/threads/callback") })
        #expect(threads.linkURL.host == "developers.facebook.com")
    }
}

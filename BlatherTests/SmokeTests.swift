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

        session.networks = [.x]
        #expect(session.hasChanges)

        session.networks = []
        session.overrides[.x] = NetworkOverride(text: "override", mediaIds: nil)
        #expect(session.hasChanges)

        session.overrides = [:]
        session.draftId = "d1"
        #expect(session.hasChanges)
    }

    @Test @MainActor func discardDraftClearsComposerChanges() throws {
        let db = try AppDatabase.inMemory()
        let model = AppModel(database: db)
        #expect(!model.session.hasChanges)

        model.session.text = "hello"
        model.session.networks = [.x]
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
        session.networks = [.x]
        let warnings = session.warnings(for: .x)
        #expect(warnings.contains { $0.contains("over limit") })
    }

    @Test func draftSessionHidesOverridesWhenOnlyOneDestination() {
        let session = DraftSession()
        session.text = "shared"
        session.setNetwork(.x, enabled: true)
        session.overrides[.x] = NetworkOverride(text: "x only", mediaIds: nil)
        #expect(!session.showsDestinationOverrides)
        #expect(session.resolvedContent(for: .x).text == "shared")

        session.setNetwork(.bluesky, enabled: true)
        session.overrides[.x] = NetworkOverride(text: "x only", mediaIds: nil)
        #expect(session.showsDestinationOverrides)
        #expect(session.resolvedContent(for: .x).text == "x only")
        #expect(session.resolvedContent(for: .bluesky).text == "shared")

        session.setNetwork(.bluesky, enabled: false)
        #expect(!session.showsDestinationOverrides)
        #expect(session.overrides.isEmpty)
        #expect(session.resolvedContent(for: .x).text == "shared")
    }

    @Test func draftSessionDropsOverridesWhenOpeningSingleDestinationDraft() {
        let draft = Draft(
            id: "d1",
            text: "shared",
            mediaIds: [],
            networks: [.x],
            overrides: [.x: NetworkOverride(text: "x only", mediaIds: nil)],
            createdAt: "",
            updatedAt: ""
        )
        let session = DraftSession(draft: draft, media: [])
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
}

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

    @Test func draftSessionWarnsOnOverLimit() {
        let session = DraftSession()
        session.text = String(repeating: "x", count: 281)
        session.networks = [.x]
        let warnings = session.warnings(for: .x)
        #expect(warnings.contains { $0.contains("over limit") })
    }

    @Test func sidebarHasComposeAndHistory() {
        #expect(SidebarItem.allCases.map(\.rawValue) == ["compose", "history"])
    }
}

import Foundation

struct PublishResult: Hashable, Sendable {
    var providerPostId: String?
    var providerPostUrl: String?
}

struct HealthResult: Hashable, Sendable {
    var ok: Bool
    var accountLabel: String?
    var meta: [String: String]
    var error: String?
}

protocol PublishContext: Sendable {
    var attemptId: String { get }
    func stageMedia(mediaId: String, attemptId: String?) async throws -> (key: String, url: String)
    func removeStaged(key: String) async
}

protocol ProviderAdapter: Sendable {
    var network: Network { get }
    func isConnected() -> Bool
    func refreshIfNeeded() async throws
    func validate(content: ResolvedContent) throws
    func publish(content: ResolvedContent, context: any PublishContext) async throws -> PublishResult
    func normalizeError(_ error: Error) -> String
    func health() async -> HealthResult
    func lookupPermalink(mediaId: String) async -> String?
}

extension ProviderAdapter {
    func lookupPermalink(mediaId: String) async -> String? { nil }
}

enum AdapterRegistry {
    static var useMocks = ProcessInfo.processInfo.arguments.contains("-mockProviders")
        || ProcessInfo.processInfo.environment["BLATHER_MOCK_PROVIDERS"] == "1"

    static var mockFail: Set<Network> = {
        let raw = ProcessInfo.processInfo.environment["BLATHER_MOCK_FAIL"] ?? "instagram"
        return Set(raw.split(separator: ",").compactMap { Network(rawValue: String($0)) })
    }()

    static var mockFailAccountIds: Set<String> = {
        let raw = ProcessInfo.processInfo.environment["BLATHER_MOCK_FAIL_ACCOUNTS"] ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }()

    static func adapter(for account: ConnectionInfo, database: AppDatabase) -> any ProviderAdapter {
        adapter(for: account.id, network: account.network, database: database)
    }

    static func adapter(for accountId: String, network: Network, database: AppDatabase) -> any ProviderAdapter {
        if useMocks { return MockAdapter(accountId: accountId, network: network) }
        switch network {
        case .x: return XAdapter(accountId: accountId, database: database)
        case .bluesky: return BlueskyAdapter(accountId: accountId, database: database)
        case .threads: return ThreadsAdapter(accountId: accountId, database: database)
        case .instagram: return InstagramAdapter(accountId: accountId, database: database)
        case .linkedin: return LinkedInAdapter(accountId: accountId, database: database)
        }
    }
}

struct MockAdapter: ProviderAdapter {
    let accountId: String
    let network: Network

    func isConnected() -> Bool { true }

    func refreshIfNeeded() async throws {}

    func validate(content: ResolvedContent) throws {
        try ContentValidation.validate(network, content: content)
    }

    func publish(content: ResolvedContent, context: any PublishContext) async throws -> PublishResult {
        try ContentValidation.validate(network, content: content)
        if AdapterRegistry.mockFail.contains(network) || AdapterRegistry.mockFailAccountIds.contains(accountId) {
            throw ProviderError(network: network, "mock \(network.rawValue) publish failure")
        }
        let id = "mock-\(accountId)-\(Int(Date().timeIntervalSince1970 * 1000))"
        return PublishResult(
            providerPostId: id,
            providerPostUrl: "https://mock.local/\(network.rawValue)/\(id)"
        )
    }

    func normalizeError(_ error: Error) -> String {
        if let provider = error as? ProviderError {
            return Redaction.redact(provider.message)
        }
        return Redaction.redact("\(network.rawValue): \(error.localizedDescription)")
    }

    func health() async -> HealthResult {
        HealthResult(ok: true, accountLabel: "@mock-\(network.rawValue)", meta: [:], error: nil)
    }
}

struct NullPublishContext: PublishContext {
    var attemptId: String
    func stageMedia(mediaId: String, attemptId: String?) async throws -> (key: String, url: String) {
        (key: "local/\(mediaId)", url: "https://mock.local/media/\(mediaId)")
    }

    func removeStaged(key: String) async {}
}

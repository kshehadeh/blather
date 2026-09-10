import Foundation

enum Network: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case x
    case bluesky
    case threads
    case instagram
    case linkedin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .x: "X"
        case .bluesky: "Bluesky"
        case .threads: "Threads"
        case .instagram: "Instagram"
        case .linkedin: "LinkedIn"
        }
    }

    var imageName: String {
        switch self {
        case .x: "NetworkX"
        case .bluesky: "NetworkBluesky"
        case .threads: "NetworkThreads"
        case .instagram: "NetworkInstagram"
        case .linkedin: "NetworkLinkedIn"
        }
    }

    func providerAccountId(in meta: [String: String]) -> String? {
        switch self {
        case .x, .threads, .linkedin: meta["userId"]
        case .instagram: meta["igUserId"]
        case .bluesky: meta["did"]
        }
    }
}

enum MediaKind: String, Codable, Hashable, Sendable {
    case image
    case video
}

struct MediaItem: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var kind: MediaKind
    var mimeType: String
    var name: String
    var size: Int
    var width: Int?
    var height: Int?
    var durationSeconds: Double?
    var createdAt: String
}

struct NetworkOverride: Hashable, Codable, Sendable {
    var text: String?
    var mediaIds: [String]?
}

struct Draft: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var text: String
    var mediaIds: [String]
    var accountIds: [String] = []
    var networks: [Network]
    var overrides: [Network: NetworkOverride]
    var createdAt: String
    var updatedAt: String
}

enum AttemptStatus: String, Codable, Hashable, Sendable {
    case pending
    case publishing
    case success
    case failed
}

struct PublishAttempt: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var draftId: String
    var network: Network
    var accountId: String? = nil
    var accountLabelSnapshot: String? = nil
    var status: AttemptStatus
    var providerPostId: String?
    var providerPostUrl: String?
    var error: String?
    var textSnapshot: String
    var createdAt: String
    var updatedAt: String
}

enum ConnectionState: String, Codable, Hashable, Sendable {
    case disconnected
    case connected
    case error
}

struct ConnectionInfo: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var network: Network
    var providerAccountId: String? = nil
    var state: ConnectionState
    var accountLabel: String?
    var meta: [String: String]
    var error: String?
    var credentialRef: String?
    var isRemoved: Bool = false

    var canPublish: Bool {
        !isRemoved && state == .connected
    }
}

struct ProviderCapabilities: Hashable, Sendable {
    var network: Network
    var maxChars: Int
    var maxImages: Int
    var maxImageBytes: Int?
    var autoOptimizeImages: Bool
    var allowsVideo: Bool
    var allowsMixedMedia: Bool
    var allowsCarousel: Bool
    var requiresMedia: Bool
    var notes: [String]
}

struct R2SettingsView: Hashable, Sendable {
    var configured: Bool
    var accountId: String?
    var bucket: String?
    var publicUrlStrategy: String?
    var publicBaseUrl: String?
    var hasCredentials: Bool
    var jurisdiction: String? = nil
}

struct ResolvedContent: Hashable, Sendable {
    var text: String
    var media: [MediaItem]
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable, Sendable {
    case compose
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compose: "Compose"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .compose: "square.and.pencil"
        case .history: "clock"
        }
    }
}

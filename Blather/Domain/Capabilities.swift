import Foundation

enum Capabilities {
    static let all: [Network: ProviderCapabilities] = [
        .x: ProviderCapabilities(
            network: .x,
            maxChars: 280,
            maxImages: 4,
            maxImageBytes: nil,
            autoOptimizeImages: false,
            allowsVideo: true,
            allowsMixedMedia: false,
            allowsCarousel: false,
            requiresMedia: false,
            notes: [
                "Free X API tier is heavily rate-limited and cannot upload media on some plans.",
                "OAuth 2.0 PKCE app with Read and Write permissions required.",
            ]
        ),
        .bluesky: ProviderCapabilities(
            network: .bluesky,
            maxChars: 300,
            maxImages: 4,
            maxImageBytes: 1_000_000,
            autoOptimizeImages: true,
            allowsVideo: true,
            allowsMixedMedia: false,
            allowsCarousel: false,
            requiresMedia: false,
            notes: [
                "Uses an app password, not your main password.",
                "Larger images are converted to a JPEG under the 1 MB limit before publishing.",
                "Video uploads are processed asynchronously.",
            ]
        ),
        .threads: ProviderCapabilities(
            network: .threads,
            maxChars: 500,
            maxImages: 20,
            maxImageBytes: nil,
            autoOptimizeImages: false,
            allowsVideo: true,
            allowsMixedMedia: true,
            allowsCarousel: true,
            requiresMedia: false,
            notes: [
                "Media must be reachable by Meta over HTTPS, so media is staged temporarily in Cloudflare R2.",
                "Requires a Meta developer app with the Threads API use case.",
            ]
        ),
        .instagram: ProviderCapabilities(
            network: .instagram,
            maxChars: 2200,
            maxImages: 10,
            maxImageBytes: nil,
            autoOptimizeImages: false,
            allowsVideo: true,
            allowsMixedMedia: false,
            allowsCarousel: true,
            requiresMedia: true,
            notes: [
                "Requires a professional (Business or Creator) Instagram account linked to a Facebook Page.",
                "Media must be reachable by Meta over HTTPS, so media is staged temporarily in Cloudflare R2.",
                "Personal Instagram accounts cannot be published to via the API.",
            ]
        ),
    ]

    static func capabilities(for network: Network) -> ProviderCapabilities {
        all[network]!
    }
}

enum MediaLimits {
    static let imageMimeTypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/gif",
    ]
    static let videoMimeTypes: Set<String> = [
        "video/mp4", "video/quicktime", "video/webm",
    ]
    static let imageMaxBytes = 10 * 1024 * 1024
    static let videoMaxBytes = 512 * 1024 * 1024
    static let videoMaxDurationSeconds: Double = 600
    static let uploadMaxBytes = 512 * 1024 * 1024
}

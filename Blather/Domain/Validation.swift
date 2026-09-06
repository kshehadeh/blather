import Foundation

struct ProviderError: Error, LocalizedError {
    var network: Network
    var message: String
    var retryable: Bool
    var status: Int?

    init(network: Network, _ message: String, retryable: Bool = false, status: Int? = nil) {
        self.network = network
        self.message = message
        self.retryable = retryable
        self.status = status
    }

    var errorDescription: String? { message }
}

enum ContentValidation {
    static func validate(_ network: Network, content: ResolvedContent) throws {
        let caps = Capabilities.capabilities(for: network)
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = content.media.filter { $0.kind == .image }
        let videos = content.media.filter { $0.kind == .video }

        if text.count > caps.maxChars {
            throw ProviderError(network: network, "\(caps.network.rawValue): text is \(text.count) characters (limit \(caps.maxChars))")
        }
        if caps.requiresMedia, content.media.isEmpty {
            throw ProviderError(network: network, "\(caps.network.rawValue): at least one image or video is required")
        }
        if text.isEmpty, content.media.isEmpty {
            throw ProviderError(network: network, "\(caps.network.rawValue): post has no text and no media")
        }
        if !images.isEmpty, !videos.isEmpty, !caps.allowsMixedMedia {
            throw ProviderError(network: network, "\(caps.network.rawValue): cannot mix images and video in one post")
        }
        if images.count > caps.maxImages {
            throw ProviderError(network: network, "\(caps.network.rawValue): \(images.count) images selected (limit \(caps.maxImages))")
        }
        if videos.count > 1 {
            throw ProviderError(network: network, "\(caps.network.rawValue): only one video per post")
        }
        if !videos.isEmpty, !caps.allowsVideo {
            throw ProviderError(network: network, "\(caps.network.rawValue): video is not supported")
        }

        for item in content.media {
            let mimeOk: Bool
            let maxBytes: Int
            if item.kind == .image {
                mimeOk = MediaLimits.imageMimeTypes.contains(item.mimeType)
                if caps.autoOptimizeImages {
                    maxBytes = MediaLimits.imageMaxBytes
                } else {
                    maxBytes = min(MediaLimits.imageMaxBytes, caps.maxImageBytes ?? MediaLimits.imageMaxBytes)
                }
            } else {
                mimeOk = MediaLimits.videoMimeTypes.contains(item.mimeType)
                maxBytes = MediaLimits.videoMaxBytes
            }
            if !mimeOk {
                throw ProviderError(network: network, "\(caps.network.rawValue): unsupported \(item.kind.rawValue) type \(item.mimeType)")
            }
            if item.size > maxBytes {
                let mb = Int((Double(maxBytes) / 1_000_000).rounded())
                throw ProviderError(network: network, "\(caps.network.rawValue): \(item.name) exceeds the \(mb)MB \(item.kind.rawValue) limit")
            }
            if item.kind == .video, let duration = item.durationSeconds, duration > MediaLimits.videoMaxDurationSeconds {
                throw ProviderError(network: network, "\(caps.network.rawValue): video is longer than \(Int(MediaLimits.videoMaxDurationSeconds))s")
            }
            if item.kind == .image, let width = item.width, let height = item.height, height > 0 {
                let ratio = Double(width) / Double(height)
                if ratio < 1.0 / 20.0 || ratio > 20 {
                    throw ProviderError(network: network, "\(caps.network.rawValue): image \(item.name) has an unsupported aspect ratio")
                }
            }
        }
    }
}

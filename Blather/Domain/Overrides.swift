import Foundation

enum Overrides {
    static func resolveContent(
        text: String,
        mediaIds: [String],
        overrides: [Network: NetworkOverride],
        network: Network,
        mediaById: [String: MediaItem]
    ) -> ResolvedContent {
        let override = overrides[network]
        let resolvedText = override?.text ?? text
        let resolvedIds = override?.mediaIds ?? mediaIds
        let media = resolvedIds.compactMap { mediaById[$0] }
        return ResolvedContent(text: resolvedText, media: media)
    }
}

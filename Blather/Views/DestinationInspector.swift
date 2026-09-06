import SwiftUI

struct DestinationInspector: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let session = appModel.session
        let networks = session.networks.sorted { $0.title < $1.title }

        Group {
            if networks.isEmpty {
                ContentUnavailableView(
                    "No destinations",
                    systemImage: "plus.rectangle.on.rectangle",
                    description: Text("Select one or more destinations to preview your post.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Per destination")
                            .font(.headline)
                            .padding(.bottom, 4)
                        ForEach(networks) { network in
                            DestinationPreviewCard(network: network)
                        }
                    }
                    .padding(16)
                }
                .scrollEdgeEffectStyleSoftIfAvailable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Preview")
    }
}

private struct DestinationPreviewCard: View {
    @Environment(AppModel.self) private var appModel
    let network: Network

    var body: some View {
        let caps = Capabilities.capabilities(for: network)
        let resolved = appModel.session.resolvedContent(for: network)
        let warnings = appModel.session.warnings(for: network)
        let overLimit = resolved.text.count > caps.maxChars

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(network.title, systemImage: network.systemImage)
                    .font(.headline)
                Spacer()
                Text("\(resolved.text.count)/\(caps.maxChars)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(overLimit ? Color.red : Color.secondary)
            }
            Text(resolved.text.isEmpty ? "No text yet." : resolved.text)
                .font(.body)
                .foregroundStyle(resolved.text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
            if !resolved.media.isEmpty {
                HStack(spacing: 6) {
                    ForEach(resolved.media) { item in
                        Label(
                            item.kind == .image ? "Image" : "Video",
                            systemImage: item.kind == .image ? "photo" : "video"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

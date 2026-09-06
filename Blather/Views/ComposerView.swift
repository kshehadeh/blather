import SwiftUI

struct ComposerView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var session = appModel.session

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                postEditor
                mediaSection
                destinations
                if !session.networks.isEmpty {
                    overrides
                }
                actions
                if let message = appModel.statusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                if !session.lastAttempts.isEmpty {
                    publishResults
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyleSoftIfAvailable()
        .background(.background)
        .dropDestination(for: URL.self) { urls, _ in
            appModel.addMedia(urls: urls)
            return true
        }
        .onPasteCommand(of: [.fileURL, .image]) { _ in
            appModel.pasteMedia()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compose")
                    .font(.largeTitle.weight(.semibold))
                Text("Write once, then tailor it for each destination if needed.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !appModel.drafts.isEmpty {
                Picker("Open Draft", selection: draftPickerBinding) {
                    Text("Open Draft").tag(String?.none)
                    ForEach(appModel.drafts) { draft in
                        Text(draftTitle(draft)).tag(Optional(draft.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }
        }
    }

    private var postEditor: some View {
        @Bindable var session = appModel.session

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your post")
                    .font(.headline)
                Spacer()
                Text("\(session.text.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            TextEditor(text: $session.text)
                .font(.body)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Post text")
                .accessibilityIdentifier("post-text")
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        let session = appModel.session
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Media")
                    .font(.headline)
                Spacer()
                Button("Add…") {
                    appModel.chooseMedia()
                }
            }
            if session.media.isEmpty {
                Text("Drop files here, paste, or add images and video. They stay on this Mac until you publish.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(session.media.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        MediaThumb(item: item)
                        Text(item.name)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            appModel.moveMedia(index: index, by: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)
                        .help("Move up")
                        Button {
                            appModel.moveMedia(index: index, by: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == session.media.count - 1)
                        .help("Move down")
                        Button {
                            appModel.removeMedia(id: item.id)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .help("Remove")
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var destinations: some View {
        @Bindable var session = appModel.session

        return VStack(alignment: .leading, spacing: 8) {
            Text("Destinations")
                .font(.headline)
            Text("Select the networks where this post will be published.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Network.allCases) { network in
                    Toggle(isOn: networkBinding(network)) {
                        Label(network.title, systemImage: network.systemImage)
                    }
                    .toggleStyle(.button)
                    .accessibilityIdentifier("destination-\(network.rawValue)")
                }
            }
        }
    }

    private var overrides: some View {
        @Bindable var session = appModel.session

        return VStack(alignment: .leading, spacing: 12) {
            Text("Destination overrides")
                .font(.headline)
            Text("Optional copy changes apply only to the chosen network.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(Array(session.networks).sorted { $0.title < $1.title }) { network in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(network.title) override")
                        .font(.subheadline.weight(.medium))
                    TextField(
                        "Override text, leave empty to inherit",
                        text: overrideBinding(network),
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Save Draft") {
                appModel.saveDraft()
            }
            Button("Publish") {
                appModel.publish()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(appModel.session.networks.isEmpty)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("publish")
            Button("Discard", role: .destructive) {
                appModel.confirmDiscard = true
            }
        }
        .controlSize(.large)
        .padding(.top, 4)
    }

    private var publishResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Publish results")
                .font(.headline)
                .accessibilityIdentifier("publish-results")
            ForEach(appModel.session.lastAttempts) { attempt in
                HStack {
                    StatusBadge(status: attempt.status)
                    Text(attempt.network.title)
                    if let error = attempt.error {
                        Text(error)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
    }

    private var draftPickerBinding: Binding<String?> {
        Binding(
            get: { appModel.session.draftId },
            set: { id in
                guard let id, let draft = appModel.drafts.first(where: { $0.id == id }) else { return }
                appModel.openDraft(draft)
            }
        )
    }

    private func networkBinding(_ network: Network) -> Binding<Bool> {
        Binding(
            get: { appModel.session.networks.contains(network) },
            set: { isOn in
                if isOn {
                    appModel.session.networks.insert(network)
                } else {
                    appModel.session.networks.remove(network)
                    appModel.session.overrides[network] = nil
                }
            }
        )
    }

    private func overrideBinding(_ network: Network) -> Binding<String> {
        Binding(
            get: { appModel.session.overrides[network]?.text ?? "" },
            set: { value in
                if value.isEmpty {
                    var override = appModel.session.overrides[network]
                    override?.text = nil
                    if override?.mediaIds == nil {
                        appModel.session.overrides[network] = nil
                    } else {
                        appModel.session.overrides[network] = override
                    }
                } else {
                    var override = appModel.session.overrides[network] ?? NetworkOverride()
                    override.text = value
                    appModel.session.overrides[network] = override
                }
            }
        )
    }

    private func draftTitle(_ draft: Draft) -> String {
        let snippet = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = snippet.isEmpty ? "(no text)" : String(snippet.prefix(40))
        return prefix
    }
}

struct MediaThumb: View {
    @Environment(AppModel.self) private var appModel
    let item: MediaItem

    var body: some View {
        Group {
            if let path = try? appModel.database.media.pathOf(item.id),
               let image = MediaStore.thumbnail(for: item, relativePath: path)
            {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.kind == .image ? "photo" : "video")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct StatusBadge: View {
    let status: AttemptStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch status {
        case .success: Color.green.opacity(0.2)
        case .failed: Color.red.opacity(0.2)
        case .publishing: Color.orange.opacity(0.2)
        case .pending: Color.secondary.opacity(0.15)
        }
    }

    private var foreground: Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .publishing: .orange
        case .pending: .secondary
        }
    }
}

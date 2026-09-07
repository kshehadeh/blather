import SwiftUI

struct PublishProgressSheet: View {
    @Bindable var progress: PublishProgress
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.title)
                    .font(.title3.weight(.semibold))
                Text(progress.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("publish-progress")

            if !progress.items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(progress.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        PublishProgressRow(item: item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack {
                Spacer()
                Button("Done") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!progress.isFinished)
                .accessibilityIdentifier("publish-progress-done")
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 420)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(!progress.isFinished)
        .presentationSizing(.fitted)
    }
}

private struct PublishProgressRow: View {
    let item: PublishProgressItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NetworkIcon(network: item.network)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.network.title)
                    .font(.body.weight(.medium))
                if let label = item.accountLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = item.error, item.status == .failed {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            statusGlyph
                .frame(width: 18, height: 18)
                .padding(.top, 2)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("publish-progress-\(item.network.rawValue)")
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch item.status {
        case .pending, .publishing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .imageScale(.large)
        }
    }

    private var accessibilityLabel: String {
        var parts = [item.network.title]
        if let label = item.accountLabel {
            parts.append(label)
        }
        switch item.status {
        case .pending, .publishing:
            parts.append("publishing")
        case .success:
            parts.append("published")
        case .failed:
            parts.append("failed")
            if let error = item.error {
                parts.append(error)
            }
        }
        return parts.joined(separator: ", ")
    }
}

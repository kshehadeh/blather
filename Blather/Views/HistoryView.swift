import AppKit
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.history.isEmpty {
                ContentUnavailableView(
                    "Nothing published yet",
                    systemImage: "clock",
                    description: Text("Publishing activity will appear here after your first post.")
                )
            } else {
                List(appModel.history) { attempt in
                    HistoryRow(attempt: attempt)
                }
                .listStyle(.inset)
                .accessibilityIdentifier("history-list")
                .scrollEdgeEffectStyleSoftIfAvailable()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            appModel.backfillHistoryPermalinks()
        }
    }
}

private struct HistoryRow: View {
    let attempt: PublishAttempt

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            StatusBadge(status: attempt.status)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    NetworkIcon(network: attempt.network)
                    Text(attempt.network.title)
                        .font(.headline)
                }
                if !attempt.textSnapshot.isEmpty {
                    Text(attempt.textSnapshot)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if let error = attempt.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            if let urlString = attempt.providerPostUrl, let url = URL(string: urlString) {
                Button("View post") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
            }
            if attempt.status == .failed {
                Button("Retry") {
                    AppModel.shared.retryAttempt(id: attempt.id)
                }
                .accessibilityIdentifier("retry-\(attempt.network.rawValue)")
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let date = ISO8601DateFormatter().date(from: attempt.createdAt) {
            return formatter.string(from: date)
        }
        return attempt.createdAt
    }
}

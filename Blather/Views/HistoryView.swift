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
    @Environment(AppModel.self) private var appModel
    let attempt: PublishAttempt

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            StatusBadge(status: attempt.status)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    NetworkIcon(network: attempt.network)
                    Text(attempt.network.title)
                        .font(.headline)
                    if let label = attempt.accountLabelSnapshot {
                        Text(label)
                            .foregroundStyle(.secondary)
                    }
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
                    appModel.retryAttempt(id: attempt.id)
                }
                .disabled(appModel.isBusy || !canRetry)
                .accessibilityIdentifier("retry-\(attempt.accountId ?? attempt.network.rawValue)")
                .help(canRetry ? "Retry this account" : "Reconnect the original account to retry")
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

    private var canRetry: Bool {
        guard let accountId = attempt.accountId,
              let account = appModel.connection(accountId: accountId)
        else { return false }
        return account.canPublish
    }
}

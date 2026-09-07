import Foundation
import Observation

struct PublishProgressItem: Identifiable, Hashable, Sendable {
    var id: String { accountId }
    var accountId: String
    var network: Network
    var accountLabel: String?
    var status: AttemptStatus
    var error: String?
}

@MainActor
@Observable
final class PublishProgress: Identifiable {
    let id = UUID()
    var items: [PublishProgressItem]
    var isFinished = false
    var overallError: String?

    init(accounts: [ConnectionInfo]) {
        items = accounts.map { account in
            PublishProgressItem(
                accountId: account.id,
                network: account.network,
                accountLabel: account.accountLabel,
                status: .publishing,
                error: nil
            )
        }
    }

    var title: String {
        if !isFinished { return "Publishing" }
        if items.isEmpty { return "Publish failed" }
        let failed = items.filter { $0.status == .failed }.count
        if failed == 0, overallError == nil { return "Published" }
        if failed == items.count { return "Publish failed" }
        return "Published with errors"
    }

    var subtitle: String {
        if let overallError { return overallError }
        let total = items.count
        if !isFinished {
            return total == 1 ? "Posting to 1 account…" : "Posting to \(total) accounts…"
        }
        let failed = items.filter { $0.status == .failed }.count
        let succeeded = total - failed
        if failed == 0 {
            return succeeded == 1 ? "Posted to 1 account." : "Posted to \(succeeded) accounts."
        }
        if succeeded == 0 {
            return "Could not post to any account."
        }
        return "\(succeeded) succeeded, \(failed) failed."
    }

    func update(_ attempt: PublishAttempt) {
        let index = attempt.accountId.flatMap { accountId in
            items.firstIndex { $0.accountId == accountId }
        } ?? items.firstIndex { $0.network == attempt.network }
        guard let index else { return }
        items[index].status = attempt.status
        items[index].error = attempt.error
    }

    func finish() {
        isFinished = true
    }

    func fail(_ message: String) {
        overallError = message
        isFinished = true
        for index in items.indices where items[index].status == .pending || items[index].status == .publishing {
            items[index].status = .failed
            if items[index].error == nil {
                items[index].error = message
            }
        }
    }
}

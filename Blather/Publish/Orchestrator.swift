import Foundation

enum PublishOrchestrator {
    static let concurrency = 3

    static func publishDraft(
        id draftId: String,
        database: AppDatabase,
        onUpdate: (@MainActor @Sendable (PublishAttempt) -> Void)? = nil
    ) async throws -> [PublishAttempt] {
        guard let draft = try database.drafts.get(draftId) else {
            throw PublishError.draftNotFound
        }
        if draft.accountIds.isEmpty {
            throw PublishError.noAccounts
        }
        let mediaItems = try database.media.byIds(allMediaIds(draft))
        let mediaById = Dictionary(uniqueKeysWithValues: mediaItems.map { ($0.id, $0) })
        let accounts = try draft.accountIds.compactMap { try database.connections.get($0) }
        guard accounts.count == draft.accountIds.count else {
            throw PublishError.accountUnavailable
        }
        let accountsById = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let created = try accounts.map { account in
            try database.attempts.create(
                draftId: draftId,
                network: account.network,
                accountId: account.id,
                accountLabelSnapshot: account.accountLabel,
                textSnapshot: draft.text
            )
        }
        for attempt in created {
            if let onUpdate {
                await onUpdate(attempt)
            }
        }
        return await withTaskGroup(of: (Int, PublishAttempt).self) { group in
            var nextIndex = 0
            while nextIndex < min(concurrency, created.count) {
                let index = nextIndex
                let attempt = created[index]
                group.addTask {
                    let result = await runAttempt(
                        attempt,
                        account: accountsById[attempt.accountId ?? ""],
                        draft: draft,
                        mediaById: mediaById,
                        database: database,
                        onUpdate: onUpdate
                    )
                    return (index, result)
                }
                nextIndex += 1
            }
            var results = [PublishAttempt?](repeating: nil, count: created.count)
            for await (index, result) in group {
                results[index] = result
                if nextIndex < created.count {
                    let newIndex = nextIndex
                    let attempt = created[newIndex]
                    group.addTask {
                        let result = await runAttempt(
                            attempt,
                            account: accountsById[attempt.accountId ?? ""],
                            draft: draft,
                            mediaById: mediaById,
                            database: database,
                            onUpdate: onUpdate
                        )
                        return (newIndex, result)
                    }
                    nextIndex += 1
                }
            }
            return results.compactMap { $0 }
        }
    }

    static func retryAttempt(
        id attemptId: String,
        database: AppDatabase,
        onUpdate: (@MainActor @Sendable (PublishAttempt) -> Void)? = nil
    ) async throws -> PublishAttempt {
        guard let attempt = try database.attempts.get(attemptId) else {
            throw PublishError.attemptNotFound
        }
        guard attempt.status == .failed else {
            throw PublishError.retryOnlyFailed
        }
        guard let draft = try database.drafts.get(attempt.draftId) else {
            throw PublishError.draftNotFound
        }
        guard let accountId = attempt.accountId,
              let account = try database.connections.get(accountId),
              account.canPublish
        else {
            throw PublishError.accountUnavailable
        }
        let mediaItems = try database.media.byIds(allMediaIds(draft))
        let mediaById = Dictionary(uniqueKeysWithValues: mediaItems.map { ($0.id, $0) })
        return await runAttempt(
            attempt,
            account: account,
            draft: draft,
            mediaById: mediaById,
            database: database,
            onUpdate: onUpdate
        )
    }

    static func recoverInterrupted(database: AppDatabase) throws {
        let stuck = try database.attempts.stuckPublishing()
        for attempt in stuck {
            try database.attempts.setStatus(
                id: attempt.id,
                status: .failed,
                error: "interrupted: the app stopped while publishing; review and retry if needed"
            )
        }
    }

    /// One Graph GET per successful Threads/Instagram row that has an id but no URL.
    /// Skips disconnected accounts. Never fails a stored success if the lookup misses.
    @discardableResult
    static func backfillMissingPostURLs(database: AppDatabase) async -> Bool {
        let attempts = (try? database.attempts.list()) ?? []
        var changed = false
        for attempt in attempts where needsPermalinkBackfill(attempt) {
            guard let postId = attempt.providerPostId else { continue }
            guard let accountId = attempt.accountId,
                  let account = try? database.connections.get(accountId),
                  account.canPublish
            else { continue }
            let adapter = AdapterRegistry.adapter(for: account, database: database)
            guard adapter.isConnected() else { continue }
            guard let permalink = await adapter.lookupPermalink(mediaId: postId), !permalink.isEmpty else {
                continue
            }
            try? database.attempts.setStatus(
                id: attempt.id,
                status: .success,
                providerPostUrl: permalink
            )
            changed = true
        }
        return changed
    }

    private static func needsPermalinkBackfill(_ attempt: PublishAttempt) -> Bool {
        guard attempt.status == .success else { return false }
        guard attempt.network == .threads || attempt.network == .instagram else { return false }
        guard let postId = attempt.providerPostId, !postId.isEmpty else { return false }
        if let url = attempt.providerPostUrl, !url.isEmpty { return false }
        return true
    }

    private static func runAttempt(
        _ attempt: PublishAttempt,
        account: ConnectionInfo?,
        draft: Draft,
        mediaById: [String: MediaItem],
        database: AppDatabase,
        onUpdate: (@MainActor @Sendable (PublishAttempt) -> Void)? = nil
    ) async -> PublishAttempt {
        try? database.attempts.setStatus(id: attempt.id, status: .publishing)
        await report(attempt.id, database: database, fallback: attempt, onUpdate: onUpdate)
        guard let account, account.canPublish else {
            try? database.attempts.setStatus(
                id: attempt.id,
                status: .failed,
                error: "account unavailable: reconnect or select another account"
            )
            return await report(attempt.id, database: database, fallback: attempt, onUpdate: onUpdate)
        }
        let adapter = AdapterRegistry.adapter(for: account, database: database)
        do {
            let content = Overrides.resolveContent(
                text: draft.text,
                mediaIds: draft.mediaIds,
                overrides: draft.overrides,
                network: attempt.network,
                mediaById: mediaById
            )
            try adapter.validate(content: content)
            let context: any PublishContext = AdapterRegistry.useMocks
                ? NullPublishContext(attemptId: attempt.id)
                : R2PublishContext(attemptId: attempt.id, database: database)
            let result = try await adapter.publish(content: content, context: context)
            try database.attempts.setStatus(
                id: attempt.id,
                status: .success,
                providerPostId: result.providerPostId,
                providerPostUrl: result.providerPostUrl
            )
        } catch {
            try? database.attempts.setStatus(
                id: attempt.id,
                status: .failed,
                error: adapter.normalizeError(error)
            )
        }
        return await report(attempt.id, database: database, fallback: attempt, onUpdate: onUpdate)
    }

    @discardableResult
    private static func report(
        _ id: String,
        database: AppDatabase,
        fallback: PublishAttempt,
        onUpdate: (@MainActor @Sendable (PublishAttempt) -> Void)?
    ) async -> PublishAttempt {
        let current = (try? database.attempts.get(id)) ?? fallback
        if let onUpdate {
            await onUpdate(current)
        }
        return current
    }

    private static func allMediaIds(_ draft: Draft) -> [String] {
        var ids = Set(draft.mediaIds)
        for override in draft.overrides.values {
            for id in override.mediaIds ?? [] {
                ids.insert(id)
            }
        }
        return Array(ids)
    }
}

enum PublishError: Error, LocalizedError, Equatable {
    case draftNotFound
    case attemptNotFound
    case noAccounts
    case accountUnavailable
    case retryOnlyFailed

    var errorDescription: String? {
        switch self {
        case .draftNotFound: "Draft not found"
        case .attemptNotFound: "Attempt not found"
        case .noAccounts: "No accounts selected"
        case .accountUnavailable: "The selected account is unavailable. Reconnect it or select another account."
        case .retryOnlyFailed: "Only failed attempts can be retried"
        }
    }
}

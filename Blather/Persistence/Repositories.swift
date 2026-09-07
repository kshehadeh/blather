import Foundation
import GRDB

struct DraftsRepository: Sendable {
    let dbQueue: DatabaseQueue

    func create(
        text: String,
        mediaIds: [String],
        accountIds: [String],
        networks: [Network],
        overrides: [Network: NetworkOverride]
    ) throws -> Draft {
        let ts = Time.now()
        let id = Time.newId()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO drafts (id, text, media_ids, account_ids, networks, overrides, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    id,
                    text,
                    JSONCodec.encode(mediaIds),
                    JSONCodec.encode(accountIds),
                    JSONCodec.encode(networks.map(\.rawValue)),
                    JSONCodec.encodeOverrides(overrides),
                    ts,
                    ts,
                ]
            )
        }
        return Draft(
            id: id,
            text: text,
            mediaIds: mediaIds,
            accountIds: accountIds,
            networks: networks,
            overrides: overrides,
            createdAt: ts,
            updatedAt: ts
        )
    }

    func update(
        id: String,
        text: String? = nil,
        mediaIds: [String]? = nil,
        accountIds: [String]? = nil,
        networks: [Network]? = nil,
        overrides: [Network: NetworkOverride]? = nil
    ) throws -> Draft? {
        guard var existing = try get(id) else { return nil }
        if let text { existing.text = text }
        if let mediaIds { existing.mediaIds = mediaIds }
        if let accountIds { existing.accountIds = accountIds }
        if let networks { existing.networks = networks }
        if let overrides { existing.overrides = overrides }
        existing.updatedAt = Time.now()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE drafts
                SET text = ?, media_ids = ?, account_ids = ?, networks = ?, overrides = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    existing.text,
                    JSONCodec.encode(existing.mediaIds),
                    JSONCodec.encode(existing.accountIds),
                    JSONCodec.encode(existing.networks.map(\.rawValue)),
                    JSONCodec.encodeOverrides(existing.overrides),
                    existing.updatedAt,
                    id,
                ]
            )
        }
        return existing
    }

    func get(_ id: String) throws -> Draft? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM drafts WHERE id = ?", arguments: [id]).map(Self.draft(from:))
        }
    }

    func list() throws -> [Draft] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM drafts ORDER BY updated_at DESC").map(Self.draft(from:))
        }
    }

    func remove(_ id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM drafts WHERE id = ?", arguments: [id])
        }
    }

    private static func draft(from row: Row) -> Draft {
        let networkIds: [String] = JSONCodec.decode([String].self, from: row["networks"])
        return Draft(
            id: row["id"],
            text: row["text"],
            mediaIds: JSONCodec.decode([String].self, from: row["media_ids"]),
            accountIds: JSONCodec.decode([String].self, from: row["account_ids"]),
            networks: networkIds.compactMap(Network.init(rawValue:)),
            overrides: JSONCodec.decodeOverrides(row["overrides"]),
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}

struct AttemptsRepository: Sendable {
    let dbQueue: DatabaseQueue

    func create(
        draftId: String,
        network: Network,
        accountId: String,
        accountLabelSnapshot: String? = nil,
        textSnapshot: String = ""
    ) throws -> PublishAttempt {
        let ts = Time.now()
        let id = Time.newId()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO publish_attempts
                  (id, draft_id, network, account_id, account_label_snapshot, status, text_snapshot, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?)
                """,
                arguments: [
                    id,
                    draftId,
                    network.rawValue,
                    accountId,
                    accountLabelSnapshot,
                    textSnapshot,
                    ts,
                    ts,
                ]
            )
        }
        return try get(id)!
    }

    func setStatus(
        id: String,
        status: AttemptStatus,
        providerPostId: String? = nil,
        providerPostUrl: String? = nil,
        error: String? = nil
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE publish_attempts
                   SET status = ?,
                       provider_post_id = COALESCE(?, provider_post_id),
                       provider_post_url = COALESCE(?, provider_post_url),
                       error = ?,
                       updated_at = ?
                 WHERE id = ?
                """,
                arguments: [status.rawValue, providerPostId, providerPostUrl, error, Time.now(), id]
            )
        }
    }

    func get(_ id: String) throws -> PublishAttempt? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM publish_attempts WHERE id = ?", arguments: [id])
                .map(Self.attempt(from:))
        }
    }

    func list(limit: Int = 200) throws -> [PublishAttempt] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM publish_attempts ORDER BY created_at DESC LIMIT ?",
                arguments: [limit]
            ).map(Self.attempt(from:))
        }
    }

    func forDraft(_ draftId: String) throws -> [PublishAttempt] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM publish_attempts WHERE draft_id = ? ORDER BY created_at DESC",
                arguments: [draftId]
            ).map(Self.attempt(from:))
        }
    }

    func stuckPublishing() throws -> [PublishAttempt] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM publish_attempts WHERE status = 'publishing'")
                .map(Self.attempt(from:))
        }
    }

    private static func attempt(from row: Row) -> PublishAttempt {
        PublishAttempt(
            id: row["id"],
            draftId: row["draft_id"],
            network: Network(rawValue: row["network"]) ?? .x,
            accountId: row["account_id"],
            accountLabelSnapshot: row["account_label_snapshot"],
            status: AttemptStatus(rawValue: row["status"]) ?? .pending,
            providerPostId: row["provider_post_id"],
            providerPostUrl: row["provider_post_url"],
            error: row["error"],
            textSnapshot: row["text_snapshot"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}

struct ConnectionsRepository: Sendable {
    let dbQueue: DatabaseQueue

    func upsert(
        accountId: String,
        network: Network,
        providerAccountId: String? = nil,
        state: ConnectionState,
        credentialRef: String? = nil,
        accountLabel: String? = nil,
        meta: [String: String] = [:],
        error: String? = nil,
        isRemoved: Bool = false
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO social_accounts
                  (id, network, provider_account_id, state, credential_ref, account_label, meta, error, is_removed, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  network = excluded.network,
                  provider_account_id = COALESCE(excluded.provider_account_id, social_accounts.provider_account_id),
                  state = excluded.state,
                  credential_ref = COALESCE(excluded.credential_ref, social_accounts.credential_ref),
                  account_label = COALESCE(excluded.account_label, social_accounts.account_label),
                  meta = excluded.meta,
                  error = excluded.error,
                  is_removed = excluded.is_removed,
                  updated_at = excluded.updated_at
                """,
                arguments: [
                    accountId,
                    network.rawValue,
                    providerAccountId,
                    state.rawValue,
                    credentialRef,
                    accountLabel,
                    JSONCodec.encode(meta),
                    error,
                    isRemoved,
                    Time.now(),
                ]
            )
        }
    }

    func get(_ accountId: String) throws -> ConnectionInfo? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM social_accounts WHERE id = ?",
                arguments: [accountId]
            ).map(Self.info(from:))
        }
    }

    func find(network: Network, providerAccountId: String) throws -> ConnectionInfo? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM social_accounts WHERE network = ? AND provider_account_id = ?",
                arguments: [network.rawValue, providerAccountId]
            ).map(Self.info(from:))
        }
    }

    func list(includeRemoved: Bool = false) throws -> [ConnectionInfo] {
        try dbQueue.read { db in
            let sql = includeRemoved
                ? "SELECT * FROM social_accounts ORDER BY network, account_label, updated_at"
                : "SELECT * FROM social_accounts WHERE is_removed = 0 ORDER BY network, account_label, updated_at"
            return try Row.fetchAll(db, sql: sql).map(Self.info(from:))
        }
    }

    func list(network: Network, includeRemoved: Bool = false) throws -> [ConnectionInfo] {
        try dbQueue.read { db in
            let removedClause = includeRemoved ? "" : "AND is_removed = 0"
            return try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM social_accounts
                WHERE network = ? \(removedClause)
                ORDER BY account_label, updated_at
                """,
                arguments: [network.rawValue]
            ).map(Self.info(from:))
        }
    }

    func clear(_ accountId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE social_accounts
                SET state = 'disconnected', credential_ref = NULL, error = NULL,
                    is_removed = 1, updated_at = ?
                WHERE id = ?
                """,
                arguments: [Time.now(), accountId]
            )
        }
    }

    private static func info(from row: Row) -> ConnectionInfo {
        ConnectionInfo(
            id: row["id"],
            network: Network(rawValue: row["network"]) ?? .x,
            providerAccountId: row["provider_account_id"],
            state: ConnectionState(rawValue: row["state"]) ?? .disconnected,
            accountLabel: row["account_label"],
            meta: JSONCodec.decode([String: String].self, from: row["meta"]),
            error: row["error"],
            credentialRef: row["credential_ref"],
            isRemoved: row["is_removed"]
        )
    }
}

struct MediaRepository: Sendable {
    let dbQueue: DatabaseQueue

    func create(
        kind: MediaKind,
        mimeType: String,
        name: String,
        size: Int,
        width: Int? = nil,
        height: Int? = nil,
        durationSeconds: Double? = nil,
        path: String
    ) throws -> MediaItem {
        let id = Time.newId()
        let ts = Time.now()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO media (id, kind, mime_type, name, size, width, height, duration_seconds, path, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [id, kind.rawValue, mimeType, name, size, width, height, durationSeconds, path, ts]
            )
        }
        return MediaItem(
            id: id,
            kind: kind,
            mimeType: mimeType,
            name: name,
            size: size,
            width: width,
            height: height,
            durationSeconds: durationSeconds,
            createdAt: ts
        )
    }

    func get(_ id: String) throws -> MediaItem? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM media WHERE id = ?", arguments: [id]).map(Self.item(from:))
        }
    }

    func pathOf(_ id: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT path FROM media WHERE id = ?", arguments: [id])
        }
    }

    func remove(_ id: String) throws -> String? {
        let path = try pathOf(id)
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM media WHERE id = ?", arguments: [id])
        }
        return path
    }

    func byIds(_ ids: [String]) throws -> [MediaItem] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM media WHERE id IN (\(placeholders))", arguments: StatementArguments(ids))
        }
        let map = Dictionary(uniqueKeysWithValues: rows.map { ($0["id"] as String, Self.item(from: $0)) })
        return ids.compactMap { map[$0] }
    }

    private static func item(from row: Row) -> MediaItem {
        MediaItem(
            id: row["id"],
            kind: MediaKind(rawValue: row["kind"]) ?? .image,
            mimeType: row["mime_type"],
            name: row["name"],
            size: row["size"],
            width: row["width"],
            height: row["height"],
            durationSeconds: row["duration_seconds"],
            createdAt: row["created_at"]
        )
    }
}

struct OAuthStatesRepository: Sendable {
    let dbQueue: DatabaseQueue

    func create(provider: String, state: String, verifier: String?, ttlMs: Int = 10 * 60 * 1000) throws {
        let createdAt = Time.now()
        let expiresAt = Time.isoFormatter.string(from: Date().addingTimeInterval(Double(ttlMs) / 1000))
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO oauth_states (state, provider, verifier, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [state, provider, verifier, createdAt, expiresAt]
            )
        }
    }

    func consume(provider: String, state: String) throws -> String? {
        try dbQueue.write { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT verifier, expires_at FROM oauth_states WHERE state = ? AND provider = ?",
                arguments: [state, provider]
            )
            try db.execute(sql: "DELETE FROM oauth_states WHERE state = ?", arguments: [state])
            guard let row else { return nil }
            let expiresAt: String = row["expires_at"]
            if let date = Time.isoFormatter.date(from: expiresAt), date < Date() {
                return nil
            }
            return row["verifier"]
        }
    }
}

struct StoredR2Settings: Hashable, Sendable {
    var accountId: String
    var bucket: String
    var publicUrlStrategy: String
    var publicBaseUrl: String?
    var credentialRef: String?
    var jurisdiction: String? = nil
}

struct R2SettingsRepository: Sendable {
    let dbQueue: DatabaseQueue

    func get() throws -> StoredR2Settings? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM r2_settings WHERE id = 1") else { return nil }
            return StoredR2Settings(
                accountId: row["account_id"],
                bucket: row["bucket"],
                publicUrlStrategy: row["public_url_strategy"],
                publicBaseUrl: row["public_base_url"],
                credentialRef: row["credential_ref"],
                jurisdiction: row["jurisdiction"]
            )
        }
    }

    func view() throws -> R2SettingsView {
        guard let r2 = try get() else {
            return R2SettingsView(configured: false, hasCredentials: false)
        }
        let configured = !r2.accountId.isEmpty
            && r2.credentialRef != nil
            && (r2.publicUrlStrategy == "presigned" || r2.publicBaseUrl != nil)
        return R2SettingsView(
            configured: configured,
            accountId: r2.accountId.isEmpty ? nil : r2.accountId,
            bucket: r2.bucket,
            publicUrlStrategy: r2.publicUrlStrategy,
            publicBaseUrl: r2.publicBaseUrl,
            hasCredentials: r2.credentialRef != nil,
            jurisdiction: r2.jurisdiction
        )
    }

    func save(_ input: StoredR2Settings) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO r2_settings (id, account_id, bucket, public_url_strategy, public_base_url, credential_ref, jurisdiction, updated_at)
                VALUES (1, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  account_id = excluded.account_id,
                  bucket = excluded.bucket,
                  public_url_strategy = excluded.public_url_strategy,
                  public_base_url = excluded.public_base_url,
                  credential_ref = COALESCE(excluded.credential_ref, r2_settings.credential_ref),
                  jurisdiction = excluded.jurisdiction,
                  updated_at = excluded.updated_at
                """,
                arguments: [
                    input.accountId,
                    input.bucket,
                    input.publicUrlStrategy,
                    input.publicBaseUrl,
                    input.credentialRef,
                    input.jurisdiction,
                    Time.now(),
                ]
            )
        }
    }

    func clear() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM r2_settings WHERE id = 1")
        }
    }
}

struct StagedRepository: Sendable {
    let dbQueue: DatabaseQueue

    func add(attemptId: String?, bucket: String, key: String) throws -> String {
        let id = Time.newId()
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO staged_objects (id, attempt_id, bucket, key, created_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [id, attemptId, bucket, key, Time.now()]
            )
        }
        return id
    }

    func remove(_ id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM staged_objects WHERE id = ?", arguments: [id])
        }
    }

    func forAttempt(_ attemptId: String) throws -> [(id: String, bucket: String, key: String)] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, bucket, key FROM staged_objects WHERE attempt_id = ?",
                arguments: [attemptId]
            ).map { (id: $0["id"], bucket: $0["bucket"], key: $0["key"]) }
        }
    }

    func olderThan(_ cutoffIso: String) throws -> [(id: String, bucket: String, key: String)] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, bucket, key FROM staged_objects WHERE created_at < ?",
                arguments: [cutoffIso]
            ).map { (id: $0["id"], bucket: $0["bucket"], key: $0["key"]) }
        }
    }
}

extension AppDatabase {
    var drafts: DraftsRepository { DraftsRepository(dbQueue: dbQueue) }
    var attempts: AttemptsRepository { AttemptsRepository(dbQueue: dbQueue) }
    var connections: ConnectionsRepository { ConnectionsRepository(dbQueue: dbQueue) }
    var media: MediaRepository { MediaRepository(dbQueue: dbQueue) }
    var oauthStates: OAuthStatesRepository { OAuthStatesRepository(dbQueue: dbQueue) }
    var r2: R2SettingsRepository { R2SettingsRepository(dbQueue: dbQueue) }
    var staged: StagedRepository { StagedRepository(dbQueue: dbQueue) }
}

import Foundation
import GRDB

final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    static func openDefault() throws -> AppDatabase {
        try AppPaths.ensureDirectories()
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let dbQueue = try DatabaseQueue(path: AppPaths.databaseURL.path, configuration: config)
        let database = AppDatabase(dbQueue: dbQueue)
        try database.migrate()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: AppPaths.databaseURL.path
        )
        return database
    }

    static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        let database = AppDatabase(dbQueue: dbQueue)
        try database.migrate()
        return database
    }

    func migrate() throws {
        try dbQueue.write { db in
            try db.execute(sql: Schema.sql)
            try migrateMultipleAccounts(db)
            try migrateR2Jurisdiction(db)
            try migrateLegacyS3Settings(db)
        }
    }

    private func migrateMultipleAccounts(_ db: Database) throws {
        let migrationName = "multiple-accounts-v1"
        if try String.fetchOne(
            db,
            sql: "SELECT name FROM app_migrations WHERE name = ?",
            arguments: [migrationName]
        ) != nil {
            return
        }

        let draftColumns = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('drafts')")
        if !draftColumns.contains("account_ids") {
            try db.execute(sql: "ALTER TABLE drafts ADD COLUMN account_ids TEXT NOT NULL DEFAULT '[]'")
        }

        let attemptColumns = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('publish_attempts')")
        if !attemptColumns.contains("account_id") {
            try db.execute(sql: "ALTER TABLE publish_attempts ADD COLUMN account_id TEXT")
        }
        if !attemptColumns.contains("account_label_snapshot") {
            try db.execute(sql: "ALTER TABLE publish_attempts ADD COLUMN account_label_snapshot TEXT")
        }

        if try db.tableExists("connections") {
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM connections")
            for row in rows {
                let rawNetwork: String = row["network"]
                guard let network = Network(rawValue: rawNetwork) else { continue }
                let meta: [String: String] = JSONCodec.decode([String: String].self, from: row["meta"])
                let providerAccountId = network.providerAccountId(in: meta)
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO social_accounts
                      (id, network, provider_account_id, state, credential_ref, account_label, meta, error, is_removed, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
                    """,
                    arguments: [
                        "legacy-\(network.rawValue)",
                        rawNetwork,
                        providerAccountId,
                        row["state"] as String,
                        row["credential_ref"] as String?,
                        row["account_label"] as String?,
                        row["meta"] as String,
                        row["error"] as String?,
                        row["updated_at"] as String,
                    ]
                )
            }
        }

        let accountRows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, network, account_label, state, is_removed
            FROM social_accounts
            ORDER BY CASE state WHEN 'connected' THEN 0 ELSE 1 END, updated_at DESC
            """
        )
        var preferredAccountByNetwork: [String: String] = [:]
        var accountsByNetwork: [String: [(id: String, label: String?)]] = [:]
        for account in accountRows {
            let network: String = account["network"]
            let id: String = account["id"]
            let label: String? = account["account_label"]
            let isRemoved: Bool = account["is_removed"]
            accountsByNetwork[network, default: []].append((id, label))
            if !isRemoved, preferredAccountByNetwork[network] == nil {
                preferredAccountByNetwork[network] = id
            }
        }

        let drafts = try Row.fetchAll(
            db,
            sql: "SELECT id, networks FROM drafts WHERE account_ids = '[]' OR account_ids = ''"
        )
        for draft in drafts {
            let networkIds: [String] = JSONCodec.decode([String].self, from: draft["networks"])
            let accountIds = networkIds.compactMap { preferredAccountByNetwork[$0] }
            guard !accountIds.isEmpty else { continue }
            try db.execute(
                sql: "UPDATE drafts SET account_ids = ? WHERE id = ?",
                arguments: [JSONCodec.encode(accountIds), draft["id"] as String]
            )
        }

        let attempts = try Row.fetchAll(
            db,
            sql: "SELECT id, network FROM publish_attempts WHERE account_id IS NULL"
        )
        for attempt in attempts {
            let network: String = attempt["network"]
            guard let accounts = accountsByNetwork[network],
                  accounts.count == 1,
                  let account = accounts.first
            else { continue }
            try db.execute(
                sql: """
                UPDATE publish_attempts
                SET account_id = ?, account_label_snapshot = ?
                WHERE id = ?
                """,
                arguments: [
                    account.id,
                    account.label,
                    attempt["id"] as String,
                ]
            )
        }

        try db.execute(
            sql: "INSERT INTO app_migrations (name, applied_at) VALUES (?, ?)",
            arguments: [migrationName, Time.now()]
        )
    }

    private func migrateLegacyS3Settings(_ db: Database) throws {
        let table = try String.fetchOne(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 's3_settings'"
        )
        guard table != nil else { return }

        struct LegacyRow: FetchableRecord {
            var endpoint: String
            var bucket: String
            var publicUrlStrategy: String
            var publicBaseUrl: String?
            var credentialRef: String?
            var updatedAt: String

            init(row: Row) {
                endpoint = row["endpoint"]
                bucket = row["bucket"]
                publicUrlStrategy = row["public_url_strategy"]
                publicBaseUrl = row["public_base_url"]
                credentialRef = row["credential_ref"]
                updatedAt = row["updated_at"]
            }
        }

        guard let row = try LegacyRow.fetchOne(db, sql: """
            SELECT endpoint, bucket, public_url_strategy, public_base_url, credential_ref, updated_at
            FROM s3_settings WHERE id = 1
            """)
        else { return }

        let parsed = R2Endpoint.parse(accountId: row.endpoint)
        try db.execute(
            sql: """
            INSERT OR IGNORE INTO r2_settings
              (id, account_id, bucket, public_url_strategy, public_base_url, credential_ref, jurisdiction, updated_at)
            VALUES (1, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                parsed.accountId,
                row.bucket,
                row.publicUrlStrategy,
                row.publicBaseUrl,
                row.credentialRef,
                parsed.jurisdiction,
                row.updatedAt,
            ]
        )
    }

    private func migrateR2Jurisdiction(_ db: Database) throws {
        let names = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('r2_settings')")
        if !names.contains("jurisdiction") {
            try db.execute(sql: "ALTER TABLE r2_settings ADD COLUMN jurisdiction TEXT")
        }
    }
}

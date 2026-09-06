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
            try migrateR2Jurisdiction(db)
            try migrateLegacyS3Settings(db)
        }
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

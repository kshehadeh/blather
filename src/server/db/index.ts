import { chmodSync } from "node:fs";
import { dbPath } from "@/server/env";
import Database from "better-sqlite3";
import { SCHEMA_SQL } from "./schema";

export type DB = Database.Database;

let cached: DB | null = null;

export function getDb(): DB {
  if (cached) return cached;
  cached = openDb(dbPath());
  return cached;
}

export function openDb(path: string): DB {
  const db = new Database(path);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(SCHEMA_SQL);
  migrateLegacyS3Settings(db);
  if (path !== ":memory:") {
    try {
      chmodSync(path, 0o600);
    } catch {
      // best effort
    }
  }
  return db;
}

/** Preserve the existing staging configuration when upgrading to the R2-only model. */
function migrateLegacyS3Settings(db: DB): void {
  const legacyTable = db
    .prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 's3_settings'")
    .get();
  if (!legacyTable) return;

  const row = db
    .prepare(
      `SELECT endpoint, bucket, public_url_strategy, public_base_url, credential_ref, updated_at
       FROM s3_settings WHERE id = 1`,
    )
    .get() as
    | {
        endpoint: string;
        bucket: string;
        public_url_strategy: "public" | "presigned";
        public_base_url: string | null;
        credential_ref: string | null;
        updated_at: string;
      }
    | undefined;
  if (!row) return;

  const match = row.endpoint.match(/^https?:\/\/([^.]+)\.r2\.cloudflarestorage\.com\/?$/);
  db.prepare(
    `INSERT OR IGNORE INTO r2_settings
       (id, account_id, bucket, public_url_strategy, public_base_url, credential_ref, updated_at)
     VALUES (1, ?, ?, ?, ?, ?, ?)`,
  ).run(
    match?.[1] ?? "",
    row.bucket,
    row.public_url_strategy,
    row.public_base_url,
    row.credential_ref,
    row.updated_at,
  );
}

/** Test hook: replace the process-wide DB (e.g. with :memory:). */
export function __setDbForTests(db: DB | null): void {
  cached = db;
}

export function now(): string {
  return new Date().toISOString();
}

export function newId(): string {
  return crypto.randomUUID();
}

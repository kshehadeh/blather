import Foundation

enum Schema {
    static let sql = """
    CREATE TABLE IF NOT EXISTS app_migrations (
      name TEXT PRIMARY KEY,
      applied_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS drafts (
      id TEXT PRIMARY KEY,
      text TEXT NOT NULL DEFAULT '',
      media_ids TEXT NOT NULL DEFAULT '[]',
      account_ids TEXT NOT NULL DEFAULT '[]',
      networks TEXT NOT NULL DEFAULT '[]',
      overrides TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS publish_attempts (
      id TEXT PRIMARY KEY,
      draft_id TEXT NOT NULL,
      network TEXT NOT NULL,
      account_id TEXT,
      account_label_snapshot TEXT,
      status TEXT NOT NULL CHECK (status IN ('pending','publishing','success','failed')),
      provider_post_id TEXT,
      provider_post_url TEXT,
      error TEXT,
      text_snapshot TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_attempts_draft ON publish_attempts(draft_id);
    CREATE INDEX IF NOT EXISTS idx_attempts_created ON publish_attempts(created_at DESC);

    CREATE TABLE IF NOT EXISTS social_accounts (
      id TEXT PRIMARY KEY,
      network TEXT NOT NULL,
      provider_account_id TEXT,
      state TEXT NOT NULL CHECK (state IN ('disconnected','connected','error')),
      credential_ref TEXT,
      account_label TEXT,
      meta TEXT NOT NULL DEFAULT '{}',
      error TEXT,
      is_removed INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_social_accounts_identity
      ON social_accounts(network, provider_account_id);
    CREATE INDEX IF NOT EXISTS idx_social_accounts_network
      ON social_accounts(network, is_removed, updated_at);

    CREATE TABLE IF NOT EXISTS media (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK (kind IN ('image','video')),
      mime_type TEXT NOT NULL,
      name TEXT NOT NULL,
      size INTEGER NOT NULL,
      width INTEGER,
      height INTEGER,
      duration_seconds REAL,
      path TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS oauth_states (
      state TEXT PRIMARY KEY,
      provider TEXT NOT NULL,
      verifier TEXT,
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS r2_settings (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      account_id TEXT NOT NULL,
      bucket TEXT NOT NULL,
      public_url_strategy TEXT NOT NULL CHECK (public_url_strategy IN ('public','presigned')),
      public_base_url TEXT,
      credential_ref TEXT,
      jurisdiction TEXT,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS staged_objects (
      id TEXT PRIMARY KEY,
      attempt_id TEXT,
      bucket TEXT NOT NULL,
      key TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_staged_created ON staged_objects(created_at);
    """
}

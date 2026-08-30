import type {
  AttemptStatus,
  ConnectionInfo,
  ConnectionState,
  Draft,
  MediaItem,
  Network,
  NetworkOverride,
  PublishAttempt,
  R2SettingsView,
} from "@/lib/types";
import { type DB, getDb, newId, now } from "./index";

/* ---------------------------------- drafts --------------------------------- */

interface DraftRow {
  id: string;
  text: string;
  media_ids: string;
  networks: string;
  overrides: string;
  created_at: string;
  updated_at: string;
}

function draftFromRow(r: DraftRow): Draft {
  return {
    id: r.id,
    text: r.text,
    mediaIds: JSON.parse(r.media_ids) as string[],
    networks: JSON.parse(r.networks) as Network[],
    overrides: JSON.parse(r.overrides) as Partial<Record<Network, NetworkOverride>>,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export const draftsRepo = (db: DB = getDb()) => ({
  create(input: Omit<Draft, "id" | "createdAt" | "updatedAt">): Draft {
    const ts = now();
    const id = newId();
    db.prepare(
      `INSERT INTO drafts (id, text, media_ids, networks, overrides, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      input.text,
      JSON.stringify(input.mediaIds),
      JSON.stringify(input.networks),
      JSON.stringify(input.overrides ?? {}),
      ts,
      ts,
    );
    return { ...input, id, createdAt: ts, updatedAt: ts };
  },

  update(
    id: string,
    input: Partial<Pick<Draft, "text" | "mediaIds" | "networks" | "overrides">>,
  ): Draft | null {
    const existing = this.get(id);
    if (!existing) return null;
    const merged = { ...existing, ...input, updatedAt: now() };
    db.prepare(
      `UPDATE drafts SET text = ?, media_ids = ?, networks = ?, overrides = ?, updated_at = ? WHERE id = ?`,
    ).run(
      merged.text,
      JSON.stringify(merged.mediaIds),
      JSON.stringify(merged.networks),
      JSON.stringify(merged.overrides),
      merged.updatedAt,
      id,
    );
    return merged;
  },

  get(id: string): Draft | null {
    const row = db.prepare("SELECT * FROM drafts WHERE id = ?").get(id) as DraftRow | undefined;
    return row ? draftFromRow(row) : null;
  },

  list(): Draft[] {
    const rows = db.prepare("SELECT * FROM drafts ORDER BY updated_at DESC").all() as DraftRow[];
    return rows.map(draftFromRow);
  },

  remove(id: string): void {
    db.prepare("DELETE FROM drafts WHERE id = ?").run(id);
  },
});

/* ------------------------------ publish attempts --------------------------- */

interface AttemptRow {
  id: string;
  draft_id: string;
  network: string;
  status: AttemptStatus;
  provider_post_id: string | null;
  provider_post_url: string | null;
  error: string | null;
  text_snapshot: string;
  created_at: string;
  updated_at: string;
}

function attemptFromRow(r: AttemptRow): PublishAttempt {
  return {
    id: r.id,
    draftId: r.draft_id,
    network: r.network as Network,
    status: r.status,
    providerPostId: r.provider_post_id ?? undefined,
    providerPostUrl: r.provider_post_url ?? undefined,
    error: r.error ?? undefined,
    textSnapshot: r.text_snapshot,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

export const attemptsRepo = (db: DB = getDb()) => ({
  create(input: { draftId: string; network: Network; textSnapshot?: string }): PublishAttempt {
    const ts = now();
    const id = newId();
    db.prepare(
      `INSERT INTO publish_attempts
         (id, draft_id, network, status, text_snapshot, created_at, updated_at)
       VALUES (?, ?, ?, 'pending', ?, ?, ?)`,
    ).run(id, input.draftId, input.network, input.textSnapshot ?? "", ts, ts);
    return this.get(id) as PublishAttempt;
  },

  setStatus(
    id: string,
    status: AttemptStatus,
    extra: { providerPostId?: string; providerPostUrl?: string; error?: string } = {},
  ): void {
    db.prepare(
      `UPDATE publish_attempts
         SET status = ?, provider_post_id = COALESCE(?, provider_post_id),
             provider_post_url = COALESCE(?, provider_post_url),
             error = ?, updated_at = ?
       WHERE id = ?`,
    ).run(
      status,
      extra.providerPostId ?? null,
      extra.providerPostUrl ?? null,
      extra.error ?? null,
      now(),
      id,
    );
  },

  get(id: string): PublishAttempt | null {
    const row = db.prepare("SELECT * FROM publish_attempts WHERE id = ?").get(id) as
      | AttemptRow
      | undefined;
    return row ? attemptFromRow(row) : null;
  },

  list(limit = 200): PublishAttempt[] {
    const rows = db
      .prepare("SELECT * FROM publish_attempts ORDER BY created_at DESC LIMIT ?")
      .all(limit) as AttemptRow[];
    return rows.map(attemptFromRow);
  },

  forDraft(draftId: string): PublishAttempt[] {
    const rows = db
      .prepare("SELECT * FROM publish_attempts WHERE draft_id = ? ORDER BY created_at DESC")
      .all(draftId) as AttemptRow[];
    return rows.map(attemptFromRow);
  },

  /** Attempts interrupted mid-flight by a process exit. */
  stuckPublishing(): PublishAttempt[] {
    const rows = db
      .prepare("SELECT * FROM publish_attempts WHERE status = 'publishing'")
      .all() as AttemptRow[];
    return rows.map(attemptFromRow);
  },
});

/* -------------------------------- connections ------------------------------ */

interface ConnectionRow {
  network: string;
  state: ConnectionState;
  credential_ref: string | null;
  account_label: string | null;
  meta: string;
  error: string | null;
  updated_at: string;
}

export const connectionsRepo = (db: DB = getDb()) => ({
  upsert(input: {
    network: Network;
    state: ConnectionState;
    credentialRef?: string | null;
    accountLabel?: string | null;
    meta?: Record<string, string>;
    error?: string | null;
  }): void {
    db.prepare(
      `INSERT INTO connections (network, state, credential_ref, account_label, meta, error, updated_at)
       VALUES (@network, @state, @credential_ref, @account_label, @meta, @error, @updated_at)
       ON CONFLICT(network) DO UPDATE SET
         state = @state,
         credential_ref = COALESCE(@credential_ref, credential_ref),
         account_label = COALESCE(@account_label, account_label),
         meta = @meta,
         error = @error,
         updated_at = @updated_at`,
    ).run({
      network: input.network,
      state: input.state,
      credential_ref: input.credentialRef ?? null,
      account_label: input.accountLabel ?? null,
      meta: JSON.stringify(input.meta ?? {}),
      error: input.error ?? null,
      updated_at: now(),
    });
  },

  get(network: Network): ConnectionInfo & { credentialRef?: string } {
    const row = db.prepare("SELECT * FROM connections WHERE network = ?").get(network) as
      | ConnectionRow
      | undefined;
    if (!row) return { network, state: "disconnected" };
    return {
      network: row.network as Network,
      state: row.state,
      accountLabel: row.account_label ?? undefined,
      meta: JSON.parse(row.meta) as Record<string, string>,
      error: row.error ?? undefined,
      credentialRef: row.credential_ref ?? undefined,
    };
  },

  list(): ConnectionInfo[] {
    const rows = db.prepare("SELECT * FROM connections").all() as ConnectionRow[];
    return rows.map((r) => ({
      network: r.network as Network,
      state: r.state,
      accountLabel: r.account_label ?? undefined,
      meta: JSON.parse(r.meta) as Record<string, string>,
      error: r.error ?? undefined,
    }));
  },

  clear(network: Network): void {
    db.prepare("DELETE FROM connections WHERE network = ?").run(network);
  },
});

/* ---------------------------------- media ---------------------------------- */

interface MediaRow {
  id: string;
  kind: "image" | "video";
  mime_type: string;
  name: string;
  size: number;
  width: number | null;
  height: number | null;
  duration_seconds: number | null;
  path: string;
  created_at: string;
}

function mediaFromRow(r: MediaRow): MediaItem {
  return {
    id: r.id,
    kind: r.kind,
    mimeType: r.mime_type,
    name: r.name,
    size: r.size,
    width: r.width ?? undefined,
    height: r.height ?? undefined,
    durationSeconds: r.duration_seconds ?? undefined,
    createdAt: r.created_at,
  };
}

export const mediaRepo = (db: DB = getDb()) => ({
  create(input: Omit<MediaItem, "id" | "createdAt"> & { path: string }): MediaItem {
    const id = newId();
    db.prepare(
      `INSERT INTO media (id, kind, mime_type, name, size, width, height, duration_seconds, path, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      input.kind,
      input.mimeType,
      input.name,
      input.size,
      input.width ?? null,
      input.height ?? null,
      input.durationSeconds ?? null,
      input.path,
      now(),
    );
    return this.get(id) as MediaItem;
  },

  get(id: string): MediaItem | null {
    const row = db.prepare("SELECT * FROM media WHERE id = ?").get(id) as MediaRow | undefined;
    return row ? mediaFromRow(row) : null;
  },

  /** Internal: absolute path on disk. Never expose to the client. */
  pathOf(id: string): string | null {
    const row = db.prepare("SELECT path FROM media WHERE id = ?").get(id) as
      | { path: string }
      | undefined;
    return row?.path ?? null;
  },

  remove(id: string): string | null {
    const path = this.pathOf(id);
    db.prepare("DELETE FROM media WHERE id = ?").run(id);
    return path;
  },

  byIds(ids: string[]): MediaItem[] {
    if (ids.length === 0) return [];
    const placeholders = ids.map(() => "?").join(",");
    const rows = db
      .prepare(`SELECT * FROM media WHERE id IN (${placeholders})`)
      .all(...ids) as MediaRow[];
    const map = new Map(rows.map((r) => [r.id, mediaFromRow(r)]));
    return ids.map((id) => map.get(id)).filter((m): m is MediaItem => Boolean(m));
  },
});

/* -------------------------------- oauth states ----------------------------- */

export const oauthStatesRepo = (db: DB = getDb()) => ({
  create(provider: string, state: string, verifier: string | null, ttlMs = 10 * 60 * 1000): void {
    const createdAt = now();
    const expiresAt = new Date(Date.now() + ttlMs).toISOString();
    db.prepare(
      "INSERT INTO oauth_states (state, provider, verifier, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
    ).run(state, provider, verifier, createdAt, expiresAt);
  },

  /** Single-use: returns the record and deletes it. */
  consume(provider: string, state: string): { verifier: string | null } | null {
    const row = db
      .prepare("SELECT verifier, expires_at FROM oauth_states WHERE state = ? AND provider = ?")
      .get(state, provider) as { verifier: string | null; expires_at: string } | undefined;
    db.prepare("DELETE FROM oauth_states WHERE state = ?").run(state);
    if (!row) return null;
    if (new Date(row.expires_at).getTime() < Date.now()) return null;
    return { verifier: row.verifier };
  },
});

/* -------------------------------- R2 settings ------------------------------ */

interface R2Row {
  account_id: string;
  bucket: string;
  public_url_strategy: "public" | "presigned";
  public_base_url: string | null;
  credential_ref: string | null;
}

export interface StoredR2Settings {
  accountId: string;
  bucket: string;
  publicUrlStrategy: "public" | "presigned";
  publicBaseUrl?: string;
  credentialRef?: string;
}

export const r2Repo = (db: DB = getDb()) => ({
  get(): StoredR2Settings | null {
    const row = db.prepare("SELECT * FROM r2_settings WHERE id = 1").get() as R2Row | undefined;
    if (!row) return null;
    return {
      accountId: row.account_id,
      bucket: row.bucket,
      publicUrlStrategy: row.public_url_strategy,
      publicBaseUrl: row.public_base_url ?? undefined,
      credentialRef: row.credential_ref ?? undefined,
    };
  },

  view(): R2SettingsView {
    const r2 = this.get();
    if (!r2) return { configured: false, hasCredentials: false };
    return {
      configured: Boolean(
        r2.accountId &&
          r2.credentialRef &&
          (r2.publicUrlStrategy === "presigned" || r2.publicBaseUrl),
      ),
      accountId: r2.accountId || undefined,
      bucket: r2.bucket,
      publicUrlStrategy: r2.publicUrlStrategy,
      publicBaseUrl: r2.publicBaseUrl,
      hasCredentials: Boolean(r2.credentialRef),
    };
  },

  save(input: StoredR2Settings): void {
    db.prepare(
      `INSERT INTO r2_settings (id, account_id, bucket, public_url_strategy, public_base_url, credential_ref, updated_at)
       VALUES (1, @account_id, @bucket, @public_url_strategy, @public_base_url, @credential_ref, @updated_at)
       ON CONFLICT(id) DO UPDATE SET
         account_id = @account_id, bucket = @bucket,
         public_url_strategy = @public_url_strategy, public_base_url = @public_base_url,
         credential_ref = COALESCE(@credential_ref, credential_ref), updated_at = @updated_at`,
    ).run({
      account_id: input.accountId,
      bucket: input.bucket,
      public_url_strategy: input.publicUrlStrategy,
      public_base_url: input.publicBaseUrl ?? null,
      credential_ref: input.credentialRef ?? null,
      updated_at: now(),
    });
  },

  clear(): void {
    db.prepare("DELETE FROM r2_settings WHERE id = 1").run();
  },
});

/* ------------------------------ staged objects ----------------------------- */

export const stagedRepo = (db: DB = getDb()) => ({
  add(attemptId: string | null, bucket: string, key: string): string {
    const id = newId();
    db.prepare(
      "INSERT INTO staged_objects (id, attempt_id, bucket, key, created_at) VALUES (?, ?, ?, ?, ?)",
    ).run(id, attemptId, bucket, key, now());
    return id;
  },

  remove(id: string): void {
    db.prepare("DELETE FROM staged_objects WHERE id = ?").run(id);
  },

  forAttempt(attemptId: string): { id: string; bucket: string; key: string }[] {
    return db
      .prepare("SELECT id, bucket, key FROM staged_objects WHERE attempt_id = ?")
      .all(attemptId) as { id: string; bucket: string; key: string }[];
  },

  olderThan(cutoffIso: string): { id: string; bucket: string; key: string }[] {
    return db
      .prepare("SELECT id, bucket, key FROM staged_objects WHERE created_at < ?")
      .all(cutoffIso) as { id: string; bucket: string; key: string }[];
  },
});

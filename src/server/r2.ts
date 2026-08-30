import { createReadStream } from "node:fs";
import { join } from "node:path";
import {
  DeleteObjectCommand,
  HeadBucketCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { readSecret } from "./credentials";
import { type StoredR2Settings, mediaRepo, r2Repo, stagedRepo } from "./db/repositories";
import { mediaDir, useFakeR2 } from "./env";
import { log } from "./log";

/**
 * Temporary staging of Meta-bound media (Threads/Instagram require media to be
 * fetchable by Meta over HTTPS). Objects are staged into a user-configured
 * Cloudflare R2 and removed after publishing; anything orphaned is
 * cleaned up after a bounded window by startup recovery.
 */

export interface R2Credentials {
  accessKeyId: string;
  secretAccessKey: string;
}

export interface StagedObject {
  key: string;
  /** URL Meta can fetch (public or presigned). */
  url: string;
}

export interface R2Stager {
  stage(mediaId: string, attemptId: string | null): Promise<StagedObject>;
  remove(key: string): Promise<void>;
  testConnection(): Promise<void>;
  bucket(): string;
}

const PRESIGN_TTL_SECONDS = 60 * 60; // 1 hour, enough for Meta to fetch
export const STAGED_CLEANUP_WINDOW_MS = 24 * 60 * 60 * 1000; // 24 hours

class CloudflareR2Stager implements R2Stager {
  private client: S3Client;
  constructor(
    private settings: StoredR2Settings,
    creds: R2Credentials,
  ) {
    this.client = new S3Client({
      endpoint: `https://${settings.accountId}.r2.cloudflarestorage.com`,
      region: "auto",
      forcePathStyle: true,
      credentials: { accessKeyId: creds.accessKeyId, secretAccessKey: creds.secretAccessKey },
    });
  }

  bucket(): string {
    return this.settings.bucket;
  }

  async stage(mediaId: string, attemptId: string | null): Promise<StagedObject> {
    const repo = mediaRepo();
    const item = repo.get(mediaId);
    const relPath = repo.pathOf(mediaId);
    if (!item || !relPath) throw new Error(`Media ${mediaId} not found`);

    const key = `blather-staging/${attemptId ?? "unlinked"}/${mediaId}-${item.name.replace(/[^A-Za-z0-9._-]/g, "_")}`;
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.settings.bucket,
        Key: key,
        Body: createReadStream(join(mediaDir(), relPath)),
        ContentType: item.mimeType,
        ContentLength: item.size,
      }),
    );
    stagedRepo().add(attemptId, this.settings.bucket, key);

    const url = await this.publicUrl(key);
    return { key, url };
  }

  private async publicUrl(key: string): Promise<string> {
    if (this.settings.publicUrlStrategy === "presigned") {
      return getSignedUrl(
        this.client,
        new (await import("@aws-sdk/client-s3")).GetObjectCommand({
          Bucket: this.settings.bucket,
          Key: key,
        }),
        { expiresIn: PRESIGN_TTL_SECONDS },
      );
    }
    const base = this.settings.publicBaseUrl?.replace(/\/$/, "");
    if (!base) throw new Error("A public R2 bucket URL is required for public media URLs");
    return `${base}/${key}`;
  }

  async remove(key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.settings.bucket, Key: key }));
  }

  async testConnection(): Promise<void> {
    await this.client.send(new HeadBucketCommand({ Bucket: this.settings.bucket }));
  }
}

/** In-memory stager for tests/e2e; URLs point at a fake host. */
export class FakeR2Stager implements R2Stager {
  objects = new Map<string, { mediaId: string; contentType: string }>();
  constructor(private settings?: StoredR2Settings) {}

  bucket(): string {
    return this.settings?.bucket ?? "fake-bucket";
  }

  async stage(mediaId: string, attemptId: string | null): Promise<StagedObject> {
    const item = mediaRepo().get(mediaId);
    if (!item) throw new Error(`Media ${mediaId} not found`);
    const key = `blather-staging/${attemptId ?? "unlinked"}/${mediaId}-${item.name}`;
    this.objects.set(key, { mediaId, contentType: item.mimeType });
    stagedRepo().add(attemptId, this.bucket(), key);
    const base =
      this.settings?.publicUrlStrategy === "public" && this.settings.publicBaseUrl
        ? this.settings.publicBaseUrl.replace(/\/$/, "")
        : `https://fake-r2.local/${this.bucket()}`;
    return { key, url: `${base}/${key}` };
  }

  async remove(key: string): Promise<void> {
    this.objects.delete(key);
  }

  async testConnection(): Promise<void> {
    if (!this.settings) throw new Error("R2 not configured");
  }
}

let cachedStager: R2Stager | null = null;

export function getStager(): R2Stager {
  if (cachedStager) return cachedStager;
  const settings = r2Repo().get();
  if (
    !settings?.accountId ||
    (settings.publicUrlStrategy === "public" && !settings.publicBaseUrl)
  ) {
    throw new Error("R2 staging is not configured (see Settings)");
  }
  if (useFakeR2()) return new FakeR2Stager(settings);
  const creds = readSecret<R2Credentials>(settings.credentialRef);
  if (!creds) throw new Error("R2 credentials missing (see Settings)");
  cachedStager = new CloudflareR2Stager(settings, creds);
  return cachedStager;
}

/** Test hook: inject a stager (e.g. shared FakeR2Stager). */
export function __setStagerForTests(stager: R2Stager | null): void {
  cachedStager = stager;
}

/** Remove staged objects older than the cleanup window (orphans). */
export async function cleanupOrphanedStaged(nowMs = Date.now()): Promise<number> {
  const cutoff = new Date(nowMs - STAGED_CLEANUP_WINDOW_MS).toISOString();
  const orphans = stagedRepo().olderThan(cutoff);
  if (orphans.length === 0) return 0;
  let stager: R2Stager;
  try {
    stager = getStager();
  } catch {
    log.warn("R2 not configured; skipping orphaned staging cleanup");
    return 0;
  }
  let removed = 0;
  for (const obj of orphans) {
    try {
      await stager.remove(obj.key);
      stagedRepo().remove(obj.id);
      removed++;
    } catch (err) {
      log.warn(`Failed to remove staged object ${obj.key}:`, err);
    }
  }
  return removed;
}

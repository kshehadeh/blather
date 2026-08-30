import { execFile } from "node:child_process";
import { statSync } from "node:fs";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { CAPABILITIES } from "@/lib/capabilities";
import type { MediaItem, ResolvedContent } from "@/lib/types";
import { type BasicCredentials, readSecret, storeSecret } from "@/server/credentials";
import { connectionsRepo } from "@/server/db/repositories";
import { mediaPath } from "./common";
import { ProviderError, fetchJson, sanitizeProviderMessage } from "./errors";
import type { HealthResult, ProviderAdapter, PublishContext, PublishResult } from "./types";
import { validateContent } from "./validation";

const NETWORK = "bluesky" as const;
const execFileAsync = promisify(execFile);
const MAX_IMAGE_BYTES = CAPABILITIES.bluesky.maxImageBytes ?? 1_000_000;
const JPEG_PROFILES = [
  { quality: 80, maxDimension: 0 },
  { quality: 65, maxDimension: 0 },
  { quality: 70, maxDimension: 2000 },
  { quality: 65, maxDimension: 1600 },
  { quality: 60, maxDimension: 1200 },
] as const;

interface Session {
  accessJwt: string;
  refreshJwt: string;
  did: string;
  handle: string;
  pds: string;
}

/**
 * Bluesky adapter: app-password session auth against the account's PDS,
 * rich-text facets, image blobs, and asynchronous video upload with job
 * status polling (video.bsky.app + service auth).
 */
export const blueskyAdapter: ProviderAdapter = {
  network: NETWORK,

  isConnected(): boolean {
    const conn = connectionsRepo().get(NETWORK);
    return conn.state === "connected" && Boolean(conn.credentialRef);
  },

  async refreshIfNeeded(): Promise<void> {
    await session();
  },

  validate(content: ResolvedContent): void {
    validateContent(NETWORK, content);
  },

  async publish(content: ResolvedContent, _ctx: PublishContext): Promise<PublishResult> {
    const sess = await session();
    const record: Record<string, unknown> = {
      $type: "app.bsky.feed.post",
      text: content.text,
      facets: buildFacets(content.text),
      createdAt: new Date().toISOString(),
    };

    const images = content.media.filter((m) => m.kind === "image");
    const video = content.media.find((m) => m.kind === "video");

    if (images.length > 0) {
      const uploaded = [];
      for (const img of images) {
        const blob = await uploadBlob(sess, img);
        uploaded.push({
          alt: "",
          image: blob,
          ...(img.width && img.height
            ? { aspectRatio: { width: img.width, height: img.height } }
            : {}),
        });
      }
      record.embed = { $type: "app.bsky.embed.images", images: uploaded };
    } else if (video) {
      const blob = await uploadVideo(sess, video.id, video.mimeType);
      record.embed = {
        $type: "app.bsky.embed.video",
        video: blob,
        ...(video.width && video.height
          ? { aspectRatio: { width: video.width, height: video.height } }
          : {}),
      };
    }

    const res = await fetchJson(NETWORK, `${sess.pds}/xrpc/com.atproto.repo.createRecord`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${sess.accessJwt}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        repo: sess.did,
        collection: "app.bsky.feed.post",
        record,
      }),
    });
    const body = res.body as { uri?: string; cid?: string };
    const rkey = body.uri?.split("/").pop();
    return {
      providerPostId: body.uri,
      providerPostUrl:
        rkey && sess.handle ? `https://bsky.app/profile/${sess.handle}/post/${rkey}` : undefined,
    };
  },

  normalizeError(err: unknown): string {
    return sanitizeProviderMessage("bluesky", err);
  },

  async health(): Promise<HealthResult> {
    try {
      const s = await session();
      return { ok: true, accountLabel: `@${s.handle}`, meta: { did: s.did, pds: s.pds } };
    } catch (err) {
      return { ok: false, error: this.normalizeError(err) };
    }
  },
};

/** Establish or refresh a session using the stored app password. */
export async function createBlueskySession(
  pds: string,
  identifier: string,
  appPassword: string,
): Promise<Session> {
  const res = await fetchJson(NETWORK, `${pds}/xrpc/com.atproto.server.createSession`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ identifier, password: appPassword }),
  });
  const body = res.body as { accessJwt: string; refreshJwt: string; did: string; handle: string };
  return { ...body, pds };
}

async function session(): Promise<Session> {
  const conn = connectionsRepo().get(NETWORK);
  const creds = readSecret<BasicCredentials & { accessJwt?: string; refreshJwt?: string }>(
    conn.credentialRef,
  );
  if (!creds) throw new ProviderError(NETWORK, "bluesky: not connected");
  const pds = creds.meta?.pds ?? "https://bsky.social";

  if (creds.accessJwt && !jwtExpiringSoon(creds.accessJwt)) {
    return {
      accessJwt: creds.accessJwt,
      refreshJwt: creds.refreshJwt ?? "",
      did: creds.meta?.did ?? "",
      handle: creds.identifier,
      pds,
    };
  }
  if (creds.refreshJwt) {
    try {
      const res = await fetchJson(NETWORK, `${pds}/xrpc/com.atproto.server.refreshSession`, {
        method: "POST",
        headers: { Authorization: `Bearer ${creds.refreshJwt}` },
      });
      const refreshed = res.body as {
        accessJwt: string;
        refreshJwt: string;
        did?: string;
        handle?: string;
      };
      if (!refreshed.accessJwt || !refreshed.refreshJwt) {
        throw new ProviderError(NETWORK, "bluesky: refreshed session was incomplete");
      }
      return saveSession(conn.credentialRef as string, creds, pds, {
        accessJwt: refreshed.accessJwt,
        refreshJwt: refreshed.refreshJwt,
        did: refreshed.did ?? creds.meta?.did ?? "",
        handle: refreshed.handle ?? creds.identifier,
      });
    } catch {
      // A refresh JWT can expire or be revoked. The app password can establish a new session.
    }
  }
  const fresh = await createBlueskySession(pds, creds.identifier, creds.secret);
  return saveSession(conn.credentialRef as string, creds, pds, fresh);
}

function saveSession(
  credentialRef: string,
  creds: BasicCredentials & { accessJwt?: string; refreshJwt?: string },
  pds: string,
  fresh: Omit<Session, "pds">,
): Session {
  storeSecret(credentialRef, {
    ...creds,
    accessJwt: fresh.accessJwt,
    refreshJwt: fresh.refreshJwt,
    meta: { ...creds.meta, pds, did: fresh.did },
  });
  return { ...fresh, pds };
}

function jwtExpiringSoon(jwt: string, skewSeconds = 60): boolean {
  try {
    const payload = JSON.parse(Buffer.from(jwt.split(".")[1], "base64url").toString("utf8")) as {
      exp?: unknown;
    };
    return typeof payload.exp === "number" && payload.exp - Date.now() / 1000 < skewSeconds;
  } catch {
    // Tokens without a parseable expiration are left to the PDS to validate.
    return false;
  }
}

async function uploadBlob(session: Session, media: MediaItem): Promise<Record<string, unknown>> {
  const { data, mimeType } = await blueskyImageData(media);
  // Bluesky blob uploads are whole-body; post images are capped at 1 MB, so this is
  // acceptable. Video goes through the async video service instead.
  try {
    const res = await fetchJson(NETWORK, `${session.pds}/xrpc/com.atproto.repo.uploadBlob`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${session.accessJwt}`,
        "Content-Type": mimeType,
        "Content-Length": String(data.byteLength),
      },
      body: new Uint8Array(data),
    });
    const body = res.body as { blob?: Record<string, unknown> };
    if (!body.blob) throw new ProviderError(NETWORK, "bluesky: blob upload returned no blob");
    return body.blob;
  } catch (err) {
    if (err instanceof ProviderError && err.opts.status === 400) {
      throw new ProviderError(
        NETWORK,
        `${err.message}. Bluesky post images must be 1 MB or smaller.`,
        { status: 400 },
      );
    }
    throw err;
  }
}

async function blueskyImageData(
  media: MediaItem,
): Promise<{ data: Buffer; mimeType: "image/jpeg" | MediaItem["mimeType"] }> {
  const path = mediaPath(media.id);
  if (media.size <= MAX_IMAGE_BYTES) {
    return { data: await readFile(path), mimeType: media.mimeType };
  }
  if (media.mimeType === "image/gif") {
    throw new ProviderError(
      NETWORK,
      `bluesky: ${media.name} is an animated GIF over the 1MB limit and cannot be converted without losing animation`,
    );
  }

  const dir = await mkdtemp(join(tmpdir(), "blather-bluesky-"));
  const output = join(dir, "optimized.jpg");
  try {
    for (const profile of JPEG_PROFILES) {
      const args = [
        "-s",
        "format",
        "jpeg",
        "-s",
        "formatOptions",
        String(profile.quality),
        ...(profile.maxDimension > 0
          ? ["--resampleHeightWidthMax", String(profile.maxDimension)]
          : []),
        path,
        "--out",
        output,
      ];
      try {
        await execFileAsync("/usr/bin/sips", args);
      } catch {
        throw new ProviderError(NETWORK, `bluesky: could not convert ${media.name} to JPEG`);
      }
      const data = await readFile(output);
      if (data.byteLength <= MAX_IMAGE_BYTES) return { data, mimeType: "image/jpeg" };
    }
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
  throw new ProviderError(
    NETWORK,
    `bluesky: ${media.name} could not be reduced below the 1MB image limit`,
  );
}

/** Async video upload: service auth -> video.bsky.app upload -> poll job. */
async function uploadVideo(
  session: Session,
  mediaId: string,
  mimeType: string,
): Promise<Record<string, unknown>> {
  const path = mediaPath(mediaId);
  const size = statSync(path).size;

  const limits = await fetchJson(NETWORK, `${session.pds}/xrpc/app.bsky.video.getUploadLimits`, {
    headers: { Authorization: `Bearer ${session.accessJwt}` },
  });
  const lim = limits.body as { canUpload?: boolean; remainingDailyBytes?: number };
  if (lim.canUpload === false || (lim.remainingDailyBytes ?? 1) < size) {
    throw new ProviderError(NETWORK, "bluesky: daily video upload limit reached");
  }

  // Scoped service auth authorizes video.bsky.app to upload to the user's PDS.
  const pdsHost = new URL(session.pds).host;
  const serviceAuthUrl = new URL(`${session.pds}/xrpc/com.atproto.server.getServiceAuth`);
  serviceAuthUrl.searchParams.set("aud", `did:web:${pdsHost}`);
  serviceAuthUrl.searchParams.set("lxm", "com.atproto.repo.uploadBlob");
  serviceAuthUrl.searchParams.set("exp", String(Math.floor(Date.now() / 1000) + 1800));
  const authRes = await fetchJson(NETWORK, serviceAuthUrl.toString(), {
    headers: { Authorization: `Bearer ${session.accessJwt}` },
  });
  const serviceToken = String((authRes.body as Record<string, unknown>).token);

  const name = path.split("/").pop() ?? "video.mp4";
  const uploadRes = await fetch(
    `https://video.bsky.app/xrpc/app.bsky.video.uploadVideo?did=${encodeURIComponent(session.did)}&name=${encodeURIComponent(name)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${serviceToken}`,
        "Content-Type": mimeType,
        "Content-Length": String(size),
      },
      body: new Uint8Array(await readFile(path)),
    },
  );
  const uploadBody = (await uploadRes.json().catch(() => null)) as {
    jobId?: string;
    blob?: Record<string, unknown>;
  } | null;
  if (!uploadRes.ok || (!uploadBody?.jobId && !uploadBody?.blob)) {
    throw new ProviderError(NETWORK, `bluesky: video upload failed (HTTP ${uploadRes.status})`);
  }
  if (uploadBody?.blob) return uploadBody.blob;

  // Poll job status
  const jobId = uploadBody?.jobId as string;
  const deadline = Date.now() + 10 * 60 * 1000;
  for (;;) {
    if (Date.now() > deadline) {
      throw new ProviderError(NETWORK, "bluesky: video processing timed out");
    }
    await new Promise((r) => setTimeout(r, 5000));
    const status = await fetchJson(
      NETWORK,
      `https://video.bsky.app/xrpc/app.bsky.video.getJobStatus?jobId=${encodeURIComponent(jobId)}`,
      { headers: { Authorization: `Bearer ${serviceToken}` } },
    );
    const job = (
      status.body as {
        jobStatus?: { state?: string; blob?: Record<string, unknown>; error?: string };
      }
    ).jobStatus;
    if (job?.state === "JOB_STATE_COMPLETED" && job.blob) return job.blob;
    if (job?.state === "JOB_STATE_FAILED") {
      throw new ProviderError(
        NETWORK,
        `bluesky: video processing failed (${job.error ?? "unknown"})`,
      );
    }
  }
}

/** Build rich-text facets (links, mentions, hashtags) with UTF-8 byte offsets. */
export function buildFacets(text: string): Record<string, unknown>[] {
  const facets: Record<string, unknown>[] = [];
  const encoder = new TextEncoder();
  const byteIndex = (charIndex: number) => encoder.encode(text.slice(0, charIndex)).length;

  const patterns: { regex: RegExp; feature: (m: RegExpMatchArray) => Record<string, unknown> }[] = [
    {
      regex: /https?:\/\/[^\s]+/g,
      feature: (m) => ({ $type: "app.bsky.richtext.facet#link", uri: m[0] }),
    },
    {
      regex: /(^|\s)(@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,})/g,
      feature: (m) => ({ $type: "app.bsky.richtext.facet#mention", did: m[2].slice(1) }),
    },
    {
      regex: /(^|\s)(#[\p{L}\p{N}_]+)/gu,
      feature: (m) => ({ $type: "app.bsky.richtext.facet#tag", tag: m[2].slice(1) }),
    },
  ];

  for (const { regex, feature } of patterns) {
    for (const m of text.matchAll(regex)) {
      const matched = m[1] !== undefined && m[2] !== undefined ? m[2] : m[0];
      const charStart =
        (m.index ?? 0) + (m[1] !== undefined && m[2] !== undefined ? m[1].length : 0);
      facets.push({
        index: { byteStart: byteIndex(charStart), byteEnd: byteIndex(charStart + matched.length) },
        features: [feature(m as RegExpMatchArray)],
      });
    }
  }
  // Mentions require DID resolution to render; unresolved handle facets are
  // harmless but we drop mention facets without DIDs resolved to avoid noise.
  return facets.filter(
    (f) =>
      (f.features as Record<string, unknown>[])[0].$type !== "app.bsky.richtext.facet#mention" ||
      Boolean((f.features as { did?: string }[])[0].did),
  );
}

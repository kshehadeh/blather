import { statSync } from "node:fs";
import type { ResolvedContent } from "@/lib/types";
import { saveTokens } from "./common";
import { chunkFile, loadTokens, mediaPath, requireTokens, tokenExpiringSoon } from "./common";
import { ProviderError, fetchJson, sanitizeProviderMessage } from "./errors";
import type { HealthResult, ProviderAdapter, PublishContext, PublishResult } from "./types";
import { validateContent } from "./validation";

const NETWORK = "x" as const;
const API = "https://api.x.com";
const CHUNK = 4 * 1024 * 1024;

/**
 * X adapter: OAuth 2.0 PKCE, media upload via the v2 chunked media API,
 * posting via v2 POST /2/tweets.
 */
export const xAdapter: ProviderAdapter = {
  network: NETWORK,

  isConnected(): boolean {
    return Boolean(loadTokens(NETWORK)?.accessToken);
  },

  async refreshIfNeeded(): Promise<void> {
    const tokens = loadTokens(NETWORK);
    if (!tokens?.refreshToken || !tokenExpiringSoon(tokens)) return;
    const clientId = tokens.meta?.clientId;
    if (!clientId) throw new ProviderError(NETWORK, "x: missing client id for token refresh");
    const res = await fetchJson(NETWORK, `${API}/2/oauth2/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        refresh_token: tokens.refreshToken,
        client_id: clientId,
      }),
    });
    const body = res.body as Record<string, unknown>;
    saveTokens(NETWORK, {
      ...tokens,
      accessToken: String(body.access_token),
      refreshToken: (body.refresh_token as string) ?? tokens.refreshToken,
      expiresAt: Date.now() + Number(body.expires_in ?? 7200) * 1000,
    });
  },

  validate(content: ResolvedContent): void {
    validateContent(NETWORK, content);
  },

  async publish(content: ResolvedContent, _ctx: PublishContext): Promise<PublishResult> {
    await this.refreshIfNeeded();
    const tokens = requireTokens(NETWORK);
    const auth = { Authorization: `Bearer ${tokens.accessToken}` };

    const mediaIds: string[] = [];
    for (const item of content.media) {
      mediaIds.push(await uploadMedia(auth, item.id, item.mimeType, item.kind));
    }

    const payload: Record<string, unknown> = { text: content.text };
    if (mediaIds.length > 0) payload.media = { media_ids: mediaIds };
    if (!content.text && mediaIds.length > 0) payload.text = "";

    const res = await fetchJson(NETWORK, `${API}/2/tweets`, {
      method: "POST",
      headers: { ...auth, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = (res.body as { data?: { id?: string } })?.data;
    const id = data?.id;
    const username = tokens.meta?.username;
    return {
      providerPostId: id,
      providerPostUrl: id && username ? `https://x.com/${username}/status/${id}` : undefined,
    };
  },

  normalizeError(err: unknown): string {
    return sanitizeProviderMessage("x", err);
  },

  async health(): Promise<HealthResult> {
    try {
      await this.refreshIfNeeded();
      const tokens = requireTokens(NETWORK);
      const res = await fetchJson(NETWORK, `${API}/2/users/me`, {
        headers: { Authorization: `Bearer ${tokens.accessToken}` },
      });
      const user = (res.body as { data?: { username?: string; id?: string } })?.data;
      return {
        ok: true,
        accountLabel: user?.username ? `@${user.username}` : undefined,
        meta: user?.id ? { userId: user.id } : {},
      };
    } catch (err) {
      return { ok: false, error: this.normalizeError(err) };
    }
  },
};

async function uploadMedia(
  auth: Record<string, string>,
  mediaId: string,
  mimeType: string,
  kind: "image" | "video",
): Promise<string> {
  try {
    const path = mediaPath(mediaId);
    const total = statSync(path).size;
    const mediaCategory =
      kind === "video" ? "tweet_video" : mimeType === "image/gif" ? "tweet_gif" : "tweet_image";

    // INIT
    const initRes = await fetchJson(NETWORK, `${API}/2/media/upload/initialize`, {
      method: "POST",
      headers: { ...auth, "Content-Type": "application/json" },
      body: JSON.stringify({
        total_bytes: total,
        media_type: mimeType,
        media_category: mediaCategory,
      }),
    });
    const uploadId = String((initRes.body as { data?: { id?: string } }).data?.id ?? "");
    if (!uploadId) throw new ProviderError(NETWORK, "x: media upload did not return an id");

    // APPEND in chunks (streams from disk; nothing large is buffered)
    let segment = 0;
    for await (const chunk of chunkFile(path, CHUNK)) {
      const form = new FormData();
      form.set("command", "APPEND");
      form.set("media_id", uploadId);
      form.set("segment_index", String(segment));
      form.set("media", new Blob([new Uint8Array(chunk)], { type: mimeType }));
      await fetchJson(NETWORK, `${API}/2/media/upload/${uploadId}/append`, {
        method: "POST",
        headers: auth,
        body: form,
      });
      segment++;
    }

    // FINALIZE
    const finRes = await fetchJson(NETWORK, `${API}/2/media/upload/${uploadId}/finalize`, {
      method: "POST",
      headers: auth,
    });
    const finBody = (finRes.body as { data?: Record<string, unknown> }).data;
    if (!finBody?.id) throw new ProviderError(NETWORK, "x: media upload did not return an id");

    // STATUS polling for async processing (video/gif)
    const processing = finBody.processing_info as
      | { state?: string; check_after_secs?: number }
      | undefined;
    if (processing) {
      await waitForProcessing(auth, uploadId, processing);
    }
    return uploadId;
  } catch (err) {
    if (err instanceof ProviderError && err.opts.status === 403) {
      throw new ProviderError(
        NETWORK,
        "x: media upload was denied. Reconnect X to grant the media.write permission, then try again.",
        { status: 403 },
      );
    }
    throw err;
  }
}

async function waitForProcessing(
  auth: Record<string, string>,
  mediaId: string,
  initial: { state?: string; check_after_secs?: number },
): Promise<void> {
  let info = initial;
  const deadline = Date.now() + 10 * 60 * 1000;
  while (info.state === "pending" || info.state === "in_progress") {
    if (Date.now() > deadline) throw new ProviderError(NETWORK, "x: media processing timed out");
    await sleep((info.check_after_secs ?? 5) * 1000);
    const res = await fetchJson(NETWORK, `${API}/2/media/upload?media_id=${mediaId}`, {
      headers: auth,
    });
    const nextInfo = (res.body as { data?: { processing_info?: typeof info } }).data
      ?.processing_info;
    if (!nextInfo) throw new ProviderError(NETWORK, "x: media processing status was unavailable");
    info = nextInfo;
    if (info?.state === "failed") {
      throw new ProviderError(NETWORK, "x: media processing failed");
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

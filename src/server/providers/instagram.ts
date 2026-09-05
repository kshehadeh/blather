import type { ResolvedContent } from "@/lib/types";
import { loadTokens, requireTokens, saveTokens, tokenExpiringSoon } from "./common";
import { ProviderError, fetchJson, sanitizeProviderMessage } from "./errors";
import type { HealthResult, ProviderAdapter, PublishContext, PublishResult } from "./types";
import { validateContent } from "./validation";

const NETWORK = "instagram" as const;
const GRAPH = "https://graph.instagram.com/v21.0";

/**
 * Instagram adapter (Instagram Business Login): professional accounts only.
 * Feed images, Reels-style video containers, and carousels. Media must be
 * HTTPS-reachable by Meta, so files are staged temporarily to R2.
 */
export const instagramAdapter: ProviderAdapter = {
  network: NETWORK,

  isConnected(): boolean {
    return Boolean(loadTokens(NETWORK)?.accessToken);
  },

  async refreshIfNeeded(): Promise<void> {
    const tokens = loadTokens(NETWORK);
    if (!tokens?.accessToken || !tokenExpiringSoon(tokens, 24 * 60 * 60 * 1000)) return;
    const res = await fetchJson(
      NETWORK,
      `${GRAPH.replace("/v21.0", "")}/refresh_access_token?grant_type=ig_refresh_token&access_token=${encodeURIComponent(tokens.accessToken)}`,
      {},
    );
    const body = res.body as { access_token?: string; expires_in?: number };
    if (body.access_token) {
      saveTokens(NETWORK, {
        ...tokens,
        accessToken: body.access_token,
        expiresAt: Date.now() + Number(body.expires_in ?? 5184000) * 1000,
      });
    }
  },

  validate(content: ResolvedContent): void {
    validateContent(NETWORK, content);
    const videos = content.media.filter((m) => m.kind === "video");
    for (const v of videos) {
      if (v.durationSeconds !== undefined && (v.durationSeconds < 3 || v.durationSeconds > 900)) {
        throw new ProviderError(NETWORK, "instagram: video must be 3-900 seconds long");
      }
      if (v.width && v.height) {
        const ratio = v.width / v.height;
        if (ratio < 0.01 || ratio > 10) {
          throw new ProviderError(NETWORK, "instagram: video aspect ratio out of range");
        }
      }
    }
  },

  async publish(content: ResolvedContent, ctx: PublishContext): Promise<PublishResult> {
    await this.refreshIfNeeded();
    const tokens = requireTokens(NETWORK);
    const igUserId = tokens.meta?.igUserId;
    if (!igUserId) throw new ProviderError(NETWORK, "instagram: missing user id; reconnect");
    const accessToken = tokens.accessToken;

    const staged: { key: string }[] = [];
    try {
      const creationId = await createContainer(content, ctx, igUserId, accessToken, staged);
      await waitForContainer(creationId, accessToken);
      const res = await fetchJson(NETWORK, `${GRAPH}/${igUserId}/media_publish`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ creation_id: creationId, access_token: accessToken }),
      });
      const id = String((res.body as Record<string, unknown>).id ?? "");
      return { providerPostId: id || undefined };
    } finally {
      await cleanupStaged(ctx, staged);
    }
  },

  normalizeError(err: unknown): string {
    return sanitizeProviderMessage("instagram", err);
  },

  async health(): Promise<HealthResult> {
    try {
      await this.refreshIfNeeded();
      const tokens = requireTokens(NETWORK);
      const res = await fetchJson(
        NETWORK,
        `${GRAPH}/me?fields=user_id,username,account_type&access_token=${encodeURIComponent(tokens.accessToken)}`,
        {},
      );
      const me = res.body as { user_id?: string; username?: string; account_type?: string };
      const meta: Record<string, string> = {};
      if (me.account_type) meta.accountType = me.account_type;
      const normalizedType = me.account_type?.toUpperCase();
      const isProfessional =
        !normalizedType ||
        normalizedType === "BUSINESS" ||
        normalizedType === "CREATOR" ||
        normalizedType === "MEDIA_CREATOR";
      if (!isProfessional) {
        return {
          ok: false,
          accountLabel: me.username ? `@${me.username}` : undefined,
          meta,
          error: "instagram: publishing requires a professional (Business/Creator) account",
        };
      }
      return {
        ok: true,
        accountLabel: me.username ? `@${me.username}` : undefined,
        meta,
      };
    } catch (err) {
      return { ok: false, error: this.normalizeError(err) };
    }
  },
};

async function createContainer(
  content: ResolvedContent,
  ctx: PublishContext,
  igUserId: string,
  accessToken: string,
  staged: { key: string }[],
): Promise<string> {
  const post = async (params: Record<string, string>) => {
    const res = await fetchJson(NETWORK, `${GRAPH}/${igUserId}/media`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ ...params, access_token: accessToken }),
    });
    return String((res.body as Record<string, unknown>).id);
  };

  const stage = async (mediaId: string) => {
    const s = await ctx.stageMedia(mediaId, ctx.attemptId);
    staged.push({ key: s.key });
    return s.url;
  };

  const caption = content.text;
  const images = content.media.filter((m) => m.kind === "image");
  const video = content.media.find((m) => m.kind === "video");

  if (content.media.length === 1) {
    if (video) {
      return post({ media_type: "REELS", video_url: await stage(video.id), caption });
    }
    return post({ image_url: await stage(images[0].id), caption });
  }

  const children: string[] = [];
  for (const item of content.media) {
    const url = await stage(item.id);
    children.push(
      await post(
        item.kind === "video"
          ? { media_type: "VIDEO", video_url: url, is_carousel_item: "true" }
          : { image_url: url, is_carousel_item: "true" },
      ),
    );
  }
  return post({ media_type: "CAROUSEL", children: children.join(","), caption });
}

async function waitForContainer(containerId: string, accessToken: string): Promise<void> {
  const deadline = Date.now() + 10 * 60 * 1000;
  for (;;) {
    if (Date.now() > deadline) {
      throw new ProviderError(NETWORK, "instagram: media processing timed out");
    }
    const res = await fetchJson(
      NETWORK,
      `${GRAPH}/${containerId}?fields=status_code&access_token=${encodeURIComponent(accessToken)}`,
      {},
    );
    const body = res.body as { status_code?: string };
    if (body.status_code === "FINISHED") return;
    if (body.status_code === "ERROR" || body.status_code === "EXPIRED") {
      throw new ProviderError(NETWORK, "instagram: media container failed");
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
}

async function cleanupStaged(ctx: PublishContext, staged: { key: string }[]): Promise<void> {
  if (staged.length === 0) return;
  const { getStager } = await import("@/server/r2");
  const { stagedRepo } = await import("@/server/db/repositories");
  const { log } = await import("@/server/log");
  let stager: ReturnType<typeof getStager>;
  try {
    stager = getStager();
  } catch (err) {
    // Orphaned rows stay in staged_objects and are swept by startup recovery.
    log.warn("R2 unavailable during staged cleanup:", err);
    return;
  }
  for (const s of staged) {
    try {
      await stager.remove(s.key);
    } catch {
      // best effort; swept later by startup recovery
    }
  }
  for (const row of stagedRepo().forAttempt(ctx.attemptId)) {
    stagedRepo().remove(row.id);
  }
}

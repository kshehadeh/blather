import type { ResolvedContent } from "@/lib/types";
import { loadTokens, requireTokens, saveTokens, tokenExpiringSoon } from "./common";
import { ProviderError, fetchJson, sanitizeProviderMessage } from "./errors";
import type { HealthResult, ProviderAdapter, PublishContext, PublishResult } from "./types";
import { validateContent } from "./validation";

const NETWORK = "threads" as const;
const GRAPH = "https://graph.threads.net/v1.0";

/**
 * Threads adapter: media containers (single image/video, text, or carousel)
 * followed by threads_publish. Meta must fetch media over HTTPS, so media is
 * staged temporarily to the configured R2 bucket via ctx.stageMedia.
 */
export const threadsAdapter: ProviderAdapter = {
  network: NETWORK,

  isConnected(): boolean {
    return Boolean(loadTokens(NETWORK)?.accessToken);
  },

  async refreshIfNeeded(): Promise<void> {
    const tokens = loadTokens(NETWORK);
    if (!tokens?.accessToken || !tokenExpiringSoon(tokens, 24 * 60 * 60 * 1000)) return;
    // Long-lived Threads tokens refresh via a simple GET (60-day rolling).
    const res = await fetchJson(
      NETWORK,
      `${GRAPH.replace("/v1.0", "")}/refresh_access_token?grant_type=th_refresh_token&access_token=${encodeURIComponent(tokens.accessToken)}`,
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
  },

  async publish(content: ResolvedContent, ctx: PublishContext): Promise<PublishResult> {
    await this.refreshIfNeeded();
    const tokens = requireTokens(NETWORK);
    const userId = tokens.meta?.userId;
    if (!userId) throw new ProviderError(NETWORK, "threads: missing user id; reconnect");
    const accessToken = tokens.accessToken;

    const staged: { key: string }[] = [];
    try {
      const creationId = await createContainer(content, ctx, userId, accessToken, staged);
      await waitForContainer(creationId, accessToken);
      const res = await fetchJson(NETWORK, `${GRAPH}/${userId}/threads_publish`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ creation_id: creationId, access_token: accessToken }),
      });
      const id = String((res.body as Record<string, unknown>).id ?? "");
      return {
        providerPostId: id || undefined,
        providerPostUrl: undefined, // permalink requires an extra lookup; id is canonical
      };
    } finally {
      await cleanupStaged(ctx, staged);
    }
  },

  normalizeError(err: unknown): string {
    return sanitizeProviderMessage("threads", err);
  },

  async health(): Promise<HealthResult> {
    try {
      await this.refreshIfNeeded();
      const tokens = requireTokens(NETWORK);
      const res = await fetchJson(
        NETWORK,
        `${GRAPH}/me?fields=id,username&access_token=${encodeURIComponent(tokens.accessToken)}`,
        {},
      );
      const me = res.body as { id?: string; username?: string };
      if (me.id && me.id !== tokens.meta?.userId) {
        saveTokens(NETWORK, { ...tokens, meta: { ...tokens.meta, userId: me.id } });
      }
      return { ok: true, accountLabel: me.username ? `@${me.username}` : undefined };
    } catch (err) {
      return { ok: false, error: this.normalizeError(err) };
    }
  },
};

async function createContainer(
  content: ResolvedContent,
  ctx: PublishContext,
  userId: string,
  accessToken: string,
  staged: { key: string }[],
): Promise<string> {
  const post = async (params: Record<string, string>) => {
    const res = await fetchJson(NETWORK, `${GRAPH}/${userId}/threads`, {
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

  const text = content.text;
  const images = content.media.filter((m) => m.kind === "image");
  const video = content.media.find((m) => m.kind === "video");

  if (content.media.length === 0) {
    return post({ media_type: "TEXT", text });
  }

  if (content.media.length === 1) {
    if (video) {
      return post({ media_type: "VIDEO", video_url: await stage(video.id), text });
    }
    return post({ media_type: "IMAGE", image_url: await stage(images[0].id), text });
  }

  // Carousel: create children first, then the parent container.
  const children: string[] = [];
  for (const item of content.media) {
    const url = await stage(item.id);
    children.push(
      await post(
        item.kind === "video"
          ? { media_type: "VIDEO", video_url: url, is_carousel_item: "true" }
          : { media_type: "IMAGE", image_url: url, is_carousel_item: "true" },
      ),
    );
  }
  return post({
    media_type: "CAROUSEL",
    children: children.join(","),
    ...(text ? { text } : {}),
  });
}

export async function waitForContainer(containerId: string, accessToken: string): Promise<void> {
  const deadline = Date.now() + 10 * 60 * 1000;
  for (;;) {
    if (Date.now() > deadline) {
      throw new ProviderError(NETWORK, "threads: media processing timed out");
    }
    const res = await fetchJson(
      NETWORK,
      `${GRAPH}/${containerId}?fields=status_code,status&access_token=${encodeURIComponent(accessToken)}`,
      {},
    );
    const body = res.body as { status_code?: string; status?: string };
    if (body.status_code === "FINISHED") return;
    if (body.status_code === "ERROR" || body.status_code === "EXPIRED") {
      throw new ProviderError(
        NETWORK,
        `threads: media container failed (${body.status ?? "ERROR"})`,
      );
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
      // best effort; orphaned objects are swept by startup recovery
    }
  }
  for (const row of stagedRepo().forAttempt(ctx.attemptId)) {
    stagedRepo().remove(row.id);
  }
}

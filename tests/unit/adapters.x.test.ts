import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { mediaRepo } from "@/server/db/repositories";
import { mediaDir } from "@/server/env";
import { xAdapter } from "@/server/providers/x";
import { afterEach, describe, expect, it, vi } from "vitest";
import { mockFetch, seedOAuthConnection, setupTestDb } from "../helpers";

function seedImage(db: ReturnType<typeof setupTestDb>) {
  const file = join(mediaDir(), `t-${crypto.randomUUID()}.png`);
  writeFileSync(file, Buffer.from([1, 2, 3, 4]));
  return mediaRepo(db).create({
    kind: "image",
    mimeType: "image/png",
    name: "t.png",
    size: 4,
    path: file.split("/").pop() as string,
  });
}

afterEach(() => vi.unstubAllGlobals());

describe("x adapter", () => {
  it("posts text only", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "x");
    const mock = mockFetch([
      {
        match: (url) => url.includes("/2/tweets"),
        respond: () => ({ body: { data: { id: "post-1" } } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    const result = await xAdapter.publish(
      { text: "hello x", media: [] },
      { attemptId: "a1", stageMedia: async () => ({ key: "k", url: "u" }) },
    );
    expect(result.providerPostId).toBe("post-1");
    expect(result.providerPostUrl).toBe("https://x.com/testuser/status/post-1");
  });

  it("uploads media with INIT/APPEND/FINALIZE then posts", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "x");
    const item = seedImage(db);

    const mock = mockFetch([
      {
        match: (url, init) =>
          url.includes("/2/media/upload/initialize") && String(init?.body).includes("tweet_image"),
        respond: () => ({ body: { data: { id: "m-123" } } }),
      },
      {
        match: (url, init) =>
          url.includes("/2/media/upload/m-123/append") && init?.body instanceof FormData,
        respond: () => ({ body: { data: {} } }),
      },
      {
        match: (url) => url.includes("/2/media/upload/m-123/finalize"),
        respond: () => ({ body: { data: { id: "m-123" } } }),
      },
      {
        match: (url) => url.includes("/2/tweets"),
        respond: () => ({ body: { data: { id: "post-2" } } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    const result = await xAdapter.publish(
      { text: "with image", media: [item] },
      { attemptId: "a2", stageMedia: async () => ({ key: "k", url: "u" }) },
    );
    expect(result.providerPostId).toBe("post-2");

    const tweetCall = mock.calls.find((c) => c.url.includes("/2/tweets"));
    expect(JSON.parse(String(tweetCall?.init?.body))).toMatchObject({
      media: { media_ids: ["m-123"] },
    });
  });

  it("refreshes an expiring token before posting", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "x", { expiresAt: Date.now() - 1000 });
    const mock = mockFetch([
      {
        match: (url) => url.includes("/2/oauth2/token"),
        respond: () => ({
          body: { access_token: "fresh-token", refresh_token: "fresh-refresh", expires_in: 7200 },
        }),
      },
      {
        match: (url) => url.includes("/2/tweets"),
        respond: () => ({ body: { data: { id: "p3" } } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    await xAdapter.publish(
      { text: "refresh please", media: [] },
      { attemptId: "a3", stageMedia: async () => ({ key: "k", url: "u" }) },
    );
    const tokenCall = mock.calls.find((c) => c.url.includes("/2/oauth2/token"));
    expect(String(tokenCall?.init?.body)).toContain("refresh_token");
    const tweetCall = mock.calls.find((c) => c.url.includes("/2/tweets"));
    expect(
      String(
        tweetCall?.init?.headers &&
          (tweetCall.init.headers as Record<string, string>).Authorization,
      ),
    ).toContain("fresh-token");
  });

  it("normalizes provider errors without leaking payloads", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "x");
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(JSON.stringify({ detail: "Forbidden: access_token=TOPSECRET" }), {
            status: 403,
          }),
      ),
    );
    await expect(
      xAdapter.publish(
        { text: "nope", media: [] },
        { attemptId: "a4", stageMedia: async () => ({ key: "k", url: "u" }) },
      ),
    ).rejects.toThrow(/Forbidden/);
    try {
      await xAdapter.publish(
        { text: "nope", media: [] },
        { attemptId: "a5", stageMedia: async () => ({ key: "k", url: "u" }) },
      );
    } catch (err) {
      expect(xAdapter.normalizeError(err)).not.toContain("TOPSECRET");
    }
  });

  it("explains when X denies a v2 media upload", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "x");
    const item = seedImage(db);
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("", { status: 403 })),
    );

    await expect(
      xAdapter.publish(
        { text: "with image", media: [item] },
        { attemptId: "a6", stageMedia: async () => ({ key: "k", url: "u" }) },
      ),
    ).rejects.toThrow(/Reconnect X to grant the media\.write permission/i);
  });

  it("health reports the username", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "x");
    vi.stubGlobal(
      "fetch",
      mockFetch([
        {
          match: (url) => url.includes("/2/users/me"),
          respond: () => ({ body: { data: { id: "u1", username: "karim" } } }),
        },
      ]),
    );
    const health = await xAdapter.health();
    expect(health.ok).toBe(true);
    expect(health.accountLabel).toBe("@karim");
  });
});

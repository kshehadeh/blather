import { mediaRepo } from "@/server/db/repositories";
import { instagramAdapter } from "@/server/providers/instagram";
import type { PublishContext } from "@/server/providers/types";
import { getStager } from "@/server/r2";
import { afterEach, describe, expect, it, vi } from "vitest";
import { mockFetch, seedFakeR2, seedOAuthConnection, setupTestDb } from "../helpers";

const ctx = (attemptId: string): PublishContext => ({
  attemptId,
  stageMedia: (mediaId) => getStager().stage(mediaId, attemptId),
});

afterEach(() => vi.unstubAllGlobals());

describe("instagram adapter", () => {
  it("creates a single-image container and publishes", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "instagram");
    seedFakeR2(db);
    const item = mediaRepo(db).create({
      kind: "image",
      mimeType: "image/jpeg",
      name: "p.jpg",
      size: 20,
      path: "p.jpg",
    });
    const mock = mockFetch([
      {
        match: (url, init) =>
          url.includes("/media") && init?.method === "POST" && !url.includes("media_publish"),
        respond: () => ({ body: { id: "igc-1" } }),
      },
      {
        match: (url) => url.includes("status_code"),
        respond: () => ({ body: { status_code: "FINISHED" } }),
      },
      { match: (url) => url.includes("media_publish"), respond: () => ({ body: { id: "ig-1" } }) },
    ]);
    vi.stubGlobal("fetch", mock);

    const result = await instagramAdapter.publish({ text: "cap", media: [item] }, ctx("i1"));
    expect(result.providerPostId).toBe("ig-1");
    const create = mock.calls.find((c) => c.url.includes("/media") && !c.url.includes("publish"));
    expect(String(create?.init?.body)).toContain("caption=cap");
  });

  it("rejects validation when media is missing", () => {
    expect(() => instagramAdapter.validate({ text: "hi", media: [] })).toThrow(/required/);
  });

  it("rejects out-of-range video durations", () => {
    const v = {
      id: "v",
      kind: "video" as const,
      mimeType: "video/mp4",
      name: "v.mp4",
      size: 100,
      durationSeconds: 1,
      createdAt: new Date().toISOString(),
    };
    expect(() => instagramAdapter.validate({ text: "", media: [v] })).toThrow(/3-900/);
  });

  it("health flags non-professional accounts", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "instagram");
    vi.stubGlobal(
      "fetch",
      mockFetch([
        {
          match: (url) => url.includes("/me"),
          respond: () => ({ body: { user_id: "1", username: "casual", account_type: "PERSONAL" } }),
        },
      ]),
    );
    const health = await instagramAdapter.health();
    expect(health.ok).toBe(false);
    expect(health.error).toMatch(/professional/);
  });

  it("health passes for business accounts", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "instagram");
    vi.stubGlobal(
      "fetch",
      mockFetch([
        {
          match: (url) => url.includes("/me"),
          respond: () => ({ body: { user_id: "1", username: "brand", account_type: "BUSINESS" } }),
        },
      ]),
    );
    const health = await instagramAdapter.health();
    expect(health.ok).toBe(true);
    expect(health.accountLabel).toBe("@brand");
  });
});

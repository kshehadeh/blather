import { mediaRepo } from "@/server/db/repositories";
import { threadsAdapter } from "@/server/providers/threads";
import type { PublishContext } from "@/server/providers/types";
import { getStager } from "@/server/r2";
import { afterEach, describe, expect, it, vi } from "vitest";
import { mockFetch, seedFakeR2, seedOAuthConnection, setupTestDb } from "../helpers";

const ctx = (attemptId: string): PublishContext => ({
  attemptId,
  stageMedia: (mediaId) => getStager().stage(mediaId, attemptId),
});

afterEach(() => vi.unstubAllGlobals());

describe("threads adapter", () => {
  it("publishes a text-only post", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "threads");
    const mock = mockFetch([
      {
        match: (url, init) => url.endsWith("/threads") && init?.method === "POST",
        respond: () => ({ body: { id: "c1" } }),
      },
      {
        match: (url) => url.includes("status_code"),
        respond: () => ({ body: { status_code: "FINISHED" } }),
      },
      { match: (url) => url.includes("threads_publish"), respond: () => ({ body: { id: "p-9" } }) },
    ]);
    vi.stubGlobal("fetch", mock);

    const result = await threadsAdapter.publish({ text: "hi threads", media: [] }, ctx("t1"));
    expect(result.providerPostId).toBe("p-9");

    const create = mock.calls.find((c) => c.url.endsWith("/threads"));
    expect(String(create?.init?.body)).toContain("media_type=TEXT");
  });

  it("stages media to R2, creates container, publishes, then cleans up", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "threads");
    const stager = seedFakeR2(db);
    const item = mediaRepo(db).create({
      kind: "image",
      mimeType: "image/png",
      name: "pic.png",
      size: 10,
      path: "unused.png",
    });

    const mock = mockFetch([
      {
        match: (url, init) => url.endsWith("/threads") && init?.method === "POST",
        respond: () => ({ body: { id: "c-img" } }),
      },
      {
        match: (url) => url.includes("status_code"),
        respond: () => ({ body: { status_code: "FINISHED" } }),
      },
      {
        match: (url) => url.includes("threads_publish"),
        respond: () => ({ body: { id: "p-img" } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    const result = await threadsAdapter.publish({ text: "img", media: [item] }, ctx("t2"));
    expect(result.providerPostId).toBe("p-img");

    // staged object was used in the container request
    const create = mock.calls.find((c) => c.url.endsWith("/threads"));
    expect(String(create?.init?.body)).toContain(encodeURIComponent("https://cdn.fake.local"));
    // and cleaned up after publishing
    expect(stager.objects.size).toBe(0);
  });

  it("creates carousel children then a parent container", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "threads");
    seedFakeR2(db);
    const mk = (name: string) =>
      mediaRepo(db).create({ kind: "image", mimeType: "image/png", name, size: 5, path: name });
    const items = [mk("1.png"), mk("2.png")];

    let containerSeq = 0;
    const mock = mockFetch([
      {
        match: (url, init) => url.endsWith("/threads") && init?.method === "POST",
        respond: () => ({ body: { id: `c-${containerSeq++}` } }),
      },
      {
        match: (url) => url.includes("status_code"),
        respond: () => ({ body: { status_code: "FINISHED" } }),
      },
      {
        match: (url) => url.includes("threads_publish"),
        respond: () => ({ body: { id: "p-car" } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    const result = await threadsAdapter.publish({ text: "car", media: items }, ctx("t3"));
    expect(result.providerPostId).toBe("p-car");

    const creates = mock.calls.filter((c) => c.url.endsWith("/threads"));
    expect(creates).toHaveLength(3); // 2 children + parent
    const parent = creates[2];
    expect(String(parent.init?.body)).toContain("media_type=CAROUSEL");
    expect(String(parent.init?.body)).toContain("children=c-0%2Cc-1");
  });

  it("fails when the container errors", async () => {
    const db = setupTestDb();
    seedOAuthConnection(db, "threads");
    const mock = mockFetch([
      { match: (url) => url.endsWith("/threads"), respond: () => ({ body: { id: "c-err" } }) },
      {
        match: (url) => url.includes("status_code"),
        respond: () => ({ body: { status_code: "ERROR" } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    await expect(threadsAdapter.publish({ text: "x", media: [] }, ctx("t4"))).rejects.toThrow(
      /container failed/,
    );
  });
});

import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { makeCredentialRef, storeSecret } from "@/server/credentials";
import { connectionsRepo, mediaRepo } from "@/server/db/repositories";
import { mediaDir } from "@/server/env";
import { blueskyAdapter, buildFacets } from "@/server/providers/bluesky";
import { afterEach, describe, expect, it, vi } from "vitest";
import { mockFetch, setupTestDb } from "../helpers";

function seedBluesky(db: ReturnType<typeof setupTestDb>) {
  const ref = makeCredentialRef("basic", "bluesky");
  storeSecret(ref, {
    identifier: "me.bsky.social",
    secret: "app-password",
    accessJwt: "jwt-access",
    refreshJwt: "jwt-refresh",
    meta: { pds: "https://pds.test", did: "did:plc:test" },
  });
  connectionsRepo(db).upsert({
    network: "bluesky",
    state: "connected",
    credentialRef: ref,
    accountLabel: "@me.bsky.social",
  });
}

function largeBmp(width = 600, height = 600): Buffer {
  const rowBytes = Math.ceil((width * 3) / 4) * 4;
  const imageBytes = rowBytes * height;
  const data = Buffer.alloc(54 + imageBytes);
  data.write("BM");
  data.writeUInt32LE(data.length, 2);
  data.writeUInt32LE(54, 10);
  data.writeUInt32LE(40, 14);
  data.writeInt32LE(width, 18);
  data.writeInt32LE(height, 22);
  data.writeUInt16LE(1, 26);
  data.writeUInt16LE(24, 28);
  data.writeUInt32LE(imageBytes, 34);
  return data;
}

afterEach(() => vi.unstubAllGlobals());

describe("bluesky facets", () => {
  it("extracts links with byte offsets", () => {
    const facets = buildFacets("see https://example.com/x now");
    expect(facets).toHaveLength(1);
    const f = facets[0] as {
      index: { byteStart: number; byteEnd: number };
      features: { uri: string }[];
    };
    expect(f.features[0].uri).toBe("https://example.com/x");
    expect(f.index.byteStart).toBe(4);
  });

  it("handles multi-byte characters before the match", () => {
    const facets = buildFacets("héllo https://x.co");
    const f = facets[0] as { index: { byteStart: number } };
    expect(f.index.byteStart).toBe("héllo ".length + 1); // é is 2 bytes
  });

  it("extracts hashtags", () => {
    const facets = buildFacets("hello #World");
    expect((facets[0] as { features: { tag: string }[] }).features[0].tag).toBe("World");
  });
});

describe("bluesky adapter", () => {
  it("creates a post record with facets", async () => {
    const db = setupTestDb();
    seedBluesky(db);
    const mock = mockFetch([
      {
        match: (url) => url.includes("com.atproto.repo.createRecord"),
        respond: () => ({
          body: { uri: "at://did:plc:test/app.bsky.feed.post/abc", cid: "bafy" },
        }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    const result = await blueskyAdapter.publish(
      { text: "hi https://example.com", media: [] },
      { attemptId: "b1", stageMedia: async () => ({ key: "k", url: "u" }) },
    );
    expect(result.providerPostId).toBe("at://did:plc:test/app.bsky.feed.post/abc");
    expect(result.providerPostUrl).toBe("https://bsky.app/profile/me.bsky.social/post/abc");

    const call = mock.calls.find((c) => c.url.includes("createRecord"));
    const record = JSON.parse(String(call?.init?.body)).record;
    expect(record.facets).toHaveLength(1);
  });

  it("uploads an image blob and embeds it", async () => {
    const db = setupTestDb();
    seedBluesky(db);
    const file = join(mediaDir(), `b-${crypto.randomUUID()}.jpg`);
    writeFileSync(file, Buffer.from([9, 9, 9]));
    const item = mediaRepo(db).create({
      kind: "image",
      mimeType: "image/jpeg",
      name: "b.jpg",
      size: 3,
      width: 100,
      height: 100,
      path: file.split("/").pop() as string,
    });

    const mock = mockFetch([
      {
        match: (url) => url.includes("uploadBlob"),
        respond: () => ({ body: { blob: { $type: "blob", ref: { $link: "bafyblob" } } } }),
      },
      {
        match: (url) => url.includes("createRecord"),
        respond: () => ({ body: { uri: "at://did:plc:test/app.bsky.feed.post/img1", cid: "c" } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    await blueskyAdapter.publish(
      { text: "pic", media: [item] },
      { attemptId: "b2", stageMedia: async () => ({ key: "k", url: "u" }) },
    );
    const call = mock.calls.find((c) => c.url.includes("createRecord"));
    const record = JSON.parse(String(call?.init?.body)).record;
    expect(record.embed.$type).toBe("app.bsky.embed.images");
    expect(record.embed.images[0].aspectRatio).toEqual({ width: 100, height: 100 });
    const uploadCall = mock.calls.find((c) => c.url.includes("uploadBlob"));
    expect(uploadCall?.init?.headers).toMatchObject({
      Authorization: "Bearer jwt-access",
      "Content-Length": "3",
      "Content-Type": "image/jpeg",
    });
  });

  it("allows oversized images so they can be optimized before uploading", () => {
    const db = setupTestDb();
    seedBluesky(db);
    const item = mediaRepo(db).create({
      kind: "image",
      mimeType: "image/jpeg",
      name: "large.jpg",
      size: 1_000_001,
      path: "large.jpg",
    });

    expect(() => blueskyAdapter.validate({ text: "large image", media: [item] })).not.toThrow();
  });

  it("converts an oversized image to a JPEG before uploading", async () => {
    const db = setupTestDb();
    seedBluesky(db);
    const source = largeBmp();
    const file = join(mediaDir(), `b-${crypto.randomUUID()}.bmp`);
    writeFileSync(file, source);
    const item = mediaRepo(db).create({
      kind: "image",
      mimeType: "image/png",
      name: "large.png",
      size: source.byteLength,
      path: file.split("/").pop() as string,
    });
    const mock = mockFetch([
      {
        match: (url) => url.includes("uploadBlob"),
        respond: () => ({ body: { blob: { $type: "blob", ref: { $link: "bafyoptimized" } } } }),
      },
      {
        match: (url) => url.includes("createRecord"),
        respond: () => ({ body: { uri: "at://did:plc:test/app.bsky.feed.post/img2", cid: "c" } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    await blueskyAdapter.publish(
      { text: "optimized", media: [item] },
      { attemptId: "b3", stageMedia: async () => ({ key: "k", url: "u" }) },
    );

    const uploadCall = mock.calls.find((c) => c.url.includes("uploadBlob"));
    const headers = uploadCall?.init?.headers as Record<string, string>;
    expect(headers["Content-Type"]).toBe("image/jpeg");
    expect(Number(headers["Content-Length"])).toBeLessThanOrEqual(1_000_000);
  });

  it("refreshes a session when no accessJwt is cached", async () => {
    const db = setupTestDb();
    const ref = makeCredentialRef("basic", "bluesky");
    storeSecret(ref, {
      identifier: "me.bsky.social",
      secret: "app-password",
      meta: { pds: "https://pds.test", did: "did:plc:test" },
    });
    connectionsRepo(db).upsert({
      network: "bluesky",
      state: "connected",
      credentialRef: ref,
      accountLabel: "@me.bsky.social",
    });

    const mock = mockFetch([
      {
        match: (url) => url.includes("createSession"),
        respond: () => ({
          body: {
            accessJwt: "new-access",
            refreshJwt: "new-refresh",
            did: "did:plc:test",
            handle: "me.bsky.social",
          },
        }),
      },
      {
        match: (url) => url.includes("createRecord"),
        respond: () => ({ body: { uri: "at://did:plc:test/app.bsky.feed.post/s1", cid: "c" } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    await blueskyAdapter.publish(
      { text: "session", media: [] },
      { attemptId: "b3", stageMedia: async () => ({ key: "k", url: "u" }) },
    );
    const createCall = mock.calls.find((c) => c.url.includes("createRecord"));
    expect((createCall?.init?.headers as Record<string, string>).Authorization).toBe(
      "Bearer new-access",
    );
  });

  it("refreshes an expired access JWT before publishing", async () => {
    const db = setupTestDb();
    const ref = makeCredentialRef("basic", "bluesky");
    const expiredJwt = `header.${Buffer.from(
      JSON.stringify({ exp: Math.floor(Date.now() / 1000) - 60 }),
    ).toString("base64url")}.signature`;
    storeSecret(ref, {
      identifier: "me.bsky.social",
      secret: "app-password",
      accessJwt: expiredJwt,
      refreshJwt: "expired-refresh",
      meta: { pds: "https://pds.test", did: "did:plc:test" },
    });
    connectionsRepo(db).upsert({
      network: "bluesky",
      state: "connected",
      credentialRef: ref,
      accountLabel: "@me.bsky.social",
    });
    const mock = mockFetch([
      {
        match: (url) => url.includes("refreshSession"),
        respond: () => ({
          body: {
            accessJwt: "refreshed-access",
            refreshJwt: "refreshed-refresh",
            did: "did:plc:test",
            handle: "me.bsky.social",
          },
        }),
      },
      {
        match: (url) => url.includes("createRecord"),
        respond: () => ({ body: { uri: "at://did:plc:test/app.bsky.feed.post/r1", cid: "c" } }),
      },
    ]);
    vi.stubGlobal("fetch", mock);

    await blueskyAdapter.publish(
      { text: "refresh please", media: [] },
      { attemptId: "b4", stageMedia: async () => ({ key: "k", url: "u" }) },
    );

    const refreshCall = mock.calls.find((c) => c.url.includes("refreshSession"));
    expect((refreshCall?.init?.headers as Record<string, string>).Authorization).toBe(
      "Bearer expired-refresh",
    );
    const createCall = mock.calls.find((c) => c.url.includes("createRecord"));
    expect((createCall?.init?.headers as Record<string, string>).Authorization).toBe(
      "Bearer refreshed-access",
    );
  });
});

import type { MediaItem } from "@/lib/types";
import { resolveContent } from "@/server/publish/overrides";
import { describe, expect, it } from "vitest";

const mediaItem = (id: string): MediaItem => ({
  id,
  kind: "image",
  mimeType: "image/png",
  name: `${id}.png`,
  size: 10,
  createdAt: new Date().toISOString(),
});

describe("resolveContent", () => {
  const a = mediaItem("a");
  const b = mediaItem("b");
  const byId = new Map([
    ["a", a],
    ["b", b],
  ]);

  it("inherits base content when no override exists", () => {
    const r = resolveContent({ text: "base", mediaIds: ["a", "b"], overrides: {} }, "x", byId);
    expect(r.text).toBe("base");
    expect(r.media.map((m) => m.id)).toEqual(["a", "b"]);
  });

  it("applies a text override without touching media", () => {
    const r = resolveContent(
      { text: "base", mediaIds: ["a"], overrides: { bluesky: { text: "bsky text" } } },
      "bluesky",
      byId,
    );
    expect(r.text).toBe("bsky text");
    expect(r.media).toEqual([a]);
  });

  it("applies a media override including reordering and filtering", () => {
    const r = resolveContent(
      { text: "base", mediaIds: ["a", "b"], overrides: { threads: { mediaIds: ["b"] } } },
      "threads",
      byId,
    );
    expect(r.text).toBe("base");
    expect(r.media).toEqual([b]);
  });

  it("does not leak overrides across networks", () => {
    const draft = {
      text: "base",
      mediaIds: ["a"],
      overrides: { x: { text: "x only" } } as const,
    };
    expect(resolveContent(draft, "bluesky", byId).text).toBe("base");
    expect(resolveContent(draft, "x", byId).text).toBe("x only");
  });

  it("drops unknown media ids gracefully", () => {
    const r = resolveContent(
      { text: "base", mediaIds: ["a", "missing"], overrides: {} },
      "x",
      byId,
    );
    expect(r.media).toEqual([a]);
  });
});

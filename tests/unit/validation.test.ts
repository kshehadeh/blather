import type { MediaItem } from "@/lib/types";
import { ProviderError } from "@/server/providers/errors";
import { validateContent } from "@/server/providers/validation";
import { describe, expect, it } from "vitest";

const image = (over: Partial<MediaItem> = {}): MediaItem => ({
  id: crypto.randomUUID(),
  kind: "image",
  mimeType: "image/jpeg",
  name: "a.jpg",
  size: 1024,
  createdAt: new Date().toISOString(),
  ...over,
});

const video = (over: Partial<MediaItem> = {}): MediaItem => ({
  id: crypto.randomUUID(),
  kind: "video",
  mimeType: "video/mp4",
  name: "v.mp4",
  size: 1024,
  createdAt: new Date().toISOString(),
  ...over,
});

describe("validateContent", () => {
  it("accepts a plain text post for text-capable networks", () => {
    for (const n of ["x", "bluesky", "threads"] as const) {
      expect(() => validateContent(n, { text: "hello", media: [] })).not.toThrow();
    }
  });

  it("requires media on instagram", () => {
    expect(() => validateContent("instagram", { text: "hi", media: [] })).toThrow(ProviderError);
    expect(() => validateContent("instagram", { text: "hi", media: [image()] })).not.toThrow();
  });

  it("enforces per-network character limits", () => {
    const text = "x".repeat(281);
    expect(() => validateContent("x", { text, media: [] })).toThrow(/280/);
    expect(() => validateContent("threads", { text: "x".repeat(501), media: [] })).toThrow(/500/);
    expect(() => validateContent("bluesky", { text: "x".repeat(300), media: [] })).not.toThrow();
  });

  it("enforces image count limits", () => {
    const five = Array.from({ length: 5 }, () => image());
    expect(() => validateContent("x", { text: "t", media: five })).toThrow(/4/);
    expect(() => validateContent("threads", { text: "t", media: five })).not.toThrow();
    const eleven = Array.from({ length: 11 }, () => image());
    expect(() => validateContent("instagram", { text: "t", media: eleven })).toThrow(/10/);
  });

  it("rejects mixed image+video where unsupported", () => {
    const media = [image(), video()];
    expect(() => validateContent("x", { text: "t", media })).toThrow(/mix/i);
    expect(() => validateContent("threads", { text: "t", media })).not.toThrow();
  });

  it("rejects more than one video", () => {
    expect(() => validateContent("x", { text: "t", media: [video(), video()] })).toThrow(
      /one video/i,
    );
  });

  it("rejects unsupported mime types", () => {
    expect(() =>
      validateContent("x", { text: "t", media: [image({ mimeType: "image/tiff" })] }),
    ).toThrow(/unsupported/i);
  });

  it("rejects oversized media", () => {
    expect(() =>
      validateContent("x", { text: "t", media: [image({ size: 11 * 1024 * 1024 })] }),
    ).toThrow(/limit/i);
  });

  it("rejects extreme image aspect ratios", () => {
    expect(() =>
      validateContent("x", { text: "t", media: [image({ width: 1, height: 100 })] }),
    ).toThrow(/aspect/i);
  });

  it("rejects empty posts", () => {
    expect(() => validateContent("x", { text: "  ", media: [] })).toThrow(/no text and no media/);
  });
});

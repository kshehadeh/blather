import { CAPABILITIES, MEDIA_LIMITS } from "@/lib/capabilities";
import type { Network, ResolvedContent } from "@/lib/types";
import { ProviderError } from "./errors";

/**
 * Pre-publish validation: character limits, media counts, MIME types, sizes,
 * aspect/duration constraints, and unsupported combinations. Runs before any
 * external write. Provider-specific nuances live in each adapter's own
 * validate() which calls this first.
 */

export function validateContent(network: Network, content: ResolvedContent): void {
  const caps = CAPABILITIES[network];
  const fail = (message: string): never => {
    throw new ProviderError(network, message);
  };

  const text = content.text.trim();
  const images = content.media.filter((m) => m.kind === "image");
  const videos = content.media.filter((m) => m.kind === "video");

  // Text rules
  if (text.length > caps.maxChars) {
    fail(`${caps.network}: text is ${text.length} characters (limit ${caps.maxChars})`);
  }

  // Media presence rules
  if (caps.requiresMedia && content.media.length === 0) {
    fail(`${caps.network}: at least one image or video is required`);
  }
  if (!text && content.media.length === 0) {
    fail(`${caps.network}: post has no text and no media`);
  }

  // Counts
  if (images.length > 0 && videos.length > 0 && !caps.allowsMixedMedia) {
    fail(`${caps.network}: cannot mix images and video in one post`);
  }
  if (images.length > caps.maxImages) {
    fail(`${caps.network}: ${images.length} images selected (limit ${caps.maxImages})`);
  }
  if (videos.length > 1) {
    fail(`${caps.network}: only one video per post`);
  }
  if (videos.length > 0 && !caps.allowsVideo) {
    fail(`${caps.network}: video is not supported`);
  }
  if (images.length > 1 && !caps.allowsCarousel && !caps.allowsMixedMedia) {
    // e.g. X/Bluesky allow up to 4 images but not as a "carousel" container;
    // handled by maxImages above. This branch is for future providers.
  }

  // Per-item checks
  for (const item of content.media) {
    const limits = MEDIA_LIMITS[item.kind];
    const maxBytes =
      item.kind === "image" && !caps.autoOptimizeImages
        ? Math.min(limits.maxBytes, caps.maxImageBytes ?? limits.maxBytes)
        : limits.maxBytes;
    if (!(limits.mimeTypes as readonly string[]).includes(item.mimeType)) {
      fail(`${caps.network}: unsupported ${item.kind} type ${item.mimeType}`);
    }
    if (item.size > maxBytes) {
      fail(
        `${caps.network}: ${item.name} exceeds the ${Math.round(maxBytes / 1_000_000)}MB ${item.kind} limit`,
      );
    }
    if (item.kind === "video") {
      const videoLimits = MEDIA_LIMITS.video;
      if (
        item.durationSeconds !== undefined &&
        item.durationSeconds > videoLimits.maxDurationSeconds
      ) {
        fail(`${caps.network}: video is longer than ${videoLimits.maxDurationSeconds}s`);
      }
    }
    if (item.kind === "image" && item.width && item.height) {
      const ratio = item.width / item.height;
      if (ratio < 1 / 20 || ratio > 20) {
        fail(`${caps.network}: image ${item.name} has an unsupported aspect ratio`);
      }
    }
  }
}

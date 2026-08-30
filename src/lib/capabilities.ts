import type { Network, ProviderCapabilities } from "./types";

/**
 * Static provider capability metadata used by both server-side validation
 * and client-side previews. Keep in sync with adapter validation.
 */
export const CAPABILITIES: Record<Network, ProviderCapabilities> = {
  x: {
    network: "x",
    maxChars: 280,
    maxImages: 4,
    allowsVideo: true,
    allowsMixedMedia: false,
    allowsCarousel: false,
    requiresMedia: false,
    notes: [
      "Free X API tier is heavily rate-limited and cannot upload media on some plans.",
      "OAuth 2.0 PKCE app with Read and Write permissions required.",
    ],
  },
  bluesky: {
    network: "bluesky",
    maxChars: 300,
    maxImages: 4,
    maxImageBytes: 1_000_000,
    autoOptimizeImages: true,
    allowsVideo: true,
    allowsMixedMedia: false,
    allowsCarousel: false,
    requiresMedia: false,
    notes: [
      "Uses an app password, not your main password.",
      "Larger images are converted to a JPEG under the 1 MB limit before publishing.",
      "Video uploads are processed asynchronously.",
    ],
  },
  threads: {
    network: "threads",
    maxChars: 500,
    maxImages: 20,
    allowsVideo: true,
    allowsMixedMedia: true,
    allowsCarousel: true,
    requiresMedia: false,
    notes: [
      "Media must be reachable by Meta over HTTPS, so media is staged temporarily in Cloudflare R2.",
      "Requires a Meta developer app with the Threads API use case.",
    ],
  },
  instagram: {
    network: "instagram",
    maxChars: 2200,
    maxImages: 10,
    allowsVideo: true,
    allowsMixedMedia: false,
    allowsCarousel: true,
    requiresMedia: true,
    notes: [
      "Requires a professional (Business or Creator) Instagram account linked to a Facebook Page.",
      "Media must be reachable by Meta over HTTPS, so media is staged temporarily in Cloudflare R2.",
      "Personal Instagram accounts cannot be published to via the API.",
    ],
  },
};

export const MEDIA_LIMITS = {
  image: {
    mimeTypes: ["image/jpeg", "image/png", "image/webp", "image/gif"],
    maxBytes: 10 * 1024 * 1024,
  },
  video: {
    mimeTypes: ["video/mp4", "video/quicktime", "video/webm"],
    maxBytes: 512 * 1024 * 1024,
    maxDurationSeconds: 600,
  },
  /** Hard upload cap enforced by the media endpoint regardless of provider. */
  uploadMaxBytes: 512 * 1024 * 1024,
} as const;

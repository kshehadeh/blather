/**
 * Shared types safe to import from client components.
 * No secrets may appear in any of these shapes.
 */

export const NETWORKS = ["x", "bluesky", "threads", "instagram"] as const;
export type Network = (typeof NETWORKS)[number];

export const NETWORK_LABELS: Record<Network, string> = {
  x: "X",
  bluesky: "Bluesky",
  threads: "Threads",
  instagram: "Instagram",
};

export type MediaKind = "image" | "video";

export interface MediaItem {
  id: string;
  kind: MediaKind;
  mimeType: string;
  /** Original filename */
  name: string;
  /** Size in bytes */
  size: number;
  width?: number;
  height?: number;
  durationSeconds?: number;
  /** Server-local path is never sent to the client; use /api/media/[id] to view. */
  createdAt: string;
}

/** Per-network override of the shared draft content. Absent fields inherit the base. */
export interface NetworkOverride {
  text?: string;
  /** Reordered/filtered media id list; absent means inherit base media. */
  mediaIds?: string[];
}

export interface Draft {
  id: string;
  text: string;
  mediaIds: string[];
  networks: Network[];
  overrides: Partial<Record<Network, NetworkOverride>>;
  createdAt: string;
  updatedAt: string;
}

export type AttemptStatus = "pending" | "publishing" | "success" | "failed";

export interface PublishAttempt {
  id: string;
  draftId: string;
  network: Network;
  status: AttemptStatus;
  /** Provider post id, when the provider returned one. */
  providerPostId?: string;
  /** Canonical URL of the published post, when known. */
  providerPostUrl?: string;
  /** Sanitized, redacted error message safe to display. */
  error?: string;
  createdAt: string;
  updatedAt: string;
}

export type ConnectionState = "disconnected" | "connected" | "error";

export interface ConnectionInfo {
  network: Network;
  state: ConnectionState;
  /** Non-secret account label, e.g. handle or username. */
  accountLabel?: string;
  /** Extra non-secret metadata (e.g. account type). */
  meta?: Record<string, string>;
  /** Sanitized error from the last health check. */
  error?: string;
}

/** What a provider can do, for capability/status cards. */
export interface ProviderCapabilities {
  network: Network;
  maxChars: number;
  maxImages: number;
  /** Optional per-image upload cap when stricter than the shared limit. */
  maxImageBytes?: number;
  /** Oversized images are converted before the provider upload. */
  autoOptimizeImages?: boolean;
  allowsVideo: boolean;
  allowsMixedMedia: boolean;
  allowsCarousel: boolean;
  requiresMedia: boolean;
  notes: string[];
}

export interface R2SettingsView {
  configured: boolean;
  accountId?: string;
  bucket?: string;
  publicUrlStrategy?: "public" | "presigned";
  publicBaseUrl?: string;
  /** Never exposed. */
  hasCredentials: boolean;
}

/** Fully-resolved, per-network content ready for an adapter. */
export interface ResolvedContent {
  text: string;
  media: MediaItem[];
}

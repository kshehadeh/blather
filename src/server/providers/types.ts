import type { Network, ResolvedContent } from "@/lib/types";

/**
 * Typed provider adapter contract. One adapter per network; the orchestrator
 * only ever talks to this interface. Adapters must never log or return raw
 * secrets, and must normalize provider errors via normalizeError.
 */

export interface PublishResult {
  providerPostId?: string;
  providerPostUrl?: string;
}

export interface HealthResult {
  ok: boolean;
  accountLabel?: string;
  meta?: Record<string, string>;
  error?: string;
}

export interface PublishContext {
  /** R2 stager for networks that need publicly reachable media URLs. */
  stageMedia(mediaId: string, attemptId: string | null): Promise<{ key: string; url: string }>;
  attemptId: string;
}

export interface ProviderAdapter {
  readonly network: Network;

  /** True when stored credentials exist and look usable. */
  isConnected(): boolean;

  /** Refresh expiring OAuth tokens server-side; no-op for app-password auth. */
  refreshIfNeeded(): Promise<void>;

  /** Pre-publish validation of fully resolved content. Throws ProviderError. */
  validate(content: ResolvedContent): void;

  /** Publish already-validated content. Returns provider IDs/URLs. */
  publish(content: ResolvedContent, ctx: PublishContext): Promise<PublishResult>;

  /** Convert any thrown value into a sanitized, redacted message. */
  normalizeError(err: unknown): string;

  /** Best-effort connection health check (may hit the provider). */
  health(): Promise<HealthResult>;
}

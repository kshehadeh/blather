import type { NextRequest } from "next/server";
import { runStartupRecovery } from "./publish/recovery";
import { guard, jsonError } from "./security";

type Handler = (req: NextRequest, ctx?: unknown) => Promise<Response> | Response;

/**
 * Wrap an API route handler with loopback + same-origin guards, startup
 * recovery (idempotent), and uniform JSON errors.
 */
export function withGuard(handler: Handler): Handler {
  return async (req: NextRequest, ctx?: unknown) => {
    try {
      guard(req);
      await runStartupRecovery();
      return await handler(req, ctx);
    } catch (err) {
      return jsonError(err);
    }
  };
}

/** The loopback origin this request arrived on (for OAuth redirect URIs). */
export function requestOrigin(req: NextRequest): string {
  const protocol = new URL(req.url).protocol;
  return `${protocol}//${req.headers.get("host")}`;
}

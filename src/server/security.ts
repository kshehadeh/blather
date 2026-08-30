import type { NextRequest } from "next/server";

/**
 * Request guards for the local-only threat model:
 * - Only loopback hosts are served.
 * - Mutating requests must be same-origin (blocks CSRF from other web pages,
 *   including DNS-rebinding attempts to non-loopback hosts).
 */

const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]"]);

export function hostOf(req: NextRequest): string {
  const host = req.headers.get("host") ?? "";
  return host.replace(/:\d+$/, "").toLowerCase();
}

export function isLoopbackHost(host: string): boolean {
  return LOOPBACK_HOSTS.has(host.replace(/:\d+$/, "").toLowerCase());
}

export function assertLoopback(req: NextRequest): void {
  if (!isLoopbackHost(req.headers.get("host") ?? "")) {
    throw new HttpError(403, "Blather only serves loopback requests");
  }
}

export function assertSameOrigin(req: NextRequest): void {
  const method = req.method.toUpperCase();
  if (method === "GET" || method === "HEAD" || method === "OPTIONS") return;
  const fetchSite = req.headers.get("sec-fetch-site");
  if (fetchSite && fetchSite !== "same-origin" && fetchSite !== "none") {
    throw new HttpError(403, "Cross-site request rejected");
  }
  const origin = req.headers.get("origin");
  if (origin) {
    let originHost: string;
    try {
      originHost = new URL(origin).host;
    } catch {
      throw new HttpError(403, "Invalid Origin header");
    }
    if (originHost !== req.headers.get("host")) {
      throw new HttpError(403, "Origin mismatch");
    }
  }
}

export function guard(req: NextRequest): void {
  assertLoopback(req);
  assertSameOrigin(req);
}

export class HttpError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

export function jsonError(err: unknown): Response {
  if (err instanceof HttpError) {
    return Response.json({ error: err.message }, { status: err.status });
  }
  const message = err instanceof Error ? err.message : "Internal error";
  return Response.json({ error: message }, { status: 500 });
}

/* ------------------------------- redaction --------------------------------- */

const SENSITIVE_PATTERNS = [
  /Bearer\s+[A-Za-z0-9._~+/=-]+/gi,
  /"?(access|refresh)_token"?\s*[:=]\s*"?[^"\s,&}]+"?/gi,
  /client_secret["']?\s*[:=]\s*["']?[^"'\s,&}]+/gi,
  /X-Amz-Signature=[0-9a-f]+/gi,
  /X-Amz-Credential=[^&\s]+/gi,
  /appsecret_proof=[0-9a-f]+/gi,
];

/** Redact tokens, secrets and signed URLs from arbitrary text for logs/history. */
export function redact(input: string): string {
  let out = input;
  for (const pattern of SENSITIVE_PATTERNS) {
    out = out.replace(pattern, "[redacted]");
  }
  return out;
}

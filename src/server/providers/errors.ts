import { redact } from "@/server/security";

/**
 * ProviderError carries a sanitized, user-displayable message. Raw provider
 * payloads (which can echo back auth headers or signed URLs) are never stored;
 * only the redacted summary survives into history and logs.
 */

export class ProviderError extends Error {
  constructor(
    public network: string,
    message: string,
    public opts: { retryable?: boolean; status?: number } = {},
  ) {
    super(message);
  }
}

export function sanitizeProviderMessage(network: string, err: unknown): string {
  if (err instanceof ProviderError) return redact(err.message);
  if (err instanceof Error) return redact(`${network}: ${err.message}`);
  return `${network}: unknown error`;
}

/** Extract a short message from a JSON-ish provider error body, then redact. */
export function messageFromBody(body: unknown, fallback: string): string {
  try {
    if (body && typeof body === "object") {
      const b = body as Record<string, unknown>;
      const candidates = [
        (b.error as Record<string, unknown> | undefined)?.message,
        b.detail,
        b.title,
        b.message,
        typeof b.error === "string" ? b.error : undefined,
        Array.isArray(b.errors)
          ? (b.errors[0] as Record<string, unknown> | undefined)?.message
          : undefined,
      ];
      for (const c of candidates) {
        if (typeof c === "string" && c.length > 0) return redact(c);
      }
    }
    if (typeof body === "string" && body.length > 0) return redact(body.slice(0, 300));
  } catch {
    // fall through
  }
  return fallback;
}

/** fetch JSON with error normalization. Never includes request headers in errors. */
export async function fetchJson(
  network: string,
  url: string,
  init: RequestInit,
): Promise<{ status: number; body: unknown }> {
  let res: Response;
  try {
    res = await fetch(url, init);
  } catch (err) {
    throw new ProviderError(network, `${network}: network request failed`, {
      retryable: true,
    });
  }
  let body: unknown = null;
  const text = await res.text();
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  if (!res.ok) {
    throw new ProviderError(network, messageFromBody(body, `${network}: HTTP ${res.status}`), {
      status: res.status,
      retryable: res.status >= 500 || res.status === 429,
    });
  }
  return { status: res.status, body };
}

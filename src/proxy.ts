import { type NextRequest, NextResponse } from "next/server";

const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]"]);

/**
 * Edge proxy: reject non-loopback Host headers everywhere, and reject
 * cross-site mutations on API routes (CSRF protection for the local threat
 * model, including DNS-rebinding style abuse).
 */
export function proxy(req: NextRequest): NextResponse {
  const host = (req.headers.get("host") ?? "").replace(/:\d+$/, "").toLowerCase();
  if (!LOOPBACK_HOSTS.has(host)) {
    return NextResponse.json({ error: "Blather only serves loopback requests" }, { status: 403 });
  }

  const method = req.method.toUpperCase();
  if (method !== "GET" && method !== "HEAD" && method !== "OPTIONS") {
    const fetchSite = req.headers.get("sec-fetch-site");
    if (fetchSite && fetchSite !== "same-origin" && fetchSite !== "none") {
      return NextResponse.json({ error: "Cross-site request rejected" }, { status: 403 });
    }
    const origin = req.headers.get("origin");
    if (origin) {
      let originHost: string;
      try {
        originHost = new URL(origin).host;
      } catch {
        return NextResponse.json({ error: "Invalid Origin header" }, { status: 403 });
      }
      if (originHost !== req.headers.get("host")) {
        return NextResponse.json({ error: "Origin mismatch" }, { status: 403 });
      }
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};

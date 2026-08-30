import { popPendingAppConfig, storeOAuthConnection } from "@/server/connect";
import { requestOrigin, withGuard } from "@/server/http";
import { completeOAuth } from "@/server/oauth";
import { fetchJson } from "@/server/providers/errors";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

export const GET = withGuard(async (req: NextRequest) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error");
  if (error) return done(req, `threads: authorization denied (${error})`);
  if (!code || !state) return done(req, "threads: missing code or state");

  try {
    completeOAuth("threads", state);
    const config = popPendingAppConfig(state);
    if (!config?.clientId || !config.clientSecret) throw new Error("missing app configuration");

    const redirectUri = `${requestOrigin(req)}/api/connect/threads/callback`;

    // Short-lived token
    const shortRes = await fetchJson("threads", "https://graph.threads.net/oauth/access_token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_secret: config.clientSecret,
        grant_type: "authorization_code",
        redirect_uri: redirectUri,
        code,
      }),
    });
    const shortToken = shortRes.body as { access_token: string; user_id?: number };

    // Exchange for a 60-day token
    const longRes = await fetchJson(
      "threads",
      `https://graph.threads.net/access_token?grant_type=th_exchange_token&client_secret=${encodeURIComponent(config.clientSecret)}&access_token=${encodeURIComponent(shortToken.access_token)}`,
      {},
    );
    const longToken = longRes.body as { access_token: string; expires_in?: number };

    const me = await fetchJson(
      "threads",
      `https://graph.threads.net/v1.0/me?fields=id,username&access_token=${encodeURIComponent(longToken.access_token)}`,
      {},
    );
    const user = me.body as { id?: string; username?: string };

    storeOAuthConnection(
      "threads",
      {
        accessToken: longToken.access_token,
        expiresAt: Date.now() + Number(longToken.expires_in ?? 5184000) * 1000,
        meta: {
          clientId: config.clientId,
          clientSecret: config.clientSecret,
          userId: user.id ?? "",
        },
      },
      user.username ? `@${user.username}` : undefined,
      { userId: user.id ?? "" },
    );
    return done(req, null);
  } catch (err) {
    return done(req, err instanceof Error ? err.message : "threads connect failed");
  }
});

function done(req: NextRequest, error: string | null): Response {
  const target = new URL("/settings", requestOrigin(req));
  target.searchParams.set("connected", "threads");
  if (error) target.searchParams.set("error", error);
  return Response.redirect(target, 302);
}

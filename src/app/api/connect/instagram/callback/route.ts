import { popPendingAppConfig, storeOAuthConnection } from "@/server/connect";
import { requestOrigin, withGuard } from "@/server/http";
import { completeOAuth } from "@/server/oauth";
import { fetchJson } from "@/server/providers/errors";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

export const GET = withGuard(async (req: NextRequest) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code")?.replace(/#_$/, "");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error");
  if (error) return done(req, `instagram: authorization denied (${error})`);
  if (!code || !state) return done(req, "instagram: missing code or state");

  try {
    completeOAuth("instagram", state);
    const config = popPendingAppConfig(state);
    if (!config?.clientId || !config.clientSecret) throw new Error("missing app configuration");

    const redirectUri = `${requestOrigin(req)}/api/connect/instagram/callback`;

    // Short-lived token
    const shortRes = await fetchJson("instagram", "https://api.instagram.com/oauth/access_token", {
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
      "instagram",
      `https://graph.instagram.com/access_token?grant_type=ig_exchange_token&client_secret=${encodeURIComponent(config.clientSecret)}&access_token=${encodeURIComponent(shortToken.access_token)}`,
      {},
    );
    const longToken = longRes.body as { access_token: string; expires_in?: number };

    const me = await fetchJson(
      "instagram",
      `https://graph.instagram.com/v21.0/me?fields=user_id,username,account_type&access_token=${encodeURIComponent(longToken.access_token)}`,
      {},
    );
    const user = me.body as { user_id?: string; username?: string; account_type?: string };
    const accountType = user.account_type ?? "unknown";

    storeOAuthConnection(
      "instagram",
      {
        accessToken: longToken.access_token,
        expiresAt: Date.now() + Number(longToken.expires_in ?? 5184000) * 1000,
        meta: {
          clientId: config.clientId,
          clientSecret: config.clientSecret,
          igUserId: user.user_id ?? String(shortToken.user_id ?? ""),
        },
      },
      user.username ? `@${user.username}` : undefined,
      { igUserId: user.user_id ?? "", accountType },
    );
    return done(req, null);
  } catch (err) {
    return done(req, err instanceof Error ? err.message : "instagram connect failed");
  }
});

function done(req: NextRequest, error: string | null): Response {
  const target = new URL("/settings", requestOrigin(req));
  target.searchParams.set("connected", "instagram");
  if (error) target.searchParams.set("error", error);
  return Response.redirect(target, 302);
}

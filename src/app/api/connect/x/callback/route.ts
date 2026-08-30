import { popPendingAppConfig, storeOAuthConnection } from "@/server/connect";
import { requestOrigin, withGuard } from "@/server/http";
import { completeOAuth } from "@/server/oauth";
import { oauthResultPage } from "@/server/oauth-result";
import { fetchJson } from "@/server/providers/errors";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

export const GET = withGuard(async (req: NextRequest) => {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error");
  if (error) return redirectWithStatus(req, `x: authorization denied (${error})`);
  if (!code || !state) return redirectWithStatus(req, "x: missing code or state");

  try {
    const { verifier } = completeOAuth("x", state);
    const config = popPendingAppConfig(state);
    if (!config?.clientId) throw new Error("missing app configuration");

    const redirectUri = `${requestOrigin(req)}/api/connect/x/callback`;
    const tokenRes = await fetchJson("x", "https://api.x.com/2/oauth2/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: redirectUri,
        code_verifier: verifier,
        client_id: config.clientId,
      }),
    });
    const tokens = tokenRes.body as {
      access_token: string;
      refresh_token?: string;
      expires_in?: number;
    };

    const me = await fetchJson("x", "https://api.x.com/2/users/me", {
      headers: { Authorization: `Bearer ${tokens.access_token}` },
    });
    const user = (me.body as { data?: { id?: string; username?: string } }).data;

    storeOAuthConnection(
      "x",
      {
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token,
        expiresAt: Date.now() + Number(tokens.expires_in ?? 7200) * 1000,
        meta: { clientId: config.clientId, userId: user?.id ?? "", username: user?.username ?? "" },
      },
      user?.username ? `@${user.username}` : undefined,
      { userId: user?.id ?? "" },
    );
    return redirectWithStatus(req, null);
  } catch (err) {
    return redirectWithStatus(req, err instanceof Error ? err.message : "x connect failed");
  }
});

function redirectWithStatus(_req: NextRequest, error: string | null): Response {
  return oauthResultPage("X", error);
}

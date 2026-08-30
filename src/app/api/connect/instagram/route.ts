import { stashPendingAppConfig } from "@/server/connect";
import { oauthStatesRepo } from "@/server/db/repositories";
import { requestOrigin, withGuard } from "@/server/http";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

/**
 * Start Instagram OAuth (Instagram Business Login) with the user's own Meta
 * app. The connected account must be a professional (Business/Creator)
 * account; the health check reports this restriction clearly.
 */
export const POST = withGuard(async (req: NextRequest) => {
  const body = (await req.json()) as { clientId?: string; clientSecret?: string };
  if (!body.clientId || !body.clientSecret) {
    return Response.json({ error: "clientId and clientSecret required" }, { status: 400 });
  }

  const state = crypto.randomUUID();
  oauthStatesRepo().create("instagram", state, "pkce-not-used");
  stashPendingAppConfig(state, { clientId: body.clientId, clientSecret: body.clientSecret });

  const redirectUri = `${requestOrigin(req)}/api/connect/instagram/callback`;
  const url = new URL("https://www.instagram.com/oauth/authorize");
  url.searchParams.set("client_id", body.clientId);
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("scope", "instagram_business_basic,instagram_business_content_publish");
  url.searchParams.set("response_type", "code");
  url.searchParams.set("state", state);

  return Response.json({ url: url.toString() });
});

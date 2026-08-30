import { stashPendingAppConfig } from "@/server/connect";
import { oauthStatesRepo } from "@/server/db/repositories";
import { withGuard } from "@/server/http";
import { requestOrigin } from "@/server/http";
import { generatePkce } from "@/server/oauth";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

/**
 * Start X OAuth 2.0 PKCE. The user supplies their own developer app's client
 * id. Returns the authorize URL; the browser navigates there.
 */
export const POST = withGuard(async (req: NextRequest) => {
  const body = (await req.json()) as { clientId?: string };
  if (!body.clientId) return Response.json({ error: "clientId required" }, { status: 400 });

  const { verifier, challenge } = generatePkce();
  const state = crypto.randomUUID();
  oauthStatesRepo().create("x", state, verifier);
  stashPendingAppConfig(state, { clientId: body.clientId });

  const redirectUri = `${requestOrigin(req)}/api/connect/x/callback`;
  const url = new URL("https://x.com/i/oauth2/authorize");
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", body.clientId);
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("scope", "tweet.read tweet.write users.read offline.access media.write");
  url.searchParams.set("state", state);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");

  return Response.json({ url: url.toString() });
});

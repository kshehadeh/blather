import { storeBasicConnection } from "@/server/connect";
import { withGuard } from "@/server/http";
import { createBlueskySession } from "@/server/providers/bluesky";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

/**
 * Connect Bluesky with handle + app password against the account's PDS.
 * Session tokens are established immediately and stored in Keychain.
 */
export const POST = withGuard(async (req: NextRequest) => {
  const body = (await req.json()) as { pds?: string; handle?: string; appPassword?: string };
  if (!body.handle || !body.appPassword) {
    return Response.json({ error: "handle and appPassword required" }, { status: 400 });
  }
  const pds = (body.pds || "https://bsky.social").replace(/\/$/, "");

  try {
    const session = await createBlueskySession(pds, body.handle, body.appPassword);
    storeBasicConnection(
      "bluesky",
      {
        identifier: body.handle,
        secret: body.appPassword,
        meta: { pds, did: session.did },
        accessJwt: session.accessJwt,
        refreshJwt: session.refreshJwt,
      },
      `@${session.handle}`,
      { pds, did: session.did },
    );
    return Response.json({ ok: true, account: `@${session.handle}` });
  } catch (err) {
    return Response.json(
      { error: err instanceof Error ? err.message : "bluesky connect failed" },
      { status: 400 },
    );
  }
});

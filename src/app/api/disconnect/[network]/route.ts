import { NETWORKS, type Network } from "@/lib/types";
import { disconnect } from "@/server/connect";
import { withGuard } from "@/server/http";
import { HttpError } from "@/server/security";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

type Ctx = { params: Promise<{ network: string }> };

export const POST = withGuard(async (_req: NextRequest, ctx) => {
  const { network } = await (ctx as Ctx).params;
  if (!(NETWORKS as readonly string[]).includes(network)) {
    throw new HttpError(404, "Unknown network");
  }
  disconnect(network as Network);
  return Response.json({ ok: true });
});

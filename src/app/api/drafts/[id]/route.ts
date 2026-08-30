import { type Draft, NETWORKS, type Network } from "@/lib/types";
import { draftsRepo } from "@/server/db/repositories";
import { withGuard } from "@/server/http";
import { HttpError } from "@/server/security";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

type Ctx = { params: Promise<{ id: string }> };

export const GET = withGuard(async (_req: NextRequest, ctx) => {
  const { id } = await (ctx as Ctx).params;
  const draft = draftsRepo().get(id);
  if (!draft) throw new HttpError(404, "Draft not found");
  return Response.json({ draft });
});

export const PUT = withGuard(async (req: NextRequest, ctx) => {
  const { id } = await (ctx as Ctx).params;
  const body = (await req.json()) as Partial<Draft>;
  const update: Partial<Pick<Draft, "text" | "mediaIds" | "networks" | "overrides">> = {};
  if (body.text !== undefined) update.text = body.text;
  if (body.mediaIds !== undefined) update.mediaIds = body.mediaIds;
  if (body.overrides !== undefined) update.overrides = body.overrides;
  if (body.networks !== undefined) {
    update.networks = body.networks.filter((n): n is Network =>
      (NETWORKS as readonly string[]).includes(n),
    );
  }
  const draft = draftsRepo().update(id, update);
  if (!draft) throw new HttpError(404, "Draft not found");
  return Response.json({ draft });
});

export const DELETE = withGuard(async (_req: NextRequest, ctx) => {
  const { id } = await (ctx as Ctx).params;
  draftsRepo().remove(id);
  return Response.json({ ok: true });
});

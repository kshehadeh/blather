import { type Draft, NETWORKS, type Network } from "@/lib/types";
import { draftsRepo } from "@/server/db/repositories";
import { withGuard } from "@/server/http";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

export const GET = withGuard(async () => {
  return Response.json({ drafts: draftsRepo().list() });
});

export const POST = withGuard(async (req: NextRequest) => {
  const body = (await req.json()) as Partial<Draft>;
  const networks = (body.networks ?? []).filter((n): n is Network =>
    (NETWORKS as readonly string[]).includes(n),
  );
  const draft = draftsRepo().create({
    text: body.text ?? "",
    mediaIds: body.mediaIds ?? [],
    networks,
    overrides: body.overrides ?? {},
  });
  return Response.json({ draft }, { status: 201 });
});

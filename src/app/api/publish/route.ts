import { withGuard } from "@/server/http";
import { publishDraft } from "@/server/publish/orchestrator";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

export const POST = withGuard(async (req: NextRequest) => {
  const body = (await req.json()) as { draftId?: string };
  if (!body.draftId) return Response.json({ error: "draftId required" }, { status: 400 });
  const attempts = await publishDraft(body.draftId);
  return Response.json({ attempts });
});

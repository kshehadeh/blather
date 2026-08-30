import { withGuard } from "@/server/http";
import { retryAttempt } from "@/server/publish/orchestrator";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

type Ctx = { params: Promise<{ id: string }> };

export const POST = withGuard(async (_req: NextRequest, ctx) => {
  const { id } = await (ctx as Ctx).params;
  const attempt = await retryAttempt(id);
  return Response.json({ attempt });
});

import { createReadStream } from "node:fs";
import { join } from "node:path";
import { Readable } from "node:stream";
import { mediaRepo } from "@/server/db/repositories";
import { mediaDir } from "@/server/env";
import { withGuard } from "@/server/http";
import { deleteMedia } from "@/server/media";
import { HttpError } from "@/server/security";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

type Ctx = { params: Promise<{ id: string }> };

export const GET = withGuard(async (_req: NextRequest, ctx) => {
  const { id } = await (ctx as Ctx).params;
  const repo = mediaRepo();
  const item = repo.get(id);
  const rel = repo.pathOf(id);
  if (!item || !rel) throw new HttpError(404, "Media not found");
  const stream = Readable.toWeb(createReadStream(join(mediaDir(), rel))) as ReadableStream;
  return new Response(stream, {
    headers: {
      "Content-Type": item.mimeType,
      "Content-Length": String(item.size),
      "Cache-Control": "private, max-age=3600",
    },
  });
});

export const DELETE = withGuard(async (_req: NextRequest, ctx) => {
  const { id } = await (ctx as Ctx).params;
  await deleteMedia(id);
  return Response.json({ ok: true });
});

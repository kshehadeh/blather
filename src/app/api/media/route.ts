import { mediaRepo } from "@/server/db/repositories";
import { withGuard } from "@/server/http";
import { saveUpload } from "@/server/media";
import { HttpError } from "@/server/security";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

/** Metadata for a set of media ids: GET /api/media?ids=a,b,c */
export const GET = withGuard(async (req: NextRequest) => {
  const ids = (new URL(req.url).searchParams.get("ids") ?? "").split(",").filter(Boolean);
  return Response.json({ media: mediaRepo().byIds(ids) });
});

export const POST = withGuard(async (req: NextRequest) => {
  const form = await req.formData();
  const file = form.get("file");
  if (!(file instanceof File)) throw new HttpError(400, "file field required");
  const item = await saveUpload(file);
  return Response.json({ media: item }, { status: 201 });
});

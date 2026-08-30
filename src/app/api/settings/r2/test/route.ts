import { withGuard } from "@/server/http";
import { getStager } from "@/server/r2";

export const runtime = "nodejs";

export const POST = withGuard(async () => {
  try {
    const stager = getStager();
    await stager.testConnection();
    return Response.json({ ok: true, bucket: stager.bucket() });
  } catch (err) {
    const message = err instanceof Error ? err.message : "R2 test failed";
    return Response.json({ ok: false, error: message }, { status: 400 });
  }
});

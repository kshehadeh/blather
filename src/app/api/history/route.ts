import { attemptsRepo } from "@/server/db/repositories";
import { withGuard } from "@/server/http";

export const runtime = "nodejs";

export const GET = withGuard(async () => {
  return Response.json({ attempts: attemptsRepo().list() });
});

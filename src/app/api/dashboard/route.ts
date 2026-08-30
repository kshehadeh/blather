import type { ConnectionInfo, RecentPost } from "@/lib/types";
import { attemptsRepo, connectionsRepo } from "@/server/db/repositories";
import { withGuard } from "@/server/http";

export const runtime = "nodejs";

export const GET = withGuard(async () => {
  const posts = new Map<string, RecentPost>();
  for (const attempt of attemptsRepo().list()) {
    const post = posts.get(attempt.draftId);
    if (post) {
      post.attempts.push(attempt);
    } else if (posts.size < 5) {
      posts.set(attempt.draftId, {
        draftId: attempt.draftId,
        text: attempt.textSnapshot,
        createdAt: attempt.createdAt,
        attempts: [attempt],
      });
    }
  }

  const platforms = connectionsRepo()
    .list()
    .filter((connection) => connection.state !== "disconnected")
    .map(stripRef);

  return Response.json({ posts: [...posts.values()], platforms });
});

function stripRef(connection: ConnectionInfo & { credentialRef?: string }): ConnectionInfo {
  const { credentialRef: _omit, ...safeConnection } = connection;
  void _omit;
  return safeConnection;
}

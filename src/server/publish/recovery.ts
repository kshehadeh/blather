import { attemptsRepo } from "@/server/db/repositories";
import { log } from "@/server/log";
import { cleanupOrphanedStaged } from "@/server/r2";

let ran = false;

/**
 * Startup recovery:
 * 1. Attempts left in `publishing` by a process exit are marked failed with a
 *    clear message (providers are not idempotent, so we do not auto-retry).
 * 2. Staged R2 objects older than the cleanup window are removed best-effort.
 */
export async function runStartupRecovery(): Promise<void> {
  if (ran) return;
  ran = true;

  const attempts = attemptsRepo();
  const stuck = attempts.stuckPublishing();
  for (const attempt of stuck) {
    attempts.setStatus(attempt.id, "failed", {
      error: "interrupted: the app stopped while publishing; review and retry if needed",
    });
  }
  if (stuck.length > 0) {
    log.warn(`Recovered ${stuck.length} interrupted publish attempt(s)`);
  }

  try {
    const removed = await cleanupOrphanedStaged();
    if (removed > 0) log.info(`Cleaned up ${removed} orphaned staged object(s)`);
  } catch (err) {
    log.warn("Staged-media cleanup failed:", err);
  }
}

/** Test hook. */
export function __resetRecoveryForTests(): void {
  ran = false;
}

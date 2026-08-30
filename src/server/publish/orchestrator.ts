import type { Draft, MediaItem, Network, PublishAttempt } from "@/lib/types";
import { attemptsRepo, draftsRepo, mediaRepo } from "@/server/db/repositories";
import { adapterFor } from "@/server/providers";
import type { PublishContext } from "@/server/providers/types";
import { getStager } from "@/server/r2";
import { resolveContent } from "./overrides";

const CONCURRENCY = 3;

function makeContext(attemptId: string): PublishContext {
  return {
    attemptId,
    stageMedia: (mediaId, attId) => getStager().stage(mediaId, attId ?? attemptId),
  };
}

async function runAttempt(
  attempt: PublishAttempt,
  draft: Pick<Draft, "text" | "mediaIds" | "overrides">,
  mediaById: Map<string, MediaItem>,
): Promise<PublishAttempt> {
  const attempts = attemptsRepo();
  const adapter = adapterFor(attempt.network);
  attempts.setStatus(attempt.id, "publishing");
  try {
    const content = resolveContent(draft, attempt.network, mediaById);
    adapter.validate(content); // before any external write
    const result = await adapter.publish(content, makeContext(attempt.id));
    attempts.setStatus(attempt.id, "success", {
      providerPostId: result.providerPostId,
      providerPostUrl: result.providerPostUrl,
    });
  } catch (err) {
    attempts.setStatus(attempt.id, "failed", { error: adapter.normalizeError(err) });
  }
  return attempts.get(attempt.id) as PublishAttempt;
}

async function mapWithConcurrency<T, R>(
  items: T[],
  limit: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let index = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (index < items.length) {
      const i = index++;
      results[i] = await fn(items[i]);
    }
  });
  await Promise.all(workers);
  return results;
}

/**
 * Publish a draft to its selected networks. Each network is an independent
 * attempt persisted as it completes, so a partial success never rolls back
 * and retries only re-run failed destinations.
 */
export async function publishDraft(draftId: string): Promise<PublishAttempt[]> {
  const drafts = draftsRepo();
  const draft = drafts.get(draftId);
  if (!draft) throw new Error(`Draft ${draftId} not found`);
  if (draft.networks.length === 0) throw new Error("No networks selected");

  const mediaById = new Map(
    mediaRepo()
      .byIds(allMediaIds(draft))
      .map((m) => [m.id, m]),
  );
  const attempts = attemptsRepo();

  const created = draft.networks.map((network) =>
    attempts.create({ draftId, network, textSnapshot: draft.text }),
  );

  return mapWithConcurrency(created, CONCURRENCY, (attempt) =>
    runAttempt(attempt, draft, mediaById),
  );
}

/**
 * Retry a single failed attempt. Successful attempts are never re-run, which
 * makes duplicate posts from partial success impossible through this path.
 */
export async function retryAttempt(attemptId: string): Promise<PublishAttempt> {
  const attempts = attemptsRepo();
  const attempt = attempts.get(attemptId);
  if (!attempt) throw new Error(`Attempt ${attemptId} not found`);
  if (attempt.status !== "failed") {
    throw new Error("Only failed attempts can be retried");
  }
  const draft = draftsRepo().get(attempt.draftId);
  if (!draft) throw new Error("Draft no longer exists");
  const mediaById = new Map(
    mediaRepo()
      .byIds(allMediaIds(draft))
      .map((m) => [m.id, m]),
  );
  return runAttempt(attempt, draft, mediaById);
}

function allMediaIds(draft: Pick<Draft, "mediaIds" | "overrides">): string[] {
  const ids = new Set<string>(draft.mediaIds);
  for (const o of Object.values(draft.overrides ?? {})) {
    for (const id of o?.mediaIds ?? []) ids.add(id);
  }
  return [...ids];
}

export type { Network };

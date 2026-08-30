import { attemptsRepo, draftsRepo } from "@/server/db/repositories";
import { publishDraft, retryAttempt } from "@/server/publish/orchestrator";
import { __resetRecoveryForTests, runStartupRecovery } from "@/server/publish/recovery";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { setupTestDb } from "../helpers";

// Use mock provider adapters for orchestration tests.
beforeEach(() => {
  process.env.BLATHER_MOCK_PROVIDERS = "1";
});

afterEach(() => {
  delete process.env.BLATHER_MOCK_PROVIDERS;
  delete process.env.BLATHER_MOCK_FAIL;
});

describe("publish orchestrator", () => {
  it("publishes to all selected networks independently", async () => {
    const db = setupTestDb();
    process.env.BLATHER_MOCK_FAIL = "";
    const draft = draftsRepo(db).create({
      text: "ship it",
      mediaIds: [],
      networks: ["x", "bluesky", "threads"],
      overrides: {},
    });
    const attempts = await publishDraft(draft.id);
    expect(attempts).toHaveLength(3);
    expect(attempts.every((a) => a.status === "success")).toBe(true);
    expect(attempts.find((a) => a.network === "x")?.providerPostId).toMatch(/^mock-x-/);
  });

  it("persists partial success: failures isolated per network", async () => {
    const db = setupTestDb();
    process.env.BLATHER_MOCK_FAIL = "threads";
    const draft = draftsRepo(db).create({
      text: "partial",
      mediaIds: [],
      networks: ["x", "threads"],
      overrides: {},
    });
    const attempts = await publishDraft(draft.id);
    const byNet = Object.fromEntries(attempts.map((a) => [a.network, a]));
    expect(byNet.x.status).toBe("success");
    expect(byNet.threads.status).toBe("failed");
    expect(byNet.threads.error).toContain("mock threads publish failure");

    // Persisted to history as they completed
    const stored = attemptsRepo(db).forDraft(draft.id);
    expect(stored.find((a) => a.network === "x")?.status).toBe("success");
  });

  it("retries only failed attempts and never duplicates successes", async () => {
    const db = setupTestDb();
    process.env.BLATHER_MOCK_FAIL = "threads";
    const draft = draftsRepo(db).create({
      text: "retry me",
      mediaIds: [],
      networks: ["x", "threads"],
      overrides: {},
    });
    const attempts = await publishDraft(draft.id);
    const ok = attempts.find((a) => a.network === "x");
    const bad = attempts.find((a) => a.network === "threads");

    // Successful attempts cannot be retried.
    await expect(retryAttempt(ok?.id as string)).rejects.toThrow(/Only failed/);

    // Fix the provider, retry the failed one.
    process.env.BLATHER_MOCK_FAIL = "";
    const retried = await retryAttempt(bad?.id as string);
    expect(retried.status).toBe("success");

    // Still exactly one attempt per network: no duplicates.
    const stored = attemptsRepo(db).forDraft(draft.id);
    expect(stored).toHaveLength(2);
    expect(stored.every((a) => a.status === "success")).toBe(true);
  });

  it("fails validation before any external write", async () => {
    const db = setupTestDb();
    process.env.BLATHER_MOCK_FAIL = "";
    const draft = draftsRepo(db).create({
      text: "y".repeat(300), // over X's 280 limit, fine for others
      mediaIds: [],
      networks: ["x", "bluesky"],
      overrides: {},
    });
    const attempts = await publishDraft(draft.id);
    const x = attempts.find((a) => a.network === "x");
    expect(x?.status).toBe("failed");
    expect(x?.error).toMatch(/280/);
    expect(x?.providerPostId).toBeUndefined();
  });

  it("marks interrupted attempts failed on startup recovery", async () => {
    const db = setupTestDb();
    const attempts = attemptsRepo(db);
    const stuck = attempts.create({ draftId: "d", network: "x" });
    attempts.setStatus(stuck.id, "publishing");

    __resetRecoveryForTests();
    await runStartupRecovery();
    const after = attempts.get(stuck.id);
    expect(after?.status).toBe("failed");
    expect(after?.error).toMatch(/interrupted/);
  });
});

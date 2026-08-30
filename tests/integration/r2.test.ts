import { mediaRepo, stagedRepo } from "@/server/db/repositories";
import { __setStagerForTests, cleanupOrphanedStaged, getStager } from "@/server/r2";
import { afterEach, describe, expect, it } from "vitest";
import { seedFakeR2, setupTestDb } from "../helpers";

afterEach(() => __setStagerForTests(null));

describe("R2 staging", () => {
  it("stages media and produces a fetchable URL", async () => {
    const db = setupTestDb();
    const stager = seedFakeR2(db);
    const item = mediaRepo(db).create({
      kind: "image",
      mimeType: "image/png",
      name: "stage me.png",
      size: 5,
      path: "stage.png",
    });
    const staged = await getStager().stage(item.id, "att-1");
    expect(staged.url).toContain("https://cdn.fake.local/");
    expect(stager.objects.has(staged.key)).toBe(true);
    expect(stagedRepo(db).forAttempt("att-1")).toHaveLength(1);
  });

  it("sweeps staged objects older than the cleanup window", async () => {
    const db = setupTestDb();
    const stager = seedFakeR2(db);
    const item = mediaRepo(db).create({
      kind: "image",
      mimeType: "image/png",
      name: "old.png",
      size: 5,
      path: "old.png",
    });
    const staged = await getStager().stage(item.id, null);

    // Fresh objects survive cleanup.
    expect(await cleanupOrphanedStaged()).toBe(0);
    expect(stager.objects.has(staged.key)).toBe(true);

    // Age the row beyond the window and sweep again.
    db.prepare("UPDATE staged_objects SET created_at = ?").run(
      new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString(),
    );
    expect(await cleanupOrphanedStaged()).toBe(1);
    expect(stager.objects.has(staged.key)).toBe(false);
    expect(stagedRepo(db).olderThan("9999")).toHaveLength(0);
  });

  it("throws a clear error when staging is not configured", () => {
    setupTestDb();
    __setStagerForTests(null);
    expect(() => getStager()).toThrow(/not configured/);
  });
});

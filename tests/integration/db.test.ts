import {
  attemptsRepo,
  connectionsRepo,
  draftsRepo,
  mediaRepo,
  oauthStatesRepo,
  stagedRepo,
} from "@/server/db/repositories";
import { describe, expect, it } from "vitest";
import { setupTestDb } from "../helpers";

describe("SQLite repositories", () => {
  it("creates, updates, lists and deletes drafts", () => {
    const db = setupTestDb();
    const repo = draftsRepo(db);
    const draft = repo.create({
      text: "hello",
      mediaIds: ["m1"],
      networks: ["x", "bluesky"],
      overrides: { x: { text: "x version" } },
    });
    expect(repo.get(draft.id)?.text).toBe("hello");

    const updated = repo.update(draft.id, { text: "edited" });
    expect(updated?.text).toBe("edited");
    expect(repo.get(draft.id)?.overrides.x?.text).toBe("x version");

    expect(repo.list().map((d) => d.id)).toContain(draft.id);
    repo.remove(draft.id);
    expect(repo.get(draft.id)).toBeNull();
  });

  it("persists attempt lifecycle independently per network", () => {
    const db = setupTestDb();
    const attempts = attemptsRepo(db);
    const a = attempts.create({ draftId: "d1", network: "x" });
    const b = attempts.create({ draftId: "d1", network: "bluesky" });

    attempts.setStatus(a.id, "publishing");
    attempts.setStatus(a.id, "success", {
      providerPostId: "px",
      providerPostUrl: "https://x.com/u/status/px",
    });
    attempts.setStatus(b.id, "failed", { error: "boom" });

    const gotA = attempts.get(a.id);
    const gotB = attempts.get(b.id);
    expect(gotA?.status).toBe("success");
    expect(gotA?.providerPostId).toBe("px");
    expect(gotB?.status).toBe("failed");
    expect(gotB?.error).toBe("boom");
    expect(attempts.forDraft("d1")).toHaveLength(2);
  });

  it("tracks stuck publishing attempts for recovery", () => {
    const db = setupTestDb();
    const attempts = attemptsRepo(db);
    const a = attempts.create({ draftId: "d1", network: "x" });
    attempts.setStatus(a.id, "publishing");
    attempts.create({ draftId: "d1", network: "threads" });
    expect(attempts.stuckPublishing().map((x) => x.id)).toEqual([a.id]);
  });

  it("stores connections with opaque credential refs only", () => {
    const db = setupTestDb();
    const repo = connectionsRepo(db);
    repo.upsert({
      network: "x",
      state: "connected",
      credentialRef: "oauth.x.abc",
      accountLabel: "@u",
    });
    const row = db.prepare("SELECT * FROM connections WHERE network = 'x'").get() as Record<
      string,
      unknown
    >;
    expect(row.credential_ref).toBe("oauth.x.abc");
    expect(JSON.stringify(row)).not.toContain("access_token");
  });

  it("stores media metadata and resolves ids in order", () => {
    const db = setupTestDb();
    const repo = mediaRepo(db);
    const m1 = repo.create({
      kind: "image",
      mimeType: "image/png",
      name: "1.png",
      size: 1,
      path: "1.png",
    });
    const m2 = repo.create({
      kind: "video",
      mimeType: "video/mp4",
      name: "2.mp4",
      size: 2,
      path: "2.mp4",
    });
    const resolved = repo.byIds([m2.id, m1.id, "missing"]);
    expect(resolved.map((m) => m.id)).toEqual([m2.id, m1.id]);
    expect(repo.pathOf(m1.id)).toBe("1.png");
  });

  it("oauth states are single-use and expire", () => {
    const db = setupTestDb();
    const repo = oauthStatesRepo(db);
    repo.create("x", "state-1", "verifier-1");
    expect(repo.consume("x", "state-1")).toEqual({ verifier: "verifier-1" });
    expect(repo.consume("x", "state-1")).toBeNull(); // single-use
    expect(repo.consume("x", "never-created")).toBeNull();

    repo.create("x", "state-2", "v", -1000); // already expired
    expect(repo.consume("x", "state-2")).toBeNull();
  });

  it("tracks staged objects by attempt and age", () => {
    const db = setupTestDb();
    const repo = stagedRepo(db);
    const id = repo.add("att-1", "bucket", "key-1");
    repo.add(null, "bucket", "key-2");
    expect(repo.forAttempt("att-1").map((o) => o.key)).toEqual(["key-1"]);
    expect(repo.olderThan(new Date(Date.now() + 1000).toISOString())).toHaveLength(2);
    repo.remove(id);
    expect(repo.forAttempt("att-1")).toHaveLength(0);
  });
});

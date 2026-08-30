import { beginOAuth, completeOAuth, generatePkce } from "@/server/oauth";
import { describe, expect, it } from "vitest";
import { setupTestDb } from "../helpers";

describe("OAuth state/PKCE", () => {
  it("generates valid PKCE pairs", () => {
    const { verifier, challenge } = generatePkce();
    expect(verifier.length).toBeGreaterThan(30);
    expect(challenge).not.toBe(verifier);
    // challenge is base64url sha256 of verifier
    const { createHash } = require("node:crypto") as typeof import("node:crypto");
    expect(challenge).toBe(createHash("sha256").update(verifier).digest("base64url"));
  });

  it("completes a flow exactly once", () => {
    setupTestDb();
    const { state } = beginOAuth("x");
    const first = completeOAuth("x", state);
    expect(first.verifier).toBeTruthy();
    expect(() => completeOAuth("x", state)).toThrow(/Invalid or expired/);
  });

  it("rejects state from the wrong provider", () => {
    setupTestDb();
    const { state } = beginOAuth("threads");
    expect(() => completeOAuth("instagram", state)).toThrow();
  });

  it("rejects unknown state (CSRF protection)", () => {
    setupTestDb();
    expect(() => completeOAuth("x", "attacker-supplied-state")).toThrow(/Invalid or expired/);
  });
});

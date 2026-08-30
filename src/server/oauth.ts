import { createHash, randomBytes } from "node:crypto";
import { oauthStatesRepo } from "./db/repositories";

/** PKCE + CSRF-state helpers for OAuth authorization-code flows. */

export function generatePkce(): { verifier: string; challenge: string } {
  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  return { verifier, challenge };
}

export function generateState(): string {
  return randomBytes(24).toString("base64url");
}

/** Persist a single-use state (+ optional PKCE verifier) for a provider. */
export function beginOAuth(provider: string): { state: string; verifier: string | null } {
  const state = generateState();
  const { verifier } = generatePkce();
  oauthStatesRepo().create(provider, state, verifier);
  return { state, verifier };
}

/** Verify state (CSRF protection) and retrieve the PKCE verifier. Single-use. */
export function completeOAuth(provider: string, state: string): { verifier: string } {
  const record = oauthStatesRepo().consume(provider, state);
  if (!record) throw new Error("Invalid or expired OAuth state");
  if (!record.verifier) throw new Error("Missing PKCE verifier");
  return { verifier: record.verifier };
}

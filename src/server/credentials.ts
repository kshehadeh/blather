import { newId } from "./db";
import { keychain } from "./keychain";

/**
 * Credential references: SQLite rows only store an opaque ref string; this
 * module resolves refs to secret material held in Keychain. Secret shapes are
 * JSON blobs so each provider can evolve its own token set.
 */

export interface OAuthTokens {
  accessToken: string;
  refreshToken?: string;
  /** epoch milliseconds when accessToken expires */
  expiresAt?: number;
  /** non-secret extras, e.g. X user id, Meta user id */
  meta?: Record<string, string>;
}

export interface BasicCredentials {
  identifier: string;
  secret: string;
  /** non-secret extras, e.g. Bluesky PDS URL, DID */
  meta?: Record<string, string>;
  /** session tokens (Bluesky), refreshed lazily */
  accessJwt?: string;
  refreshJwt?: string;
}

export function makeCredentialRef(kind: "oauth" | "basic" | "r2", owner: string): string {
  return `${kind}.${owner}.${newId()}`;
}

export function storeSecret<T>(ref: string, value: T): void {
  keychain().set(ref, JSON.stringify(value));
}

export function readSecret<T>(ref: string | undefined | null): T | null {
  if (!ref) return null;
  const raw = keychain().get(ref);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export function deleteSecret(ref: string | undefined | null): void {
  if (ref) keychain().remove(ref);
}

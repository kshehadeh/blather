import type { Network } from "@/lib/types";
import {
  type BasicCredentials,
  type OAuthTokens,
  deleteSecret,
  makeCredentialRef,
  storeSecret,
} from "./credentials";
import { connectionsRepo } from "./db/repositories";
import { keychain } from "./keychain";

/** Shared helpers for connect flows. */

export function storeOAuthConnection(
  network: Network,
  tokens: OAuthTokens,
  accountLabel?: string,
  meta: Record<string, string> = {},
): void {
  const conn = connectionsRepo().get(network);
  if (conn.credentialRef) deleteSecret(conn.credentialRef);
  const ref = makeCredentialRef("oauth", network);
  storeSecret(ref, tokens);
  connectionsRepo().upsert({
    network,
    state: "connected",
    credentialRef: ref,
    accountLabel: accountLabel ?? null,
    meta,
    error: null,
  });
}

export function storeBasicConnection(
  network: Network,
  creds: BasicCredentials,
  accountLabel: string,
  meta: Record<string, string> = {},
): void {
  const conn = connectionsRepo().get(network);
  if (conn.credentialRef) deleteSecret(conn.credentialRef);
  const ref = makeCredentialRef("basic", network);
  storeSecret(ref, creds);
  connectionsRepo().upsert({
    network,
    state: "connected",
    credentialRef: ref,
    accountLabel,
    meta,
    error: null,
  });
}

export function markConnectionError(network: Network, error: string): void {
  connectionsRepo().upsert({ network, state: "error", error });
}

export function disconnect(network: Network): void {
  const conn = connectionsRepo().get(network);
  if (conn.credentialRef) deleteSecret(conn.credentialRef);
  connectionsRepo().clear(network);
}

/** Pending OAuth app config, kept in Keychain (never SQLite) during the flow. */
export function stashPendingAppConfig(state: string, config: Record<string, string>): string {
  const ref = `pending.${state}`;
  storeSecret(ref, config);
  return ref;
}

export function popPendingAppConfig(state: string): Record<string, string> | null {
  const ref = `pending.${state}`;
  const raw = keychain().get(ref);
  keychain().remove(ref);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as Record<string, string>;
  } catch {
    return null;
  }
}

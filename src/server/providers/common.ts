import { createReadStream } from "node:fs";
import { join } from "node:path";
import type { Network } from "@/lib/types";
import { type OAuthTokens, readSecret, storeSecret } from "@/server/credentials";
import { connectionsRepo, mediaRepo } from "@/server/db/repositories";
import { mediaDir } from "@/server/env";
import { ProviderError } from "./errors";

/** Load OAuth tokens for a network from Keychain via the connection row. */
export function loadTokens(network: Network): OAuthTokens | null {
  const conn = connectionsRepo().get(network);
  return readSecret<OAuthTokens>(conn.credentialRef);
}

export function saveTokens(network: Network, tokens: OAuthTokens): void {
  const conn = connectionsRepo().get(network);
  if (!conn.credentialRef) {
    throw new ProviderError(network, `${network}: no credential reference stored`);
  }
  storeSecret(conn.credentialRef, tokens);
}

export function requireTokens(network: Network): OAuthTokens {
  const tokens = loadTokens(network);
  if (!tokens?.accessToken) throw new ProviderError(network, `${network}: not connected`);
  return tokens;
}

export function tokenExpiringSoon(tokens: OAuthTokens, skewMs = 5 * 60 * 1000): boolean {
  if (!tokens.expiresAt) return false;
  return tokens.expiresAt - Date.now() < skewMs;
}

/** Absolute path for a media item (server-only). */
export function mediaPath(mediaId: string): string {
  const rel = mediaRepo().pathOf(mediaId);
  if (!rel) throw new Error(`Media ${mediaId} not found`);
  return join(mediaDir(), rel);
}

/** Stream a file in fixed-size chunks (for chunked upload APIs). */
export async function* chunkFile(path: string, chunkSize: number): AsyncGenerator<Buffer> {
  const stream = createReadStream(path, { highWaterMark: chunkSize });
  let pending: Buffer = Buffer.alloc(0);
  for await (const piece of stream) {
    pending = pending.length === 0 ? (piece as Buffer) : Buffer.concat([pending, piece as Buffer]);
    while (pending.length >= chunkSize) {
      yield pending.subarray(0, chunkSize);
      pending = pending.subarray(chunkSize);
    }
  }
  if (pending.length > 0) yield pending;
}

export function basicAuth(id: string, secret: string): string {
  return `Basic ${Buffer.from(`${id}:${secret}`).toString("base64")}`;
}

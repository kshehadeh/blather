import { chmodSync, existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

/**
 * Local runtime configuration. Only non-secret options come from env vars;
 * all secrets are entered through Settings and stored in Keychain.
 */

let ensured = false;
const DEFAULT_PORT = "3000";

export function dataDir(): string {
  const raw = process.env.BLATHER_DATA_DIR ?? join(homedir(), ".blather");
  const dir = resolve(raw.replace(/^~/, homedir()));
  ensureDataDir(dir);
  return dir;
}

function ensureDataDir(dir: string): void {
  if (ensured && existsSync(dir)) return;
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true, mode: 0o700 });
  // Restrictive permissions: owner only.
  try {
    chmodSync(dir, 0o700);
  } catch {
    // best effort on non-POSIX filesystems
  }
  const media = join(dir, "media");
  if (!existsSync(media)) mkdirSync(media, { recursive: true, mode: 0o700 });
  ensured = true;
}

export function mediaDir(): string {
  return join(dataDir(), "media");
}

export function dbPath(): string {
  return join(dataDir(), "blather.db");
}

/** Base URL used for OAuth callbacks. Always loopback. */
export function appBaseUrl(): string {
  const port = process.env.BLATHER_PORT ?? process.env.PORT ?? DEFAULT_PORT;
  return `https://127.0.0.1:${port}`;
}

export function useMemoryKeychain(): boolean {
  return process.env.BLATHER_KEYCHAIN === "memory";
}

export function useFakeR2(): boolean {
  return process.env.BLATHER_R2 === "fake";
}

export function useMockProviders(): boolean {
  return process.env.BLATHER_MOCK_PROVIDERS === "1";
}

/** Test hook for resetting memoization between tests. */
export function __resetEnvForTests(): void {
  ensured = false;
}

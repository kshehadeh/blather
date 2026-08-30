import { execFileSync } from "node:child_process";
import { useMemoryKeychain } from "./env";

/**
 * Credential storage abstraction. The production backend is macOS Keychain via
 * the `security` CLI, under a Blather-specific service name. Tests and e2e use
 * an in-memory backend selected with BLATHER_KEYCHAIN=memory.
 */

export interface KeychainStore {
  set(ref: string, secret: string): void;
  get(ref: string): string | null;
  remove(ref: string): void;
}

const SERVICE_PREFIX = "com.blather";

class MacOSKeychain implements KeychainStore {
  set(ref: string, secret: string): void {
    // -U updates in place when the item already exists.
    execFileSync(
      "security",
      ["add-generic-password", "-U", "-s", `${SERVICE_PREFIX}.${ref}`, "-a", ref, "-w", secret],
      { stdio: ["ignore", "ignore", "pipe"] },
    );
  }

  get(ref: string): string | null {
    try {
      const out = execFileSync(
        "security",
        ["find-generic-password", "-s", `${SERVICE_PREFIX}.${ref}`, "-w"],
        { stdio: ["ignore", "pipe", "ignore"] },
      );
      return out.toString("utf8").replace(/\n$/, "");
    } catch {
      return null;
    }
  }

  remove(ref: string): void {
    try {
      execFileSync("security", ["delete-generic-password", "-s", `${SERVICE_PREFIX}.${ref}`], {
        stdio: ["ignore", "ignore", "ignore"],
      });
    } catch {
      // already gone
    }
  }
}

class MemoryKeychain implements KeychainStore {
  private map = new Map<string, string>();
  set(ref: string, secret: string): void {
    this.map.set(ref, secret);
  }
  get(ref: string): string | null {
    return this.map.get(ref) ?? null;
  }
  remove(ref: string): void {
    this.map.delete(ref);
  }
}

let store: KeychainStore | null = null;

export function keychain(): KeychainStore {
  if (!store) store = useMemoryKeychain() ? new MemoryKeychain() : new MacOSKeychain();
  return store;
}

/** Test hook. */
export function __setKeychainForTests(s: KeychainStore | null): void {
  store = s;
}

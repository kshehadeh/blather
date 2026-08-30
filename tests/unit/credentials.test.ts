import { deleteSecret, makeCredentialRef, readSecret, storeSecret } from "@/server/credentials";
import { __setKeychainForTests, keychain } from "@/server/keychain";
import { describe, expect, it } from "vitest";

// vitest env sets BLATHER_KEYCHAIN=memory

describe("credential references", () => {
  it("generates opaque, unique refs", () => {
    const a = makeCredentialRef("oauth", "x");
    const b = makeCredentialRef("oauth", "x");
    expect(a).not.toBe(b);
    expect(a).toMatch(/^oauth\.x\./);
    expect(a).not.toContain("token");
  });

  it("round-trips secrets via the keychain store", () => {
    const ref = makeCredentialRef("oauth", "x");
    storeSecret(ref, { accessToken: "super-secret-token", meta: { userId: "1" } });
    expect(readSecret<{ accessToken: string }>(ref)?.accessToken).toBe("super-secret-token");
  });

  it("returns null for unknown or missing refs", () => {
    expect(readSecret("nope")).toBeNull();
    expect(readSecret(undefined)).toBeNull();
    expect(readSecret(null)).toBeNull();
  });

  it("deletes secrets", () => {
    const ref = makeCredentialRef("r2", "staging");
    storeSecret(ref, { accessKeyId: "k", secretAccessKey: "s" });
    deleteSecret(ref);
    expect(readSecret(ref)).toBeNull();
  });

  it("returns null for malformed payloads", () => {
    const ref = makeCredentialRef("basic", "bluesky");
    keychain().set(ref, "not-json{");
    expect(readSecret(ref)).toBeNull();
    __setKeychainForTests(null); // reset memoized store
  });
});

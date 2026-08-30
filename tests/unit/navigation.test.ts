import { describe, expect, it } from "vitest";
import { isProviderAuthorizationUrl } from "../../electron/navigation";

describe("provider authorization URL allowlist", () => {
  it.each([
    "https://x.com/i/oauth2/authorize",
    "https://www.instagram.com/oauth/authorize",
    "https://threads.net/oauth/authorize",
    "https://www.threads.net/oauth/authorize",
  ])("accepts known provider URL %s", (url) => {
    expect(isProviderAuthorizationUrl(url)).toBe(true);
  });

  it.each([
    "http://x.com/i/oauth2/authorize",
    "https://evil.example/x.com",
    "https://api.x.com/2/users/me",
    "file:///tmp/page.html",
  ])("rejects non-authorization URL %s", (url) => {
    expect(isProviderAuthorizationUrl(url)).toBe(false);
  });
});

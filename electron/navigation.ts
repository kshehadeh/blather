const OAUTH_HOSTS = new Set(["x.com", "www.instagram.com", "threads.net", "www.threads.net"]);

/**
 * Only provider authorization pages may leave Blather's local window.
 * Callbacks stay on the loopback server and are handled in the system browser.
 */
export function isProviderAuthorizationUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && OAUTH_HOSTS.has(url.hostname.toLowerCase());
  } catch {
    return false;
  }
}

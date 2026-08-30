import type { Network } from "@/lib/types";
import { type OAuthTokens, makeCredentialRef, storeSecret } from "@/server/credentials";
import { type DB, __setDbForTests, openDb } from "@/server/db";
import { connectionsRepo, r2Repo } from "@/server/db/repositories";
import { FakeR2Stager, __setStagerForTests } from "@/server/r2";

/** Fresh in-memory DB per test, registered as the process DB. */
export function setupTestDb(): DB {
  const db = openDb(":memory:");
  __setDbForTests(db);
  return db;
}

/** Seed a connected network with OAuth tokens (memory keychain). */
export function seedOAuthConnection(
  db: DB,
  network: Network,
  tokens: Partial<OAuthTokens> = {},
): void {
  const ref = makeCredentialRef("oauth", network);
  storeSecret(ref, {
    accessToken: "test-access-token",
    refreshToken: "test-refresh-token",
    // Far-future expiry so Meta adapters don't attempt refresh mid-test.
    expiresAt: Date.now() + 45 * 24 * 3600_000,
    meta: {
      clientId: "test-client",
      clientSecret: "test-secret",
      userId: "user-1",
      igUserId: "ig-user-1",
      username: "testuser",
    },
    ...tokens,
  });
  connectionsRepo(db).upsert({
    network,
    state: "connected",
    credentialRef: ref,
    accountLabel: "@testuser",
  });
}

/** Seed R2 settings and register a shared fake stager. */
export function seedFakeR2(db: DB): FakeR2Stager {
  r2Repo(db).save({
    accountId: "fake-account-id",
    bucket: "fake-bucket",
    publicUrlStrategy: "public",
    publicBaseUrl: "https://cdn.fake.local",
    credentialRef: makeCredentialRef("r2", "staging"),
  });
  const stager = new FakeR2Stager(r2Repo(db).get() ?? undefined);
  __setStagerForTests(stager);
  return stager;
}

/** Mock fetch with a sequence of {match, response} handlers. */
export interface MockRoute {
  match: (url: string, init?: RequestInit) => boolean;
  respond: (url: string, init?: RequestInit) => { status?: number; body: unknown };
}

export function mockFetch(routes: MockRoute[]): ReturnType<typeof buildMock> {
  return buildMock(routes);
}

function buildMock(routes: MockRoute[]) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const fn = async (input: unknown, init?: RequestInit): Promise<Response> => {
    const url = String(input);
    calls.push({ url, init });
    for (const route of routes) {
      if (route.match(url, init)) {
        const { status = 200, body } = route.respond(url, init);
        if (status === 204 || status === 304) return new Response(null, { status });
        return new Response(typeof body === "string" ? body : JSON.stringify(body), {
          status,
          headers: { "Content-Type": "application/json" },
        });
      }
    }
    return new Response(JSON.stringify({ error: `unmocked: ${url}` }), { status: 500 });
  };
  return Object.assign(fn, { calls });
}

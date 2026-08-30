import type { Network, ResolvedContent } from "@/lib/types";
import { sanitizeProviderMessage } from "./errors";
import type { HealthResult, ProviderAdapter, PublishResult } from "./types";
import { validateContent } from "./validation";

/**
 * Deterministic in-process adapters for Playwright e2e runs. No external
 * network calls. Instagram is configured to fail so the partial-failure and
 * retry flows are exercisable. Behavior can be tweaked per-run via env:
 *   BLATHER_MOCK_FAIL=instagram,x
 */
function failingNetworks(): Set<Network> {
  const raw = process.env.BLATHER_MOCK_FAIL ?? "instagram";
  return new Set(raw.split(",").filter(Boolean) as Network[]);
}

function makeMock(network: Network): ProviderAdapter {
  return {
    network,
    isConnected: () => true,
    refreshIfNeeded: async () => {},
    validate(content: ResolvedContent): void {
      validateContent(network, content);
    },
    async publish(content: ResolvedContent): Promise<PublishResult> {
      validateContent(network, content);
      if (failingNetworks().has(network)) {
        throw new Error(`mock ${network} publish failure`);
      }
      const id = `mock-${network}-${Date.now()}`;
      return {
        providerPostId: id,
        providerPostUrl: `https://mock.local/${network}/${id}`,
      };
    },
    normalizeError: (err: unknown) => sanitizeProviderMessage(network, err),
    async health(): Promise<HealthResult> {
      return { ok: true, accountLabel: `@mock-${network}` };
    },
  };
}

export const mockAdapters: Record<Network, ProviderAdapter> = {
  x: makeMock("x"),
  bluesky: makeMock("bluesky"),
  threads: makeMock("threads"),
  instagram: makeMock("instagram"),
};

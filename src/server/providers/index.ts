import type { Network } from "@/lib/types";
import { useMockProviders } from "@/server/env";
import { blueskyAdapter } from "./bluesky";
import { instagramAdapter } from "./instagram";
import { mockAdapters } from "./mock";
import { threadsAdapter } from "./threads";
import type { ProviderAdapter } from "./types";
import { xAdapter } from "./x";

const realAdapters: Record<Network, ProviderAdapter> = {
  x: xAdapter,
  bluesky: blueskyAdapter,
  threads: threadsAdapter,
  instagram: instagramAdapter,
};

/** Registry. BLATHER_MOCK_PROVIDERS=1 swaps in deterministic mocks for e2e. */
export function adapterFor(network: Network): ProviderAdapter {
  if (useMockProviders()) return mockAdapters[network];
  return realAdapters[network];
}

export function allAdapters(): ProviderAdapter[] {
  return (Object.keys(realAdapters) as Network[]).map(adapterFor);
}

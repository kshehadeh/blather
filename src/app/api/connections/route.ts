import { CAPABILITIES } from "@/lib/capabilities";
import { type ConnectionInfo, NETWORKS, type Network } from "@/lib/types";
import { markConnectionError } from "@/server/connect";
import { connectionsRepo, r2Repo } from "@/server/db/repositories";
import { withGuard } from "@/server/http";
import { adapterFor } from "@/server/providers";
import type { NextRequest } from "next/server";

export const runtime = "nodejs";

/**
 * Connection status for all networks. With ?refresh=1, runs a live health
 * check per connected network and persists sanitized results.
 */
export const GET = withGuard(async (req: NextRequest) => {
  const refresh = new URL(req.url).searchParams.get("refresh") === "1";
  const repo = connectionsRepo();

  const connections: ConnectionInfo[] = [];
  for (const network of NETWORKS) {
    const stored = repo.get(network);
    if (refresh && stored.state !== "disconnected") {
      const adapter = adapterFor(network);
      const health = await adapter.health();
      if (health.ok) {
        repo.upsert({
          network,
          state: "connected",
          accountLabel: health.accountLabel ?? null,
          meta: { ...stored.meta, ...health.meta },
          error: null,
        });
      } else {
        markConnectionError(network, health.error ?? "health check failed");
      }
      connections.push(stripRef(repo.get(network)));
    } else {
      connections.push(stripRef(stored));
    }
  }

  return Response.json({
    connections,
    capabilities: NETWORKS.map((n: Network) => CAPABILITIES[n]),
    r2: r2Repo().view(),
  });
});

function stripRef(c: ConnectionInfo & { credentialRef?: string }): ConnectionInfo {
  const { credentialRef: _omit, ...rest } = c;
  void _omit;
  return rest;
}

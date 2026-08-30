import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // better-sqlite3 is a native module; keep it external to the server bundle.
  serverExternalPackages: ["better-sqlite3"],
  // Electron E2E must not contend with a developer's active Next dev lock.
  distDir: process.env.BLATHER_NEXT_E2E_DEV === "1" ? ".next-e2e" : ".next",
  poweredByHeader: false,
  // Local-only app: no telemetry, no remote features.
  productionBrowserSourceMaps: false,
};

export default nextConfig;

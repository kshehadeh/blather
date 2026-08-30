import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // better-sqlite3 is a native module; keep it external to the server bundle.
  serverExternalPackages: ["better-sqlite3"],
  poweredByHeader: false,
  // Local-only app: no telemetry, no remote features.
  productionBrowserSourceMaps: false,
};

export default nextConfig;

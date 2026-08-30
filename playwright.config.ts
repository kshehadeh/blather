import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  globalSetup: "./tests/e2e/global-setup.ts",
  timeout: 30_000,
  retries: 0,
  use: {
    baseURL: "https://127.0.0.1:3199",
    headless: true,
    ignoreHTTPSErrors: true,
  },
  webServer: {
    command: "bun run dev --port 3199",
    url: "https://127.0.0.1:3199",
    ignoreHTTPSErrors: true,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env: {
      BLATHER_DATA_DIR: ".tmp/e2e-data",
      BLATHER_KEYCHAIN: "memory",
      BLATHER_R2: "fake",
      BLATHER_MOCK_PROVIDERS: "1",
      NEXT_TELEMETRY_DISABLED: "1",
    },
  },
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});

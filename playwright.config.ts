import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  globalSetup: "./tests/e2e/global-setup.ts",
  timeout: 30_000,
  retries: 0,
  use: {
    headless: true,
    baseURL: "https://127.0.0.1:3199",
    ignoreHTTPSErrors: true,
  },
  projects: [{ name: "electron" }],
});

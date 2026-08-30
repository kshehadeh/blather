import { join } from "node:path";
import { test as base, _electron as electron, expect } from "@playwright/test";

export const test = base.extend<{
  electronApp: Awaited<ReturnType<typeof electron.launch>>;
}>({
  electronApp: [
    async ({ browserName: _browserName }, use) => {
      const electronApp = await electron.launch({
        args: [
          join(process.cwd(), "electron-dist", "main.js"),
          `--user-data-dir=${join(process.cwd(), ".tmp", "e2e-electron-user-data")}`,
        ],
        env: {
          ...process.env,
          BLATHER_DATA_DIR: ".tmp/e2e-data",
          BLATHER_KEYCHAIN: "memory",
          BLATHER_R2: "fake",
          BLATHER_MOCK_PROVIDERS: "1",
          BLATHER_DISABLE_EXTERNAL_LINKS: "1",
          BLATHER_E2E: "1",
          BLATHER_PORT: "3199",
          NEXT_TELEMETRY_DISABLED: "1",
        },
      });
      await use(electronApp);
      await electronApp.close();
    },
    { scope: "worker" },
  ],
  page: async ({ electronApp }, use) => {
    const page = await electronApp.firstWindow();
    await page.waitForLoadState("domcontentloaded");
    await use(page);
  },
});

export { expect };

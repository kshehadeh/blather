import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: { "@": new URL("./src", import.meta.url).pathname },
  },
  test: {
    environment: "node",
    include: ["tests/unit/**/*.test.ts", "tests/integration/**/*.test.ts"],
    env: {
      BLATHER_DATA_DIR: ".tmp/test-data",
      BLATHER_KEYCHAIN: "memory",
      BLATHER_S3: "fake",
    },
    testTimeout: 15000,
  },
});

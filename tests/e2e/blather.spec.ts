import { expect, test } from "./fixtures";

// 1x1 transparent PNG
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
  "base64",
);

test.describe("dashboard", () => {
  test("shows fixed sidebar navigation and empty summaries", async ({ page }) => {
    await page.goto("https://127.0.0.1:3199/");
    await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Main navigation" })).toContainText(
      "Dashboard",
    );
    for (const name of ["Compose", "History", "Settings"]) {
      await expect(page.getByRole("link", { name, exact: true })).toBeVisible();
    }
    await expect(page.getByText("Nothing published yet")).toBeVisible();
    await expect(page.getByText("No connections")).toBeVisible();
  });
});

test.describe("settings", () => {
  test("shows provider capability cards and R2 staging panel", async ({ page }) => {
    await page.goto("https://127.0.0.1:3199/settings");
    await expect(page.getByRole("heading", { name: "Settings" })).toBeVisible();
    for (const name of ["X", "Bluesky", "Threads", "Instagram"]) {
      await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
    }
    // Capability/limitation notes are visible
    await expect(page.getByText(/Free X API tier/)).toBeVisible();
    await expect(
      page.getByText(/professional \(Business or Creator\) Instagram account/),
    ).toBeVisible();
    await expect(page.getByText(/app password/i).first()).toBeVisible();
    await expect(page.getByRole("heading", { name: /R2 staging/ })).toBeVisible();
    // All start disconnected
    await expect(page.getByText("disconnected").first()).toBeVisible();
  });

  test("labels Meta credentials and explains where to find them", async ({ page }) => {
    await page.goto("https://127.0.0.1:3199/settings");
    await expect(page.getByLabel("App ID")).toHaveCount(2);
    await expect(page.getByLabel("App Secret")).toHaveCount(2);

    await page
      .getByRole("button", { name: /where do i find the app id/i })
      .first()
      .click();
    const dialog = page.getByRole("dialog");
    await expect(dialog).toContainText("Find your Threads app credentials");
    await expect(dialog).toContainText("App settings");
    await expect(dialog).toContainText("App Secret");
    await expect(dialog).toContainText("/api/connect/threads/callback");
  });
});

test.describe("composer", () => {
  test("compose, save, reopen, override, publish with a partial failure", async ({ page }) => {
    const unique = `e2e post ${Date.now()}`;
    await page.goto("https://127.0.0.1:3199/compose");

    // Compose base text + media
    await page.getByLabel("Post text").fill(unique);
    await page.getByLabel("Add media").setInputFiles({
      name: "dot.png",
      mimeType: "image/png",
      buffer: PNG,
    });
    await expect(page.getByTestId("media-list").locator("li")).toHaveCount(1);

    // Select networks (instagram is the mock failure)
    await page.getByText("X", { exact: true }).click();
    await page.getByText("Bluesky", { exact: true }).click();
    await page.getByText("Instagram", { exact: true }).click();

    // Previews show per-network char counts
    await expect(page.getByTestId("preview-x")).toContainText("/280");
    await expect(page.getByTestId("preview-instagram")).toContainText("/2200");

    // Save draft
    await page.getByRole("button", { name: "Save draft" }).click();
    await expect(page.getByRole("status")).toContainText("Draft saved");

    // Reopen the draft from the selector
    const selector = page.getByLabel("Open saved draft");
    const optionValue = await selector.locator("option", { hasText: unique }).getAttribute("value");
    expect(optionValue).toBeTruthy();
    await selector.selectOption(optionValue as string);
    await expect(page.getByLabel("Post text")).toHaveValue(unique);

    // Add an X-specific override
    await page.getByText("X override (optional)").click();
    await page.getByLabel("X override text").fill(`${unique} (x edition)`);
    await page.getByRole("button", { name: "Save draft" }).click();
    await expect(page.getByRole("status")).toContainText("Draft updated");

    // Publish: mock providers => x+bluesky succeed, instagram fails
    await page.getByRole("button", { name: "Publish now" }).click();
    await expect(page.getByRole("status")).toContainText(/2 succeeded, 1 failed/);

    const results = page.getByTestId("publish-results");
    await expect(results.getByText("success")).toHaveCount(2);
    await expect(results.getByText("failed")).toHaveCount(1);
    await expect(results).toContainText("mock instagram publish failure");
  });

  test("validation warnings appear before publishing", async ({ page }) => {
    await page.goto("https://127.0.0.1:3199/compose");
    await page.getByLabel("Post text").fill("x".repeat(281));
    await page.getByText("X", { exact: true }).click();
    await expect(page.getByTestId("preview-x").getByRole("alert")).toContainText("over limit");
  });
});

test.describe("history", () => {
  test("shows per-network attempts and retries only failures", async ({ page }) => {
    // Publish something first (instagram fails in mock mode)
    const unique = `history ${Date.now()}`;
    await page.goto("https://127.0.0.1:3199/compose");
    await page.getByLabel("Post text").fill(unique);
    // Instagram requires media; attach one so the failure comes from the
    // (mocked) provider rather than validation.
    await page.getByLabel("Add media").setInputFiles({
      name: "dot.png",
      mimeType: "image/png",
      buffer: PNG,
    });
    await expect(page.getByTestId("media-list").locator("li")).toHaveCount(1);
    await page.getByText("X", { exact: true }).click();
    await page.getByText("Instagram", { exact: true }).click();
    await page.getByRole("button", { name: "Publish now" }).click();
    await expect(page.getByRole("status")).toContainText(/1 succeeded, 1 failed/);

    await page.goto("https://127.0.0.1:3199/history");
    const list = page.getByTestId("history-list");
    await expect(list).toContainText("mock instagram publish failure");

    // Only failed attempts offer a retry button (one per failed row).
    await expect(async () => {
      const failedRows = await list.locator("li", { hasText: "failed" }).count();
      const retryButtons = await page.getByRole("button", { name: "Retry" }).count();
      expect(retryButtons).toBe(failedRows);
      expect(failedRows).toBeGreaterThan(0);
    }).toPass();

    // Retry (still failing in mock mode): no duplicate attempts are created.
    const rowsBefore = await list.locator("li").count();
    const successBefore = await list.locator("li", { hasText: "success" }).count();
    await list
      .locator("li", { hasText: "Instagram" })
      .getByRole("button", { name: "Retry" })
      .first()
      .click();
    await expect(list).toContainText("mock instagram publish failure");
    expect(await list.locator("li").count()).toBe(rowsBefore);
    expect(await list.locator("li", { hasText: "success" }).count()).toBe(successBefore);
  });
});

test.describe("desktop navigation", () => {
  test("keeps provider authorization outside the application window", async ({ page }) => {
    await page.goto("https://127.0.0.1:3199/settings");
    await page.evaluate(() => window.open("https://x.com/i/oauth2/authorize"));
    await expect(page).toHaveURL(/https:\/\/127\.0\.0\.1:3199\/settings/);
  });
});

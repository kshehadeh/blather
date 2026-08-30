import { ProviderError, fetchJson, messageFromBody } from "@/server/providers/errors";
import { redact } from "@/server/security";
import { describe, expect, it, vi } from "vitest";

describe("redact", () => {
  it("redacts bearer tokens", () => {
    expect(redact("failed with Bearer abc123.def456 on request")).toBe(
      "failed with [redacted] on request",
    );
  });

  it("redacts access_token fields", () => {
    expect(redact('{"access_token":"sekrit"}')).not.toContain("sekrit");
    expect(redact("access_token=sekrit")).not.toContain("sekrit");
  });

  it("redacts signed URL credentials", () => {
    const url = "https://s3/x?X-Amz-Signature=deadbeef&X-Amz-Credential=AKIA%2F123";
    const out = redact(url);
    expect(out).not.toContain("deadbeef");
    expect(out).not.toContain("AKIA");
  });
});

describe("messageFromBody", () => {
  it("extracts nested error messages", () => {
    expect(messageFromBody({ error: { message: "bad things" } }, "fb")).toBe("bad things");
    expect(messageFromBody({ detail: "nope" }, "fb")).toBe("nope");
    expect(messageFromBody({ errors: [{ message: "first" }] }, "fb")).toBe("first");
  });

  it("falls back when body has no message", () => {
    expect(messageFromBody({}, "fallback")).toBe("fallback");
    expect(messageFromBody(null, "fallback")).toBe("fallback");
  });

  it("redacts secrets in provider messages", () => {
    expect(messageFromBody({ message: "token access_token=hunter2 rejected" }, "fb")).not.toContain(
      "hunter2",
    );
  });
});

describe("fetchJson", () => {
  it("throws ProviderError with sanitized message on HTTP errors", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(
        async () =>
          new Response(JSON.stringify({ error: { message: "bad access_token=leak" } }), {
            status: 403,
          }),
      ),
    );
    await expect(fetchJson("x", "https://api.x.com/2/tweets", {})).rejects.toMatchObject({
      message: expect.not.stringContaining("leak"),
    });
    vi.unstubAllGlobals();
  });

  it("marks 429/5xx as retryable", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("{}", { status: 429 })),
    );
    const err = await fetchJson("x", "https://x", {}).catch((e) => e);
    expect(err).toBeInstanceOf(ProviderError);
    expect((err as ProviderError).opts.retryable).toBe(true);
    vi.unstubAllGlobals();
  });

  it("throws retryable error on network failure", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("ECONNREFUSED");
      }),
    );
    const err = await fetchJson("x", "https://x", {}).catch((e) => e);
    expect(err).toBeInstanceOf(ProviderError);
    expect((err as ProviderError).opts.retryable).toBe(true);
    expect((err as ProviderError).message).toBe("x: network request failed");
    vi.unstubAllGlobals();
  });
});

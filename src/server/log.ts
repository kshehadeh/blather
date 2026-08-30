import { redact } from "./security";

/**
 * Minimal logger that redacts tokens, app secrets, signed staging URLs, and
 * raw provider payloads before anything reaches stdout/stderr.
 */

function safe(value: unknown): string {
  let text: string;
  if (typeof value === "string") {
    text = value;
  } else {
    try {
      text = JSON.stringify(value);
    } catch {
      text = String(value);
    }
  }
  return redact(text);
}

export const log = {
  info(...args: unknown[]): void {
    console.log("[blather]", ...args.map(safe));
  },
  warn(...args: unknown[]): void {
    console.warn("[blather]", ...args.map(safe));
  },
  error(...args: unknown[]): void {
    console.error("[blather]", ...args.map(safe));
  },
};

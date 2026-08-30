import { rmSync } from "node:fs";
import { join } from "node:path";

/** Start every e2e run from a clean local data directory. */
export default function globalSetup(): void {
  rmSync(join(process.cwd(), ".tmp", "e2e-data"), { recursive: true, force: true });
}

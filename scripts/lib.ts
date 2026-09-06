import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

export const repoRoot = resolve(import.meta.dir, "..");
export const xcode = process.env.DEVELOPER_DIR ?? "/Applications/Xcode.app/Contents/Developer";
export const project = join(repoRoot, "Blather.xcodeproj");
export const scheme = "Blather";
export const archivePath = join(repoRoot, "build", "Blather.xcarchive");
export const exportDir = join(repoRoot, "build", "export");
export const exportOptions = join(repoRoot, "scripts", "ExportOptions.plist");

export interface ReleaseConfig {
  app_name: string;
  github_repo: string;
  git_branch: string;
  min_system_version: string;
  bundle_name: string;
  dmg_name: string;
  appcast_file: string;
  development_team: string;
}

export function loadConfig(): ReleaseConfig {
  const raw = JSON.parse(readFileSync(join(repoRoot, "release.json"), "utf8")) as Partial<ReleaseConfig>;
  if (!raw.app_name || !raw.github_repo) fail("release.json needs app_name and github_repo");
  return {
    app_name: raw.app_name,
    github_repo: raw.github_repo,
    git_branch: raw.git_branch ?? "main",
    min_system_version: raw.min_system_version ?? "15.0",
    bundle_name: raw.bundle_name ?? `${raw.app_name}.app`,
    dmg_name: raw.dmg_name ?? `${raw.app_name}.dmg`,
    appcast_file: raw.appcast_file ?? "appcast.xml",
    development_team: raw.development_team ?? process.env.DEVELOPMENT_TEAM ?? "",
  };
}

export function developerIdIdentities(): string[] {
  const proc = Bun.spawnSync(["security", "find-identity", "-v", "-p", "codesigning"], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = new TextDecoder().decode(proc.stdout);
  return [...out.matchAll(/Developer ID Application: ([^"]+)/g)].map((match) => match[0]);
}

export function requireDeveloperId(): void {
  const ids = developerIdIdentities();
  if (ids.length > 0) {
    ok(ids[0]);
    return;
  }
  const proc = Bun.spawnSync(["security", "find-identity", "-v", "-p", "codesigning"], {
    stdout: "pipe",
    stderr: "pipe",
  });
  const found = new TextDecoder().decode(proc.stdout).trim() || "(none)";
  fail(`No "Developer ID Application" certificate in the keychain.

GitHub/Sparkle releases have to be signed with Developer ID, then notarized.
You currently have:
${found}

Create one with a paid Apple Developer Program membership:
  1. https://developer.apple.com/account/resources/certificates/list
  2. Create a "Developer ID Application" certificate
  3. Xcode → Settings → Accounts → your team → Manage Certificates
     → + → Developer ID Application

Apple Development certificates can run the app on this Mac, but they cannot
export a Developer ID build (that is the xcodebuild exit 70 / "No Team Found"
failure).`);
}

export function writeExportOptions(team: string): string {
  if (!team) fail("release.json is missing development_team (your 10-character Apple team ID)");
  ensureDir(join(repoRoot, "build"));
  const path = join(repoRoot, "build", "ExportOptions.plist");
  writeFileSync(
    path,
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>${team}</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
</dict>
</plist>
`,
  );
  return path;
}

export function fail(message: string): never {
  console.error(`error: ${message}`);
  process.exit(1);
}

export function log(message: string): void {
  console.log(`==> ${message}`);
}

export function ok(message: string): void {
  console.log(`  ok  ${message}`);
}

export function warn(message: string): void {
  console.log(`  warn  ${message}`);
}

export async function run(cmd: string[], options: { cwd?: string; allowFail?: boolean } = {}): Promise<number> {
  const proc = Bun.spawn(cmd, {
    cwd: options.cwd ?? repoRoot,
    stdout: "inherit",
    stderr: "inherit",
    env: { ...process.env, DEVELOPER_DIR: xcode },
  });
  const code = await proc.exited;
  if (code !== 0 && !options.allowFail) fail(`${cmd.join(" ")} exited ${code}`);
  return code;
}

export async function capture(cmd: string[], options: { cwd?: string } = {}): Promise<{ code: number; out: string }> {
  const proc = Bun.spawn(cmd, {
    cwd: options.cwd ?? repoRoot,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, DEVELOPER_DIR: xcode },
  });
  const out = `${await new Response(proc.stdout).text()}${await new Response(proc.stderr).text()}`;
  const code = await proc.exited;
  return { code, out: out.trim() };
}

export function which(name: string): string | null {
  for (const dir of (process.env.PATH ?? "").split(":")) {
    const candidate = join(dir, name);
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

export function requireTool(name: string, hint: string): string {
  const path = which(name);
  if (!path) fail(`${name} not found. ${hint}`);
  return path;
}

export function ensureDir(path: string): void {
  mkdirSync(path, { recursive: true });
}

export function findSparkleBin(name: "generate_keys" | "sign_update"): string {
  const derived = join(homedir(), "Library/Developer/Xcode/DerivedData");
  if (!existsSync(derived)) fail("DerivedData not found. Build Blather once first.");
  for (const entry of readdirSync(derived)) {
    if (!entry.startsWith("Blather-")) continue;
    const candidate = join(derived, entry, "SourcePackages/artifacts/sparkle/Sparkle/bin", name);
    if (existsSync(candidate)) return candidate;
  }
  fail(`Sparkle ${name} not found. Run bun run build first so Sparkle artifacts exist.`);
}

export function plist(appPath: string, key: string): string {
  const path = join(appPath, "Contents/Info.plist");
  if (!existsSync(path)) fail(`Info.plist not found at ${path}`);
  const proc = Bun.spawnSync(["plutil", "-extract", key, "raw", "-o", "-", path], { stdout: "pipe", stderr: "pipe" });
  if (proc.exitCode !== 0) fail(`Could not read ${key} from ${path}`);
  return new TextDecoder().decode(proc.stdout).trim();
}

export function defaultAppPath(cfg: ReleaseConfig): string {
  const exported = join(exportDir, cfg.bundle_name);
  if (existsSync(exported)) return exported;
  const downloads = join(homedir(), "Downloads", cfg.bundle_name);
  if (existsSync(downloads)) return downloads;
  fail(`${cfg.bundle_name} not found in build/export or ~/Downloads. Export a Release build first.`);
}

export function dmgPath(cfg: ReleaseConfig): string {
  return join(repoRoot, "build", cfg.dmg_name);
}

export function parseArgs(argv: string[]): { command: string; flags: Record<string, string | boolean>; rest: string[] } {
  const [command = "help", ...raw] = argv;
  const flags: Record<string, string | boolean> = {};
  const rest: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    const arg = raw[i];
    if (arg === "--") {
      rest.push(...raw.slice(i + 1));
      break;
    }
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const next = raw[i + 1];
      if (!next || next.startsWith("--")) flags[key] = true;
      else {
        flags[key] = next;
        i++;
      }
    } else rest.push(arg);
  }
  return { command, flags, rest };
}

export function flagString(flags: Record<string, string | boolean>, name: string): string | undefined {
  const value = flags[name];
  return typeof value === "string" ? value : undefined;
}

export function readProjectYml(): string {
  return readFileSync(join(repoRoot, "project.yml"), "utf8");
}

export function writeProjectYml(contents: string): void {
  writeFileSync(join(repoRoot, "project.yml"), contents);
}

export function projectVersions(): { marketing: string; build: string } {
  const yml = readProjectYml();
  const marketing = yml.match(/MARKETING_VERSION:\s*"([^"]+)"/)?.[1];
  const build = yml.match(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/)?.[1];
  if (!marketing || !build) fail("Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml");
  return { marketing, build };
}

export function setProjectVersions(marketing: string, build: string): void {
  let yml = readProjectYml();
  yml = yml.replace(/MARKETING_VERSION:\s*"[^"]+"/, `MARKETING_VERSION: "${marketing}"`);
  yml = yml.replace(/CURRENT_PROJECT_VERSION:\s*"[^"]+"/, `CURRENT_PROJECT_VERSION: "${build}"`);
  yml = yml.replace(/CFBundleShortVersionString:\s*"[^"]+"/, `CFBundleShortVersionString: "${marketing}"`);
  yml = yml.replace(/CFBundleVersion:\s*"[^"]+"/, `CFBundleVersion: "${build}"`);
  writeProjectYml(yml);
}

export async function xcodegen(): Promise<void> {
  requireTool("xcodegen", "Install with: brew install xcodegen");
  log("Generating Xcode project");
  await run(["xcodegen", "generate"]);
}

export function xcodebuildBase(): string[] {
  return [`${xcode}/usr/bin/xcodebuild`];
}

export async function confirm(question: string, defaultYes = true): Promise<boolean> {
  if (!process.stdin.isTTY) return defaultYes;
  const hint = defaultYes ? "Y/n" : "y/N";
  const answer = (await prompt(`${question} (${hint}) `))?.trim().toLowerCase() ?? "";
  if (!answer) return defaultYes;
  return answer === "y" || answer === "yes";
}

async function prompt(message: string): Promise<string | null> {
  process.stdout.write(message);
  const reader = Bun.stdin.stream().getReader();
  const chunks: Uint8Array[] = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    if (value.includes(10) || value.includes(13)) break;
  }
  reader.releaseLock();
  const text = new TextDecoder().decode(Buffer.concat(chunks.map((c) => Buffer.from(c))));
  return text.replace(/\r?\n$/, "");
}

export async function readNotes(flags: Record<string, string | boolean>): Promise<string[]> {
  const fromFlag = flagString(flags, "notes");
  if (fromFlag) {
    return fromFlag
      .split(/[;\n]/)
      .map((line) => line.replace(/^-\s*/, "").trim())
      .filter(Boolean);
  }
  const fromFile = flagString(flags, "notes-file");
  if (fromFile) {
    return readFileSync(fromFile, "utf8")
      .split("\n")
      .map((line) => line.replace(/^-\s*/, "").trim())
      .filter(Boolean);
  }
  if (!process.stdin.isTTY) fail("Pass --notes \"one;two\" or --notes-file path");
  console.log("Release notes (one bullet per line, empty line to finish):");
  const notes: string[] = [];
  while (true) {
    const line = (await prompt("> "))?.trim() ?? "";
    if (!line) break;
    notes.push(line.replace(/^-\s*/, ""));
  }
  if (notes.length === 0) fail("No release notes provided");
  return notes;
}

export function escapeXml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

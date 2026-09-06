#!/usr/bin/env bun

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  archivePath,
  capture,
  confirm,
  defaultAppPath,
  dmgPath,
  ensureDir,
  escapeXml,
  exportDir,
  fail,
  findSparkleBin,
  flagString,
  loadConfig,
  log,
  ok,
  parseArgs,
  plist,
  project,
  projectVersions,
  readNotes,
  repoRoot,
  requireDeveloperId,
  requireTool,
  run,
  scheme,
  setProjectVersions,
  warn,
  writeExportOptions,
  xcodebuildBase,
  xcodegen,
} from "./lib";

const { command, flags, rest } = parseArgs(Bun.argv.slice(2));

await dispatch(command);

async function dispatch(name: string): Promise<void> {
  switch (name) {
    case "generate":
      return xcodegen();
    case "dev":
      return dev();
    case "build":
      return build();
    case "test":
      return test();
    case "keys":
      return keys();
    case "bump":
      return bump();
    case "archive":
      return archive();
    case "export":
      return exportArchive();
    case "dmg":
      return dmg();
    case "sign":
      return sign();
    case "appcast":
      return appcast();
    case "github":
      return github();
    case "release":
      return release();
    case "help":
    case "--help":
    case "-h":
      return help();
    default:
      fail(`Unknown command: ${name}\nRun bun run scripts/blather.ts help`);
  }
}

function help(): void {
  console.log(`Blather build and release scripts

Usage: bun run <script> [-- flags]

  generate          xcodegen generate
  dev               generate and open Blather.xcodeproj
  build             Debug build (unsigned, local)
  test              Unit tests
  keys              Generate Sparkle EdDSA keys (once)
  bump <version>    Set MARKETING_VERSION and increment build
  archive           Release archive (Developer ID)
  export            Export + notarize Developer ID app from the archive
  dmg               Create Blather.dmg from the exported app
  sign              Sparkle-sign the DMG
  appcast           Insert a Sparkle appcast item
  github            Create the GitHub release with the DMG
  release           archive → export → dmg → sign → appcast → git → gh
  release:pack      dmg → sign → appcast → git → gh (app already exported)

Flags
  --yes             Skip confirmation
  --pack-only       Skip archive/export (use with release)
  --app <path>      Path to Blather.app
  --dmg <path>      Path to Blather.dmg
  --notes "a;b"     Release notes
  --notes-file path Notes file, one bullet per line
  --build N         Build number for bump
`);
}

async function dev(): Promise<void> {
  await xcodegen();
  await run(["open", join(repoRoot, "Blather.xcodeproj")]);
}

async function build(): Promise<void> {
  await xcodegen();
  log("Debug build");
  await run([
    ...xcodebuildBase(),
    "build",
    "-project",
    project,
    "-scheme",
    scheme,
    "-configuration",
    "Debug",
    "-destination",
    "platform=macOS",
    "CODE_SIGN_IDENTITY=",
    "CODE_SIGNING_ALLOWED=NO",
  ]);
}

async function test(): Promise<void> {
  await xcodegen();
  log("Unit tests");
  await run([
    ...xcodebuildBase(),
    "test",
    "-project",
    project,
    "-scheme",
    scheme,
    "-configuration",
    "Debug",
    "-destination",
    "platform=macOS",
    "-only-testing:BlatherTests",
    "CODE_SIGN_IDENTITY=",
    "CODE_SIGNING_ALLOWED=NO",
  ]);
}

async function keys(): Promise<void> {
  const generateKeys = findSparkleBin("generate_keys");
  log(`Running ${generateKeys}`);
  console.log(`
This prints a public key and stores the private key in your login Keychain.
Paste the public key into project.yml as SUPublicEDKey, then run bun run generate.
Do this once. Do not commit the private key.
`);
  await run([generateKeys]);
}

async function bump(): Promise<void> {
  const current = projectVersions();
  const marketing = rest[0] ?? flagString(flags, "version");
  if (!marketing) fail("Usage: bun run bump 0.2.0");
  const build = flagString(flags, "build") ?? String(Number(current.build) + 1);
  setProjectVersions(marketing, build);
  ok(`project.yml → ${marketing} (${build})`);
  await xcodegen();
}

async function archive(): Promise<void> {
  requireDeveloperId();
  const cfg = loadConfig();
  if (!cfg.development_team) fail("Set development_team in release.json to your Apple team ID");
  await xcodegen();
  ensureDir(join(repoRoot, "build"));
  log("Release archive");
  await run([
    ...xcodebuildBase(),
    "archive",
    "-project",
    project,
    "-scheme",
    scheme,
    "-configuration",
    "Release",
    "-destination",
    "generic/platform=macOS",
    "-archivePath",
    archivePath,
    "-allowProvisioningUpdates",
    `DEVELOPMENT_TEAM=${cfg.development_team}`,
    "CODE_SIGN_STYLE=Manual",
    "CODE_SIGN_IDENTITY=Developer ID Application",
  ]);
  ok(archivePath);
}

async function exportArchive(): Promise<void> {
  requireDeveloperId();
  const cfg = loadConfig();
  if (!existsSync(archivePath)) fail("No archive at build/Blather.xcarchive. Run bun run archive first.");
  ensureDir(exportDir);
  const options = writeExportOptions(cfg.development_team);
  log("Exporting Developer ID build");
  const { code, out } = await capture([
    ...xcodebuildBase(),
    "-exportArchive",
    "-archivePath",
    archivePath,
    "-exportPath",
    exportDir,
    "-exportOptionsPlist",
    options,
    "-allowProvisioningUpdates",
  ]);
  const errors = out
    .split("\n")
    .filter((line) => /error:|EXPORT FAILED|No Team Found|to be signed with/i.test(line));
  if (errors.length) console.error(errors.join("\n"));
  if (code !== 0) fail(errors.at(-1) ?? `exportArchive exited ${code}`);
  const app = join(exportDir, cfg.bundle_name);
  if (!existsSync(app)) fail(`Export succeeded but ${app} is missing`);
  log("Stapling notarization ticket");
  await run(["xcrun", "stapler", "staple", app], { allowFail: true });
  ok(app);
}

async function dmg(): Promise<void> {
  const cfg = loadConfig();
  requireTool("create-dmg", "Install with: brew install create-dmg");
  const app = flagString(flags, "app") ?? defaultAppPath(cfg);
  const out = flagString(flags, "dmg") ?? dmgPath(cfg);
  ensureDir(join(repoRoot, "build"));
  if (existsSync(out)) await run(["rm", "-f", out]);
  log(`Creating ${out}`);
  const code = await run(
    [
      "create-dmg",
      "--volname",
      cfg.app_name,
      "--window-pos",
      "200",
      "120",
      "--window-size",
      "660",
      "400",
      "--icon-size",
      "160",
      "--icon",
      cfg.bundle_name,
      "180",
      "170",
      "--app-drop-link",
      "480",
      "170",
      "--hide-extension",
      cfg.bundle_name,
      out,
      app,
    ],
    { allowFail: true },
  );
  if (!existsSync(out)) fail(`create-dmg exited ${code} and did not write ${out}`);
  ok(out);
}

function parseSignature(output: string): { signature: string; length: string } {
  const signature = output.match(/sparkle:edSignature="([^"]+)"/)?.[1];
  const length = output.match(/length="([^"]+)"/)?.[1];
  if (!signature || !length) fail(`Could not parse sign_update output:\n${output}`);
  return { signature, length };
}

async function sign(): Promise<void> {
  const cfg = loadConfig();
  const dmg = flagString(flags, "dmg") ?? dmgPath(cfg);
  if (!existsSync(dmg)) fail(`${dmg} not found. Run bun run dmg first.`);
  const signUpdate = findSparkleBin("sign_update");
  log("Sparkle-signing DMG");
  const { code, out } = await capture([signUpdate, dmg]);
  if (code !== 0) fail(out || "sign_update failed");
  const parsed = parseSignature(out);
  console.log(out);
  writeFileSync(join(repoRoot, "build", "sparkle-sign.txt"), `${out}\n`);
  ok(`edSignature length=${parsed.length}`);
}

function insertAppcastItem(xml: string, item: string): string {
  if (xml.includes("<item>")) return xml.replace("<item>", `${item}\n    <item>`);
  return xml.replace("</channel>", `${item}\n  </channel>`);
}

async function appcast(): Promise<{ version: string; build: string; dmg: string }> {
  const cfg = loadConfig();
  const app = flagString(flags, "app") ?? defaultAppPath(cfg);
  const dmg = flagString(flags, "dmg") ?? dmgPath(cfg);
  const version = plist(app, "CFBundleShortVersionString");
  const build = plist(app, "CFBundleVersion");
  const signFile = join(repoRoot, "build", "sparkle-sign.txt");
  const signed = existsSync(signFile) ? readFileSync(signFile, "utf8") : "";
  const parsed = signed.includes("sparkle:edSignature")
    ? parseSignature(signed)
    : await (async () => {
        if (!existsSync(dmg)) fail("Need a signed DMG. Run bun run sign first.");
        const signUpdate = findSparkleBin("sign_update");
        const { code, out } = await capture([signUpdate, dmg]);
        if (code !== 0) fail(out || "sign_update failed");
        return parseSignature(out);
      })();

  const notes = await readNotes(flags);
  const pubDate = new Date().toUTCString().replace("GMT", "+0000");
  const url = `https://github.com/${cfg.github_repo}/releases/download/v${version}/${cfg.dmg_name}`;
  const lis = notes.map((note) => `          <li>${escapeXml(note)}</li>`).join("\n");
  const item = `    <item>
      <title>Version ${escapeXml(version)} (Build ${escapeXml(build)})</title>
      <pubDate>${pubDate}</pubDate>
      <sparkle:version>${escapeXml(build)}</sparkle:version>
      <sparkle:shortVersionString>${escapeXml(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escapeXml(cfg.min_system_version)}</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <ul>
${lis}
        </ul>
      ]]></description>
      <enclosure url="${escapeXml(url)}"
                 type="application/octet-stream"
                 sparkle:edSignature="${parsed.signature}"
                 length="${parsed.length}" />
    </item>`;

  const path = join(repoRoot, cfg.appcast_file);
  const xml = readFileSync(path, "utf8");
  if (xml.includes(`<sparkle:version>${build}</sparkle:version>`)) {
    warn(`Build ${build} already exists in ${cfg.appcast_file}`);
  }
  writeFileSync(path, insertAppcastItem(xml, item));
  ok(`Updated ${cfg.appcast_file} for v${version} (${build})`);
  return { version, build, dmg };
}

async function github(precomputed?: { version: string; dmg: string; notes: string[] }): Promise<void> {
  const cfg = loadConfig();
  requireTool("gh", "Install with: brew install gh");
  const app = flagString(flags, "app") ?? defaultAppPath(cfg);
  const version = precomputed?.version ?? plist(app, "CFBundleShortVersionString");
  const dmg = precomputed?.dmg ?? (flagString(flags, "dmg") ?? dmgPath(cfg));
  if (!existsSync(dmg)) fail(`${dmg} not found`);
  const notes = precomputed?.notes ?? (await readNotes(flags));
  const md = ["## What's New", "", ...notes.map((note) => `- ${note}`)].join("\n");
  log(`Creating GitHub release v${version}`);
  await run([
    "gh",
    "release",
    "create",
    `v${version}`,
    dmg,
    "--repo",
    cfg.github_repo,
    "--title",
    `v${version}`,
    "--notes",
    md,
  ]);
}

async function release(): Promise<void> {
  const cfg = loadConfig();
  requireTool("create-dmg", "Install with: brew install create-dmg");
  requireTool("gh", "Install with: brew install gh");
  requireTool("git", "");
  findSparkleBin("sign_update");
  if (!Boolean(flags["pack-only"])) requireDeveloperId();

  const packOnly = Boolean(flags["pack-only"]);
  if (!packOnly) {
    await archive();
    await exportArchive();
  }

  const app = flagString(flags, "app") ?? defaultAppPath(cfg);
  const version = plist(app, "CFBundleShortVersionString");
  const build = plist(app, "CFBundleVersion");
  const notes = await readNotes(flags);

  console.log(`
Release summary
  App:     ${cfg.app_name}
  Version: ${version} (build ${build})
  Tag:     v${version}
  Notes:`);
  for (const note of notes) console.log(`    - ${note}`);
  console.log("");

  if (!flags.yes && !(await confirm("Proceed with release?", true))) process.exit(0);

  flags.notes = notes.join(";");
  await dmg();
  await sign();
  await appcast();

  log("Committing appcast");
  await run(["git", "add", cfg.appcast_file]);
  await run(["git", "commit", "-m", `Release v${version} appcast`], { allowFail: true });
  await run(["git", "push", "origin", cfg.git_branch]);

  await github({ version, dmg: dmgPath(cfg), notes });
  ok(`Released ${cfg.app_name} v${version}`);
  console.log(`https://github.com/${cfg.github_repo}/releases/tag/v${version}`);
}

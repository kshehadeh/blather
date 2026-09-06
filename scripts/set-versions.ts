#!/usr/bin/env bun

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const version = process.argv[2];
const build = process.argv[3];

if (!version) {
  console.error("Usage: bun scripts/set-versions.ts <version> [build]");
  process.exit(2);
}

const root = join(import.meta.dir, "..");
const ymlPath = join(root, "project.yml");
let yml = readFileSync(ymlPath, "utf8");
yml = yml.replace(/MARKETING_VERSION:\s*"[^"]+"/, `MARKETING_VERSION: "${version}"`);
yml = yml.replace(/CFBundleShortVersionString:\s*"[^"]+"/, `CFBundleShortVersionString: "${version}"`);
if (build) {
  yml = yml.replace(/CURRENT_PROJECT_VERSION:\s*"[^"]+"/, `CURRENT_PROJECT_VERSION: "${build}"`);
  yml = yml.replace(/CFBundleVersion:\s*"[^"]+"/, `CFBundleVersion: "${build}"`);
}
writeFileSync(ymlPath, yml);

const plistPath = join(root, "Blather/Resources/Info.plist");
let plist = readFileSync(plistPath, "utf8");
plist = plist.replace(
  /(<key>CFBundleShortVersionString<\/key>\s*<string>)[^<]+/,
  `$1${version}`,
);
if (build) {
  plist = plist.replace(/(<key>CFBundleVersion<\/key>\s*<string>)[^<]+/, `$1${build}`);
}
writeFileSync(plistPath, plist);

console.log(`version → ${version}${build ? ` (${build})` : ""}`);

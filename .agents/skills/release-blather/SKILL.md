---
name: release-blather
description: Perform Blather project releases using release-it, GitHub Actions signing/notarization, DMG packaging, and Sparkle appcast updates. Use when the user asks to cut, prepare, dry-run, tag, or troubleshoot a Blather release.
---

# Release Blather

## Goal

Prepare and cut a Blather release the same way Toby does: `release-it` locally, GitHub Actions on the version tag.

**Default for agents:** use non-interactive release-it mode so prompts are skipped:

```bash
bun run release -- <patch|minor|major> --ci
```

The `--` passes `<increment>` and `--ci` through to `release-it`.

## Source Of Truth

- Release docs: `docs/release.md`
- Release script: `bun run release` (wraps `release-it`)
- Release config: `.release-it.json`
- CI workflow: `.github/workflows/release.yml`
- Version sync: `scripts/set-versions.ts` (package.json → project.yml)

## Release Shape

Tag pushes matching `v*` run the GitHub Actions release workflow.

Expected assets:

- `Blather.dmg`
- `appcast.xml` (when Sparkle secrets are present)

The DMG contains `Blather.app`. Sparkle publishes `appcast.xml` to GitHub Pages at `/appcast.xml` (`https://kshehadeh.github.io/blather/appcast.xml`).

Signed browser-safe releases require these GitHub Actions secrets:

- `CSC_LINK` — base64-encoded Developer ID Application `.p12`
- `CSC_KEY_PASSWORD` — certificate export password
- `APPLE_ID` — Apple Developer account email
- `APPLE_APP_SPECIFIC_PASSWORD` — notarization app-specific password
- `APPLE_TEAM_ID` — Apple Developer Team ID
- `SPARKLE_PUBLIC_KEY` — public EdDSA key (must match `SUPublicEDKey`)
- `SPARKLE_PRIVATE_KEY` — private EdDSA key used only in CI

If any signing secret is missing, CI skips signing/notarization and uploads an unsigned DMG. Invalid non-empty credentials should fail the release.

Sparkle needs a publicly reachable `SUFeedURL`; this repo is public and Pages serves the appcast. See `docs/release.md`.

## Cutting The Release

```bash
bun run release -- patch --ci
bun run release -- minor --ci
bun run release -- major --ci
```

Always include `--ci` when cutting a release without a human at the terminal.
`--ci` skips release-it prompts (version bump confirmation, publish questions,
etc.).

`release-it` bumps `package.json`, syncs `project.yml` via the `after:bump`
hook, creates a `chore(release): v${version}` commit, creates tag `v${version}`,
and pushes. The tag push triggers `.github/workflows/release.yml`.

`bun run release:ci -- <patch|minor|major>` is a thin wrapper around the same
`release-it <increment> --ci` invocation; prefer `bun run release -- … --ci`
for consistency.

Do not use `bun run release:local` unless the user explicitly wants the old
Mac-side archive → notarize → DMG → gh pipeline.

## Safety Notes

- Never force-push release tags unless the user explicitly requests it.
- If the release commit/tag already exists, stop and inspect before retrying.
- If CI fails, fix forward with a new commit and tag unless the user explicitly
  asks to delete/recreate the tag.
- Keep release messages Conventional Commit compatible.

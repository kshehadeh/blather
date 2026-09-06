# Releasing Blather

Blather uses the same release methodology as Toby:

1. Locally, `release-it` bumps the version, commits, tags `v${version}`, and pushes.
2. The tag push runs [`.github/workflows/release.yml`](../.github/workflows/release.yml) on `macos-26`.
3. CI archives the app with Xcode, signs with Developer ID, notarizes, builds a DMG, generates a Sparkle appcast, creates a GitHub Release, and publishes `appcast.xml` to GitHub Pages.

## Cutting a release

From a clean `main`:

```bash
bun run release -- patch --ci
bun run release -- minor --ci
bun run release -- major --ci
```

Always include `--ci` when no human is at the terminal. `bun run release:dry -- patch` prints the same steps without writing.

`release-it` updates `package.json`, syncs `MARKETING_VERSION` / `CFBundleShortVersionString` in `project.yml`, creates `chore(release): v${version}`, tags `v${version}`, and pushes. Do not create the GitHub Release by hand.

`bun run release:ci -- <patch|minor|major>` is a thin wrapper around the same `release-it <increment> --ci` invocation.

## What CI publishes

- `Blather.dmg` — drag-and-drop installer (Blather.app + /Applications)
- `appcast.xml` — Sparkle feed (also deployed to GitHub Pages)

`CFBundleVersion` (Sparkle `sparkle:version`) is `github.run_number` for that Release workflow, so it always increases.

## GitHub Actions variables and secrets

Signed, notarized, Sparkle-updating releases need repository **variables** for non-secret identifiers and **secrets** for credentials:

| Kind | Name | Purpose |
| --- | --- | --- |
| Variable | `APPLE_ID` | Apple Developer account email |
| Variable | `APPLE_TEAM_ID` | Apple Developer Team ID (`SFK76D5YXM`) |
| Secret | `CSC_LINK` | Base64-encoded Developer ID Application `.p12` |
| Secret | `CSC_KEY_PASSWORD` | Password used when exporting that `.p12` |
| Secret | `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for `notarytool` |
| Secret | `SPARKLE_PUBLIC_KEY` | Public EdDSA key (must match `SUPublicEDKey` in `project.yml`) |
| Secret | `SPARKLE_PRIVATE_KEY` | Private EdDSA key used only in CI by `generate_appcast` |

Create `CSC_LINK` by base64-encoding the Developer ID Application `.p12`:

```bash
base64 -i /path/to/developer-id-application.p12 | tr -d '\n' | pbcopy
```

If any Apple signing variable or secret is missing, CI still builds and uploads an unsigned DMG with a warning. Invalid non-empty credentials fail the release. If Sparkle keys are missing, CI skips `appcast.xml`.

Sparkle keys are **not** the Developer ID certificate. Generate them once on a trusted Mac:

```bash
bun run keys
```

Store the public key in `project.yml` (`SUPublicEDKey`) and in `SPARKLE_PUBLIC_KEY`. Export the private key with Sparkle `generate_keys -x` (a single line of base64) and store that in `SPARKLE_PRIVATE_KEY` (and in your login Keychain). Never commit the private key.

## Sparkle feed

Production `SUFeedURL` is:

```
https://kshehadeh.github.io/blather/appcast.xml
```

CI generates the appcast with Sparkle `generate_appcast` (`--maximum-versions 1`) and deploys it to GitHub Pages. The same file is attached to the GitHub Release next to `Blather.dmg`.

The v0.1.0 app looked at `https://raw.githubusercontent.com/kshehadeh/blather/main/appcast.xml`. That file is left in the repo for that build only; new builds use Pages.

## Local artifacts (no publish)

```bash
bun run build:release   # dist/Blather.app (unsigned unless Developer ID is in the keychain)
bun run build:dmg       # dist/Blather.dmg
```

Set `BLATHER_SIGNING=false` to force an unsigned local archive.

The older Mac-side pipeline (`bun run release:local`, `archive` / `export` / `dmg` / `sign` / `appcast` / `github`) still exists as a fallback. Prefer the tag + Actions path.

## Safety

- Never force-push release tags unless explicitly requested.
- If the release commit/tag already exists, stop and inspect before retrying.
- If CI fails, fix forward with a new commit and tag unless you explicitly want to delete/recreate the tag.
- Keep release messages Conventional Commit compatible (`chore(release): vX.Y.Z`).

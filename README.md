# Blather

Compose once, publish to your own accounts on **X**, **Bluesky**, **Threads**,
**Instagram**, and **LinkedIn** — from a local-only native macOS app. No hosted backend, no
telemetry, no third-party aggregation API. Your provider credentials live in macOS Keychain;
everything else lives in a local SQLite database.

## Requirements

- macOS 15 or later
- Xcode 26 or later (to build from source)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Your own developer apps/accounts for each network you want to use (see below)
- A Cloudflare R2 bucket if you want to publish media to Threads or Instagram

## Getting started

```sh
bun run dev
```

That regenerates `Blather.xcodeproj` and opens it. Select the **Blather** scheme and press **Cmd+R**.

Or from the command line:

```sh
bun run build
```

The Debug app is under Xcode DerivedData. [Bun](https://bun.sh) is only used for these repo scripts, not by the app itself.

Go to **Blather > Settings…** (Cmd+,), connect the accounts you want, configure R2 staging if you
plan to post media to Threads or Instagram, then compose and publish. OAuth authorization opens
in your system browser; return to Blather after the browser displays a completion message.

Keep Blather open while connecting an account. OAuth providers send the browser back to
`https://127.0.0.1:3000`. Port 3000 must be free during that handshake. The first connection
creates a local TLS certificate under `~/.blather/oauth-tls/`; the browser may warn once that the
certificate is self-signed.

## Social network setup

Blather talks directly to each provider's native API. You can connect multiple accounts on each
network and select any combination of accounts for a post.

Begin with the [social network setup overview](docs/README.md), then follow the separate guide for
each network:

- [X](docs/x.md)
- [Bluesky](docs/bluesky.md)
- [Threads](docs/threads.md)
- [Instagram](docs/instagram.md)
- [LinkedIn](docs/linkedin.md)

Media posts to Threads and Instagram also require the
[Cloudflare R2 staging setup](docs/cloudflare-r2.md). LinkedIn uploads media
directly and never needs R2.

## Data locations

Everything lives under the data directory (default `~/.blather`, override with
`BLATHER_DATA_DIR`):

| What | Where |
| --- | --- |
| Drafts, overrides, publish attempts, connection metadata, staging records | `~/.blather/blather.db` (SQLite, mode 0600) |
| Uploaded source media | `~/.blather/media/` (dir mode 0700) |
| Local OAuth TLS identity | `~/.blather/oauth-tls/` |
| API secrets, per-account OAuth tokens, app passwords, R2 keys | macOS Keychain, service prefix `com.blather.*` |

SQLite stores only **opaque credential references**; resolving a reference requires the
Keychain. Deleting the database does not leak secrets, and deleting Keychain entries
(via Disconnect in Settings) does not touch your drafts.

Secrets are entered through the Settings UI only.

## Security model and limitations

- There is no hosted server. Outgoing HTTPS goes to X, Bluesky, Meta, LinkedIn, and R2.
  Incoming HTTPS is only the ephemeral OAuth callback listener on `127.0.0.1:3000`.
- OAuth callbacks verify single-use state parameters (CSRF) and PKCE verifiers (X).
- Logs and stored history errors are redacted: bearer tokens, `access_token` fields,
  client secrets, and signed staging URLs never persist.
- Uploads are streamed to disk with an explicit 512 MB cap.
- Publish attempts interrupted by a crash are marked `failed` at startup and never
  auto-retried (providers are not idempotent; retry manually from History after
  checking the network).
- Retries are only possible for failed destinations, so a partial success can never
  duplicate an already-published post.
- Each retry remains tied to the original account. Blather never substitutes another account on
  the same network.

**Limitations:** this is a single-user, single-machine tool. Any process running as your user can
read the database and request Keychain items.

## Development

```sh
bun run generate   # xcodegen generate
bun run build      # Debug build
bun run test       # unit tests
bun run keys       # Sparkle EdDSA keypair (once; private key stays in Keychain)
bun run bump -- 0.2.0
bun run signing:import   # Developer ID + notarytool profile from another Mac
bun run build:release    # signed + notarized dist/Blather.app
```

Unit tests use an in-memory SQLite database and a memory Keychain.

UI tests live in `BlatherUITests` and launch with `-mockProviders` so no external network is
contacted. Instagram's mock always fails so partial-failure and retry flows are exercised. Run
them from Xcode with **Product > Test** (a signing team is required for the UI test runner).

**Real-network smoke tests are manual**: they require your developer apps, accounts,
permissions, and R2 credentials. Connect in Settings, run the health checks, and publish
a low-stakes post per network.

## Release

Releases follow the same flow as Toby: `release-it` bumps and tags locally; GitHub Actions
builds, signs, notarizes, and publishes.

```sh
bun run release -- patch --ci
bun run release -- minor --ci
bun run release -- major --ci
```

`--ci` skips `release-it` prompts. The tag push (`v*`) runs
[`.github/workflows/release.yml`](.github/workflows/release.yml). See
[docs/release.md](docs/release.md) for secrets, Sparkle, and the local fallback.

## Architecture

```
Blather/
  App/            SwiftUI app entry, menus, Sparkle updater
  AppModel/       observable compose session and persistence wiring
  Domain/         types, capabilities, validation, overrides
  Persistence/    GRDB SQLite schema and repositories
  Security/       Keychain + credential refs + redaction
  Media/          NSOpenPanel, drag/drop, paste, thumbnails
  Networking/     URLSession JSON client
  OAuth/          PKCE, loopback HTTPS callback, connect flows
  Providers/      X / Bluesky / Threads / Instagram / LinkedIn / mock adapters
  Publish/        orchestrator and crash recovery
  R2/             SigV4 staging client
  Views/          Compose, History, inspector
  Settings/       Cmd+, window (Accounts, Media Staging, General, About)
BlatherTests/     Swift Testing
BlatherUITests/   XCUITest compose → publish → retry
```

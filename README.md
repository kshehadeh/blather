# Blather

Compose once, publish to your own accounts on **X**, **Bluesky**, **Threads**, and
**Instagram** — from a local-only macOS app. No hosted backend, no telemetry, no third-party
aggregation API. Your provider credentials live in macOS Keychain; everything else lives in a
local SQLite database.

## Requirements

- macOS (credentials are stored via the Keychain `security` CLI)
- [Bun](https://bun.sh) 1.3+ (used as the package manager and script runner)
- Node.js 22+ (Next.js runtime; Bun manages it via your existing install)
- [mkcert](https://github.com/FiloSottile/mkcert) (`brew install mkcert && mkcert -install`) —
  used by Blather's local server to serve trusted HTTPS, which Meta requires for OAuth callbacks
- Your own developer apps/accounts for each network you want to use (see below)
- A Cloudflare R2 bucket if you want to publish media to Threads or Instagram

## Getting started

```sh
bun install
bun run dev
```

This builds and opens the Electron app, which starts a local HTTPS server at
`https://127.0.0.1:3000`. The Electron window is the supported application UI; do not use the
local URL directly.

The local certificate is issued by mkcert and stored in `certificates/`. If a system browser
warns about the certificate during an OAuth connection, run `mkcert -install` once, then restart
Blather. The callback origin and port are fixed, so port 3000 must be free.

Go to **Settings**, connect the networks you want, configure R2 staging if you plan to post media
to Threads/Instagram, then compose and publish. OAuth authorization opens in your system browser;
return to Blather after the browser displays a completion message.

```sh
bun run build      # creates an unsigned DMG under release/
bun run build:dir  # creates an unpacked .app for local testing
```

The DMG is unsigned and may prompt for confirmation in macOS Gatekeeper. This first version is
macOS-only because it uses the macOS Keychain `security` CLI.

The embedded server binds to `127.0.0.1` only. Non-loopback Host headers and cross-site mutations
are rejected regardless.

## Provider developer-app prerequisites

Blather talks to each provider's native API using **your own** developer app. One account
per network is supported.

### X (Twitter)

1. Create a project + app at https://developer.x.com with **Read and Write** permissions.
2. Set the app type to a **public client** with **OAuth 2.0** enabled.
3. Add the callback URL: `https://127.0.0.1:3000/api/connect/x/callback`.
4. In Blather Settings, paste the app's **Client ID**.

**X media uploads:** Blather uses X's OAuth 2.0 v2 media-upload endpoints and requests the
`media.write` scope when connecting. If a media upload is denied, disconnect and reconnect X
to grant that scope. Tokens refresh automatically via the `offline.access` scope.

### Bluesky

1. Use your handle (e.g. `you.bsky.social`) and an **app password**
   (Settings → Privacy and security → App passwords). Do not use your main password.
2. If your account is on a non-default PDS, enter its URL; otherwise leave the default
   `https://bsky.social`.

Bluesky limits each post image to 1 MB. When a non-GIF image is larger, Blather creates a
temporary, smaller JPEG for that Bluesky upload and then deletes it, leaving the original
file unchanged. Bluesky sessions are refreshed automatically. Video uploads go through
Bluesky's asynchronous video service and are polled until processing completes.

### Threads

1. Create a Meta developer app at https://developers.facebook.com with the **Threads API**
   use case.
2. Under the Threads API settings add the callback URL:
   `https://127.0.0.1:3000/api/connect/threads/callback`
3. In Blather Settings, paste the app's **App ID** and **App Secret**. Find both in
   Meta for Developers: **My Apps** → select your app → **App settings** → **Basic**.

Short-lived tokens are exchanged for 60-day tokens, which are refreshed server-side
before they expire.

### Instagram

1. Your Instagram account must be a **professional account** (Business or Creator).
   Personal accounts cannot publish via the API — the Settings status card reports this.
2. Create a Meta developer app with **Instagram API with Instagram Login**
   (`instagram_business_basic` + `instagram_business_content_publish` scopes).
3. Add the callback URL: `https://127.0.0.1:3000/api/connect/instagram/callback`
4. In Blather Settings, paste the app's **App ID** and **App Secret**. Find both in
   Meta for Developers: **My Apps** → select your app → **App settings** → **Basic**.

### Cloudflare R2 staging (required for Threads/Instagram media)

Meta fetches media from a public HTTPS URL, so Blather stages media temporarily into an
Cloudflare R2 bucket you own, then deletes the objects after publishing. Anything left
behind (crash, interruption) is swept at startup after a 24-hour window.

Settings fields:

- **Account ID / Bucket** — your Cloudflare account ID and R2 bucket name. Blather derives the
  R2 S3-compatible API endpoint and uses path-style addressing.
- **Public URL strategy**:
  - `Presigned URLs` (default): the bucket can stay fully private. Presigned GET URLs
    valid for 1 hour are handed to Meta.
  - `Public R2 bucket URL`: objects are world-readable through a custom domain or R2.dev URL.
    Provide its full base URL (for example, `https://media.example.com`). Your R2 public
    bucket policy and CORS configuration should allow GET from any origin, e.g.:

    ```json
    [
      {
        "AllowedOrigins": ["*"],
        "AllowedMethods": ["GET"],
        "AllowedHeaders": ["*"],
        "MaxAgeSeconds": 3000
      }
    ]
    ```
- **Access credentials** — stored in Keychain, never in SQLite or on disk in plaintext.

The R2 API token needs Object Read & Write permission for the selected bucket.

## Data locations

Everything lives under the data directory (default `~/.blather`, override with
`BLATHER_DATA_DIR`):

| What | Where |
| --- | --- |
| Drafts, overrides, publish attempts, connection metadata, staging records | `~/.blather/blather.db` (SQLite, mode 0600) |
| Uploaded source media | `~/.blather/media/` (dir mode 0700) |
| API secrets, OAuth tokens, app passwords, R2 keys | macOS Keychain, service prefix `com.blather.*` |

SQLite stores only **opaque credential references**; resolving a reference requires the
Keychain. Deleting the database does not leak secrets, and deleting Keychain entries
(via Disconnect in Settings) does not touch your drafts.

`.env.example` documents the only supported env vars — all non-secret. Secrets are
entered through the Settings UI only.

## Security model and limitations

- The server binds to loopback and rejects non-loopback Host headers.
- Mutating API requests must be same-origin (Origin + Sec-Fetch-Site checks).
- OAuth callbacks verify single-use state parameters (CSRF) and PKCE verifiers (X).
- Logs and stored history errors are redacted: bearer tokens, `access_token` fields,
  client secrets, and signed staging URLs never persist.
- Uploads are streamed to disk with explicit size caps (512 MB), never buffered whole.
- Publish attempts interrupted by a crash are marked `failed` at startup and never
  auto-retried (providers are not idempotent; retry manually from History after
  checking the network).
- Retries are only possible for failed destinations, so a partial success can never
  duplicate an already-published post.

**Limitations:** there is no authentication on the UI — it trusts the loopback boundary.
Any process running as your user can read the database and request Keychain items. This
is a single-user, single-machine tool; do not expose it beyond localhost.

## Development

```sh
bun run lint         # Biome check
bun run format       # Biome format --write
bun run typecheck    # tsc --noEmit
bun run test         # Vitest unit + integration
bun run test:e2e     # Playwright (mock providers; no external calls)
bun run build        # production build
```

Tests use fakes selected by env vars (`BLATHER_KEYCHAIN=memory`, `BLATHER_R2=fake`,
`BLATHER_MOCK_PROVIDERS=1`) so nothing external is contacted. Playwright launches Electron
against mock provider adapters; Instagram's mock always fails so partial-failure and retry flows
are exercised.

**Real-network smoke tests are manual**: they require your developer apps, accounts,
permissions, and R2 credentials. Connect in Settings, run the health checks, and publish
a low-stakes post per network.

## Architecture

```
src/
  lib/            shared types + provider capability metadata (client-safe)
  server/
    db/           SQLite schema + repositories (no secrets)
    keychain.ts   macOS Keychain via `security` CLI (in-memory for tests)
    credentials.ts  opaque refs <-> Keychain blobs
    providers/    adapter contract + x / bluesky / threads / instagram / mock
    publish/      orchestrator (bounded concurrency), override resolution, recovery
    s3.ts         staging, presigned/public URLs, orphan cleanup
    security.ts   loopback + same-origin guards, redaction
    oauth.ts      PKCE + single-use state
  app/            App Router pages (composer, history, settings) + API routes
tests/
  unit/           validation, overrides, credentials, errors, adapters (mocked HTTP)
  integration/    SQLite repos, OAuth state/PKCE, partial success + retry, S3 cleanup
  e2e/            Playwright flows against mock providers
```

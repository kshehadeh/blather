# Social network setup

Blather can connect multiple accounts on each network. When composing, select every individual
account that should receive the post.

| Network | What you need | Setup guide |
| --- | --- | --- |
| X | An X developer project and OAuth 2.0 app | [Set up X](x.md) |
| Bluesky | Your handle and a Bluesky app password | [Set up Bluesky](bluesky.md) |
| Threads | A Meta developer app with the Threads API | [Set up Threads](threads.md) |
| Instagram | A professional Instagram account and a Meta developer app | [Set up Instagram](instagram.md) |
| LinkedIn | A LinkedIn developer app with Share on LinkedIn | [Set up LinkedIn](linkedin.md) |

Threads and Instagram also need [Cloudflare R2](cloudflare-r2.md) when a post contains an image
or video. Text-only Threads posts do not need R2. Instagram always needs R2 because Instagram
requires media. LinkedIn uploads media directly and never needs R2.

## Before setting up a network

1. Install and start Blather by following the [main README](../README.md#getting-started).
2. Confirm that the Blather window opens. Compose is the default view; Settings is **Cmd+,**.
3. Keep Blather running while connecting an account. OAuth providers send your browser back to
   Blather at `https://127.0.0.1:3000`.
4. If the browser warns that the local certificate is unsafe, continue for this local address
   (Blather generates a self-signed identity under `~/.blather/oauth-tls/` on first connect).
5. Make sure no other program is using port `3000` while you connect.

## Using multiple accounts

Expand a network in **Settings > Accounts**, then select **Add Account…** for each identity you
want to connect. During browser authorization, verify that the provider shows the intended
account. Blather identifies accounts by the provider's stable user ID, so reconnecting an
existing identity updates it instead of creating a duplicate.

The composer groups accounts by network. You can select several accounts from the same network
for one post. Destination overrides are shared by network, so every selected X account receives
the same X override, for example. Progress, History, failures, and retries remain separate for
each account. If an account is removed, drafts and History retain its identity, but it must be
reconnected before publishing or retrying.

## Terms used in these guides

- **Developer app:** A configuration in a social network's developer portal. It gives Blather
  permission to act on your behalf. It is not a second copy of Blather.
- **App ID or Client ID:** A public identifier for a developer app. Blather uses it to begin a
  connection.
- **App Secret:** A private password for a developer app. Do not post it, commit it, or send it to
  anyone.
- **Callback URL or Redirect URI:** The exact address to which a network returns your browser
  after you approve access. These terms mean the same thing in these guides.
- **Scope or permission:** One specific action that you allow Blather to perform, such as creating
  a post.
- **Development mode:** A provider mode in which only the app owner, administrators, developers,
  or invited testers can connect. This is normally sufficient when you only publish to your own
  account.
- **PDS:** A Bluesky Personal Data Server. Most people use Bluesky's default PDS and do not need
  to change it.

## Where secrets are stored

Enter network credentials only in **Blather > Settings…** (Cmd+,). Blather stores secrets and
access tokens in macOS Keychain. They do not belong in environment files, and Blather does not
store them in its SQLite database.

## A note about provider screens

Social networks change their developer portals frequently. A menu may have a slightly different
name than the one shown in these guides. Look for the bold field names and use the exact URLs,
permissions, and values documented here. The guides include links to the providers' official
documentation when the portal layout is unclear.

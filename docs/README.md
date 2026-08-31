# Social network setup

Blather can publish to one account on each of these networks. You only need to set up the
networks you intend to use.

| Network | What you need | Setup guide |
| --- | --- | --- |
| X | An X developer project and OAuth 2.0 app | [Set up X](x.md) |
| Bluesky | Your handle and a Bluesky app password | [Set up Bluesky](bluesky.md) |
| Threads | A Meta developer app with the Threads API | [Set up Threads](threads.md) |
| Instagram | A professional Instagram account and a Meta developer app | [Set up Instagram](instagram.md) |

Threads and Instagram also need [Cloudflare R2](cloudflare-r2.md) when a post contains an image
or video. Text-only Threads posts do not need R2. Instagram always needs R2 because Instagram
requires media.

## Before setting up a network

1. Install and start Blather by following the [main README](../README.md#getting-started).
2. Confirm that the Blather Electron window opens. The supported interface is the app window,
   not the local page opened directly in a browser.
3. Keep Blather running while connecting an account. OAuth providers send your browser back to
   Blather at `https://127.0.0.1:3000`.
4. If the browser warns that the local certificate is unsafe, quit Blather, run
   `mkcert -install`, and start Blather again.
5. Make sure no other program is using port `3000`.

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

Enter network credentials only in **Blather > Settings**. Blather stores secrets and access
tokens in macOS Keychain. They do not belong in `.env`, and Blather does not store them in its
SQLite database.

## A note about provider screens

Social networks change their developer portals frequently. A menu may have a slightly different
name than the one shown in these guides. Look for the bold field names and use the exact URLs,
permissions, and values documented here. The guides include links to the providers' official
documentation when the portal layout is unclear.

# Set up Bluesky

Bluesky is the simplest network to connect. You do not need a developer account, API key, OAuth
app, callback URL, or Cloudflare R2. You need your Bluesky handle and a dedicated app password.

## What you need

- The Bluesky account you want Blather to publish to
- Access to that account's settings
- Your account's PDS URL only if you use a custom Bluesky server

## 1. Find your handle

Your handle is the account name shown after `@`, for example `you.bsky.social` or
`social.example.com`. Enter it without the leading `@`.

Your display name is not your handle. For example, if the app shows **Ada (@ada.bsky.social)**,
the handle is `ada.bsky.social`.

## 2. Create an app password

An app password is a separate password that can be revoked without changing your main account
password. Never give Blather your main Bluesky password.

1. Sign in at [bsky.app](https://bsky.app/).
2. Open **Settings**.
3. Open **Privacy and security**.
4. Open **App passwords**.
5. Select **Add app password**.
6. Give it a recognizable name such as `Blather`.
7. Create it and copy the generated password. Bluesky may only show it once.

If Bluesky's menu names have changed, use the Settings search or the official app-password link
in the references below.

## 3. Decide which PDS value to use

Most people use Bluesky's own server. For a normal `*.bsky.social` account, use:

```text
https://bsky.social
```

Only change this if your account administrator or hosting provider gave you a custom PDS URL. A
custom PDS value must be a complete HTTPS origin, such as `https://pds.example.com`; it is not
your profile URL or handle.

## 4. Connect Bluesky in Blather

1. Open **Blather > Settings**.
2. Find the **Bluesky** card.
3. Enter the PDS. Leave it blank to use `https://bsky.social`, or enter your custom PDS URL.
4. Enter your handle without `@` in **Handle**.
5. Paste the generated password into **App password**.
6. Select **Connect**.
7. Confirm that the card shows the correct `@handle` and shows **connected**.
8. Select **Run health checks** and confirm that no Bluesky error appears.

There is no browser approval screen. Blather verifies the credentials directly with your PDS and
stores the app password and session tokens in macOS Keychain.

## 5. Test publishing

1. Publish a short text-only test post to Bluesky.
2. If you use media, publish a second test with one image or video.
3. Delete the test posts in Bluesky if you no longer need them.

Blather supports up to 300 characters, up to four images, or one video. A post cannot mix images
and video. Bluesky limits each post image to 1,000,000 bytes; Blather automatically makes a
smaller temporary JPEG when possible without changing your original file. An oversized animated
GIF cannot be reduced this way and must be made smaller before upload.

## Troubleshooting

### The handle or password is invalid

Confirm that the handle has no leading `@` and that you used the generated app password, not your
normal account password. If you no longer have the generated value, revoke it in Bluesky and
create a new one.

### A custom-domain handle does not connect

A custom handle does not necessarily mean a custom PDS. If you only changed your handle but still
use Bluesky hosting, keep the PDS as `https://bsky.social`.

### The PDS connection fails

Make sure the value starts with `https://`, contains the PDS host only, and has no profile path.
Ask the PDS administrator for the server's public URL if you are unsure.

### An image is rejected as too large

Blather can optimize JPEG, PNG, and WebP still images, but it will not flatten an animated
GIF into a still image. Reduce an animated GIF below 1,000,000 bytes before attaching it.

### A previously working connection stops working

Check whether the app password was revoked in Bluesky. Blather refreshes sessions automatically,
but it cannot recover from a revoked app password; disconnect and connect again with a new one.

## Official references

- [Bluesky app passwords](https://bsky.app/settings/app-passwords)
- [Bluesky account hosting and PDSes](https://docs.bsky.app/docs/advanced-guides/entryway)

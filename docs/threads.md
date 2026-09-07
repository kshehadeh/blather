# Set up Threads

Threads uses a Meta developer app and browser-based OAuth. A text-only post needs only the Meta
app. Any post with an image or video also needs [Cloudflare R2](cloudflare-r2.md), because Meta's
servers must download the media from a public HTTPS URL while publishing.

## What you need

- The Threads account you want Blather to publish to
- A [Meta for Developers](https://developers.facebook.com/) account
- Permission to create or administer a Meta developer app
- Cloudflare R2 if you want to publish images or video

For personal use, leave the Meta app in development mode and connect an account that has an app
role, such as administrator, developer, or tester. Meta normally requires app review and possibly
business verification before people without an app role can connect. Blather is designed for
connecting your own account, not for operating a public login service.

## 1. Create a Meta app

1. Sign in to [Meta for Developers](https://developers.facebook.com/apps/).
2. Open **My Apps** and select **Create App**.
3. Choose the option that offers the **Threads API** use case. Meta may first ask you to choose
   **Other** or a business app type before it shows use cases.
4. Enter an app name and contact email, then create the app.
5. In the app dashboard, add or customize the **Threads API** use case if it was not added during
   creation.

Meta changes this wizard regularly. The important result is that the app dashboard lists the
**Threads API** and exposes its settings.

## 2. Configure the OAuth callback

Open the Threads API settings, then add this exact URL to **Redirect Callback URLs**, **Valid OAuth
Redirect URIs**, or the equivalently named field:

```text
https://127.0.0.1:3000/api/connect/threads/callback
```

Use `https`, `127.0.0.1`, and port `3000`. Do not substitute `localhost` or add a trailing slash.

Blather requests these permissions automatically:

- `threads_basic`, to identify the connected Threads account
- `threads_content_publish`, to create posts

Blather does not use Threads webhooks. If Meta shows optional webhook configuration, it is not
needed for Blather. If the portal requires deauthorization or data-deletion URLs before taking an
app live, note that Blather does not provide public endpoints for those flows; keep the app in
development mode for your own app-role account.

## 3. Give your Threads account access to the app

The app administrator's associated account may already be eligible. If Meta says the account is
not authorized:

1. Open **App roles** in the Meta app dashboard.
2. Add the account as an administrator, developer, or Threads tester, using whichever role the
   current portal offers.
3. Sign in to Threads as that account and accept the tester invitation if Meta sends one.
4. Return to the app dashboard and confirm the invitation is no longer pending.

An invited role is only for development access. It is not a Threads follower or profile role.

## 4. Copy the App ID and App Secret

1. In the Meta app dashboard, open **App settings > Basic**.
2. Copy **App ID**.
3. Next to **App Secret**, select **Show**. Meta may ask for your password.
4. Copy the revealed **App Secret**.

Treat the App Secret like a password. Do not commit it to Git.

## 5. Connect Threads in Blather

1. Keep Blather running.
2. Open **Blather > Settings…** (Cmd+,).
3. Open the **Accounts** tab and find the **Threads** section.
4. Select **Add Account…**.
5. Paste the Meta **App ID** and **App Secret**, then select **Connect Account**.
6. In the system browser, sign in to the intended Threads account and approve both permissions.
7. Wait for the completion message, then return to Blather.
8. Confirm that the Threads section shows the correct account and shows **connected**.
9. Select **Run health checks** and confirm that no Threads error appears.

Blather exchanges the initial token for a longer-lived token and refreshes it before it expires.
Repeat **Add Account…** while signed into each additional Threads identity you want to use.

## 6. Set up media publishing, if needed

Follow [Set up Cloudflare R2](cloudflare-r2.md), then use **Test connection** in Blather Settings.
You can skip this for text-only Threads posts.

## 7. Test publishing

1. Publish a short text-only test post first.
2. If R2 is configured, publish a second post with one image.
3. Confirm both posts appear on the intended Threads profile.
4. Delete the tests in Threads if you no longer need them.

Blather supports up to 500 characters, up to 20 images, and at most one video. Images and one
video may be mixed in a carousel. Threads may impose a lower total carousel-item count or stricter
format and account limits than Blather's initial checks.

## Troubleshooting

### Meta says the redirect URI is invalid or does not match

Copy the callback from this guide again. Make sure it is in the Threads API OAuth settings, not
only in a general app-domain or website field.

### Meta says the app is unavailable or the account has no role

While the app is in development mode, connect with an app administrator/developer account or add
the Threads account as a tester and accept the invitation.

### Blather reports an invalid App ID or App Secret

Copy both values from **App settings > Basic** in the same Meta app. Do not use an access token,
client token, Instagram app ID, or credentials from a different Meta app.

### Text posts work but media posts fail

This normally means R2 is missing or Meta could not fetch the staged URL. Open the
[R2 troubleshooting guide](cloudflare-r2.md#troubleshooting) and run **Test connection**.

### A permission was added after connecting

Disconnect and reconnect Threads. An existing token does not automatically gain a newly enabled
permission.

## Official references

- [Threads API documentation](https://developers.facebook.com/docs/threads/)
- [Threads API getting started](https://developers.facebook.com/docs/threads/get-started/)

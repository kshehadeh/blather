# Set up Instagram

Instagram publishing uses Meta's **Instagram API with Instagram Login**. It only supports
professional Instagram accounts: **Business** or **Creator**. Personal accounts cannot publish
through Blather.

Instagram posts must contain media, and Meta must fetch that media over HTTPS. You must therefore
set up both a Meta developer app and [Cloudflare R2](cloudflare-r2.md).

## What you need

- The Instagram account you want Blather to publish to
- That account configured as **Business** or **Creator**
- A [Meta for Developers](https://developers.facebook.com/) account
- A Cloudflare account and R2 bucket

This guide uses direct Instagram Login and its `instagram_business_*` permissions. Do not mix it
with older guides for **Instagram API with Facebook Login**, which use Facebook Login, different
permissions, and a Facebook Page. Blather's direct Instagram Login flow does not ask you for a
Facebook Page.

For personal use, keep the Meta app in development mode and connect an account that has an app
role or tester access. Connecting arbitrary users generally requires Meta app review and possibly
business verification.

## 1. Convert the Instagram account to professional

Skip this section if the account is already Business or Creator.

1. Sign in to the Instagram account in Instagram's mobile app.
2. Open the profile menu and **Settings and privacy**.
3. Find **Account type and tools** or **For professionals**.
4. Choose **Switch to professional account**.
5. Select **Creator** or **Business** and complete Instagram's prompts.
6. Reopen the account settings and confirm the professional account type is shown.

Switching account type changes Instagram features and may change profile privacy options. Review
Instagram's prompts before confirming.

## 2. Create a Meta app

1. Sign in to [Meta for Developers](https://developers.facebook.com/apps/).
2. Open **My Apps** and select **Create App**.
3. Choose a creation path that offers **Instagram API with Instagram Login**. Meta may ask you to
   choose **Other** and then a business app type before products or use cases appear.
4. Enter an app name and contact email, then create the app.
5. Add **Instagram API with Instagram Login** to the app if it was not added during creation.

Do not select an older Facebook Login integration merely because another tutorial does. You can
confirm the correct product by checking that its permissions are named
`instagram_business_basic` and `instagram_business_content_publish`.

## 3. Configure Instagram Login

Open the Instagram product's **API setup**, **Instagram Login settings**, or similarly named page.
Add this exact value to **Valid OAuth Redirect URIs**:

```text
https://127.0.0.1:3000/api/connect/instagram/callback
```

Use `https`, `127.0.0.1`, and port `3000`. Do not use `localhost` and do not add a trailing slash.

Blather requests these permissions automatically:

- `instagram_business_basic`, to identify and check the connected account
- `instagram_business_content_publish`, to create posts

Blather does not use Instagram webhooks. If Meta requires public deauthorization or data-deletion
URLs before an app can go live, Blather does not provide those public endpoints. For publishing
to your own app-role/tester account, keep the app in development mode.

## 4. Add the Instagram account as a tester, if required

If the professional account is not already available to the app:

1. In the Meta app dashboard, open the Instagram product's setup page or **App roles**.
2. Add the Instagram username under **Instagram testers** or the equivalent role.
3. Sign in to that Instagram account.
4. Open its app and website permissions or tester invitations and accept the invitation.
5. Return to the Meta dashboard and confirm that the invitation is accepted rather than pending.

Meta periodically moves tester controls. The account must have accepted access; sending an
invitation alone is not enough.

## 5. Copy the Instagram App ID and App Secret

1. Return to the same Instagram product **API setup** or **Instagram Login settings** page where
   you configured the redirect URI.
2. Find and copy the **Instagram App ID**.
3. Find **Instagram App Secret**, select **Show** if necessary, and complete any security prompt.
4. Copy the revealed **Instagram App Secret**.

Meta may also display a general Meta **App ID** and **App Secret** under **App settings > Basic**.
For this direct Instagram Login flow, use the Instagram credentials shown in the Instagram
product setup. Keep the secret private and do not put it in `.env`.

## 6. Connect Instagram in Blather

1. Keep Blather running.
2. Open **Blather > Settings**.
3. Find the **Instagram** card.
4. Paste the Meta **App ID** and **App Secret**.
5. Select **Connect**.
6. In the system browser, sign in to the intended professional Instagram account and approve the
   requested access.
7. Wait for the completion message, then return to Blather.
8. Confirm that Blather shows the correct username and shows **connected**.
9. Select **Run health checks**. Blather reports an error if Instagram does not identify the
   account as Business or Creator.

Blather exchanges the initial token for a longer-lived token and refreshes it before it expires.

## 7. Configure Cloudflare R2

Complete [Set up Cloudflare R2](cloudflare-r2.md), save the values in Blather Settings, and select
**Test connection**. Instagram publishing cannot work without R2 because every Instagram post
requires media.

## 8. Test publishing

1. Create a low-stakes post with a single JPEG or PNG and a short caption.
2. Publish only to Instagram.
3. Confirm it appears on the intended profile.
4. Delete the test in Instagram if you no longer need it.

Blather requires media, allows captions up to 2,200 characters, supports up to ten images in a
carousel, or one video. A single video is published as a Reel. Blather does not allow mixing
images and video in one Instagram post. Its effective accepted video duration is 3 to 600 seconds.
Provider-side encoding, aspect-ratio, or account limits can be stricter.

## Troubleshooting

### Blather says the account must be Business or Creator

The connected account is still Personal, or Instagram has not finished applying the account-type
change. Confirm the type in Instagram, disconnect it in Blather, and connect again.

### Meta says the redirect URI is invalid

Make sure the callback is listed in the **Instagram Login** product settings. Adding it only as a
website URL, app domain, or Facebook Login redirect does not configure this flow.

### The account does not appear or cannot authorize

Confirm that you added the exact Instagram account as a tester and accepted the invitation while
signed in as that account. Also confirm that the app is using Instagram Login rather than the
older Facebook Login product.

### Blather reports an invalid App ID or App Secret

Copy the **Instagram App ID** and **Instagram App Secret** from the Instagram product's API setup,
not the general values under **App settings > Basic**. Do not paste an access token, Facebook Page
ID, client token, or credentials from another app.

### Connection works but every publish fails

Run the R2 **Test connection** first. Then try one ordinary JPEG. A successful R2 API test proves
Blather can access the bucket, but Meta must also be able to download the generated HTTPS URL.
See [R2 troubleshooting](cloudflare-r2.md#troubleshooting).

### A permission was enabled after connecting

Disconnect and reconnect Instagram so the account can approve the current permissions.

## Official references

- [Instagram API with Instagram Login](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/)
- [Instagram content publishing](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/content-publishing/)

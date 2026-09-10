# Set up LinkedIn

LinkedIn publishing uses your personal profile. Company (organization) pages are not supported.
You need a LinkedIn developer app with two products added; it takes a few minutes and LinkedIn
reviews them automatically for self-serve posting.

## What you need

- The LinkedIn account whose personal profile you want to publish to
- A LinkedIn developer app you create (below)
- A LinkedIn Page you administer, or a colleague who administers one (see step 1)

No Cloudflare R2 setup is needed. Media is uploaded directly to LinkedIn.

## 1. Create a LinkedIn developer app

1. Go to [LinkedIn Developers](https://www.linkedin.com/developers/) and select **Create app**.
2. Give the app a name such as `Blather` and attach it to a LinkedIn Page. LinkedIn requires
   every app to be associated with a Page; that Page is only the app's publisher. Blather never
   posts to it, and the Page can be any page you or your company administers.
3. Accept the API terms and create the app.

You do not need to request review beyond the self-serve products below. Development mode is
normally sufficient when you only publish to your own profile.

## 2. Add the required products

In your app, open the **Products** tab and request both of these products:

- **Share on LinkedIn** — grants the `w_member_social` permission used to create posts.
- **Sign In with LinkedIn using OpenID Connect** — grants the `openid` and `profile` scopes used
  to identify which member connected, so Blather can label and bind the account.

Both products are self-serve. After LinkedIn approves them (usually immediate), the scopes
appear on the app's **Auth** tab.

## 3. Register the callback URL and copy your credentials

1. Open the **Auth** tab of your app.
2. Under **Redirect URLs**, add this exact URL:

   ```text
   https://127.0.0.1:3000/api/connect/linkedin/callback
   ```

3. Copy the **Client ID**.
4. Select/reveal the **Client Secret** and copy it. Treat the secret like a password.

## 4. Connect LinkedIn in Blather

1. Open **Blather > Settings…** (Cmd+,).
2. Open the **Accounts** tab and find the **LinkedIn** section.
3. Select **Add Account…**.
4. Paste the Client ID and Client Secret.
5. Select **Connect Account**. Your browser opens LinkedIn's approval screen.
6. Sign in with the LinkedIn account whose profile you want to publish to and select **Allow**.
   Blather identifies the account by LinkedIn's stable member ID, so reconnecting an existing
   identity updates it instead of creating a duplicate.
7. Return to Blather and confirm the section shows your name and **connected**.
8. Select **Run health checks** and confirm that no LinkedIn error appears.

Keep Blather open while connecting, and make sure nothing else is using port `3000` during the
browser handshake.

Repeat **Add Account…** for each additional LinkedIn identity.

## 5. Test publishing

1. Publish a short text-only test post to LinkedIn.
2. If you use media, publish a second test with an image, and a third with a short MP4 video.
3. Delete the test posts in LinkedIn if you no longer need them.

Blather supports up to 3,000 characters, up to 20 images per post, or one video. Video must be
MP4, at least 3 seconds, and under 500MB. Images must contain fewer than 36,152,320 pixels. A
post cannot mix images and video. LinkedIn applies rate limits per member per day (currently 150
requests), which Blather treats as a temporary failure you can retry from History.

## Session expiry

LinkedIn issues access tokens that last about 60 days and does not offer automatic renewal for
self-serve apps. Blather stores the expiry, marks the account with an error when the session
expires, and asks you to reconnect. Reconnecting takes a few seconds and keeps the same account
history.

## Troubleshooting

### The callback URL is rejected

Confirm the Redirect URL in LinkedIn's **Auth** tab matches
`https://127.0.0.1:3000/api/connect/linkedin/callback` exactly, including `https`, the port, and
the full path.

### Authorization fails with a permissions error

Make sure both products from step 2 are added and approved, then reconnect. If the scopes of an
existing grant change, LinkedIn requires the member to approve the app again.

### Publishing fails with a permissions or 403 error

The `w_member_social` permission is write-only on some LinkedIn reads. Blather avoids those
reads, so a 403 during publishing usually means the app is missing the **Share on LinkedIn**
product or the connected member changed. Reconnect after fixing the app configuration.

### A previously working connection stops working

The session may have expired (see [Session expiry](#session-expiry)) or been revoked from the
member's settings. Run health checks; if the account shows an error, reconnect it.

## Official references

- [Share on LinkedIn](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/share-on-linkedin)
- [Sign In with LinkedIn using OpenID Connect](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2)
- [Posts API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api)
- [Images API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/images-api)
- [Videos API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/videos-api)

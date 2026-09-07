# Set up X

X requires an X developer account and an OAuth 2.0 app. Blather uses OAuth 2.0 with PKCE, so you
enter a **Client ID** but not a client secret.

## What you need

- The X account you want Blather to publish to
- Access to the [X Developer Portal](https://developer.x.com/)
- An X API plan that permits creating posts and any media operations you need

X controls API access and pricing. A developer app can be configured correctly and still receive
rate-limit or plan-related errors. In particular, media upload may not be available on every
plan.

## 1. Create a project and app

1. Sign in to the [X Developer Portal](https://developer.x.com/) with the X account that owns the
   developer project.
2. Create a project if you do not already have one.
3. Create an app inside that project.
4. Open the app's **User authentication settings**. Depending on the current portal, this may be
   under **Settings** or have a **Set up** or **Edit** button.

Creating an app may show an API key, API key secret, and bearer token. Blather does not use those
values. Do not paste any of them into Blather.

## 2. Configure user authentication

Set the app's user authentication values as follows:

| X field | Value |
| --- | --- |
| OAuth version | **OAuth 2.0** |
| App permissions | **Read and write** |
| Type of App | A public-client option, normally **Native App** |
| Callback URI / Redirect URL | `https://127.0.0.1:3000/api/connect/x/callback` |
| Website URL | A valid URL required by X; use your own site or this repository's URL |

The callback must match exactly. Use `https`, the numeric address `127.0.0.1`, port `3000`, and no
trailing slash.

Blather asks X for these scopes during connection:

- `tweet.read`
- `tweet.write`
- `users.read`
- `offline.access`
- `media.write`

You do not normally type these scopes into X individually. **Read and write** and the OAuth 2.0
settings make them available; Blather includes them in the authorization request.

## 3. Copy the Client ID

1. Save the user authentication settings.
2. Open the app's **Keys and tokens** page.
3. Find **OAuth 2.0 Client ID and Client Secret**.
4. Copy the **Client ID**. Ignore the Client Secret because Blather is a public PKCE client.

The Client ID is different from the app's API Key, App ID, and bearer token.

## 4. Connect X in Blather

1. Open **Blather > Settings…** (Cmd+,).
2. Open the **Accounts** tab and find the **X** section.
3. Select **Add Account…**.
4. Paste the OAuth 2.0 **Client ID** into **Client ID**, then select **Connect Account**.
5. Your system browser opens X. Sign in to the account that Blather should publish to and approve
   the requested access.
6. Wait for the browser to show the completion message, then return to Blather.
7. Confirm that the X section names the correct account and shows **connected**.
8. Select **Run health checks** and confirm that no X error appears.

Repeat **Add Account…** while signed into each additional X identity you want to use.

## 5. Test publishing

1. Publish a short text-only test post to X.
2. If you intend to publish media, publish a second low-stakes post with one image.
3. Delete the test posts on X if you no longer need them.

Blather supports up to 280 characters, up to four images, or one video. A post cannot mix images
and video.

## Troubleshooting

### X says the callback or redirect URI is invalid

Compare the portal value character by character with:

```text
https://127.0.0.1:3000/api/connect/x/callback
```

`http://`, `localhost`, another port, or an added trailing slash is a different callback.

### Blather says the client is invalid

Confirm that you copied the **OAuth 2.0 Client ID**, not the API Key, App ID, client secret, or
bearer token. Also confirm that the app is configured as a public/native OAuth 2.0 client.

### Posting is read-only or forbidden

Change **App permissions** to **Read and write**, save the setting, then disconnect and reconnect X
in Blather. Existing access tokens do not automatically gain newly enabled permissions.

### Media upload says `media.write` is missing or is denied

Disconnect and reconnect X so that the latest `media.write` scope is approved. If it still fails,
check whether your X API plan permits the v2 media-upload endpoints.

### The browser cannot return to Blather

Keep Blather running, make sure port `3000` is free, and accept any local certificate warning as
described in the [setup overview](README.md#before-setting-up-a-network).

## Official references

- [X OAuth 2.0 authorization code flow with PKCE](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code)
- [X API access and versions](https://docs.x.com/x-api/getting-started/about-x-api)

# Set up Cloudflare R2 for Meta media

Threads and Instagram do not accept a file directly from Blather. Meta asks for an HTTPS URL and
downloads the file itself. Blather temporarily uploads each file to a Cloudflare R2 bucket, gives
Meta either a one-hour presigned URL or the configured public bucket URL, and deletes the object
after publishing.

- R2 is required for Threads posts that contain media.
- R2 is not required for text-only Threads posts.
- R2 is always required for Instagram because Instagram requires media.
- X and Bluesky do not use R2.

Blather also removes abandoned staging objects older than 24 hours when it starts.

## What you need

- A [Cloudflare](https://dash.cloudflare.com/) account
- Permission to create an R2 bucket and R2 API token
- R2 enabled for the Cloudflare account

R2 usage may incur Cloudflare charges. Review Cloudflare's current pricing before continuing.

## 1. Find the Cloudflare Account ID

1. Sign in to the [Cloudflare dashboard](https://dash.cloudflare.com/).
2. Select the account, not an individual website.
3. Open **R2 Object Storage**.
4. Find and copy the **Account ID**. It is also commonly shown in the account's overview or R2 API
   information.

The Account ID is not a zone ID, user ID, bucket name, access key, or token value.

## 2. Create a bucket

1. In **R2 Object Storage**, select **Create bucket**.
2. Choose a bucket name, such as `blather-media`.
3. Create the bucket and copy its exact name.

Use a dedicated bucket if possible. Blather deletes the objects that it creates, and isolation
makes access permissions and troubleshooting simpler.

## 3. Create R2 API credentials

Blather uses R2's S3-compatible API. It needs an **Access Key ID** and **Secret Access Key**, not a
general Cloudflare API token copied from the main API Tokens page.

1. From **R2 Object Storage**, open **Manage R2 API Tokens** or **API**.
2. Select **Create API token**.
3. Give it a recognizable name such as `Blather`.
4. Grant **Object Read & Write** access.
5. Restrict the token to the bucket you created, if Cloudflare offers bucket restrictions.
6. Create the token.
7. Copy both **Access Key ID** and **Secret Access Key** immediately. Cloudflare may show the secret
   only once.

The test performed by Blather also checks that the bucket is reachable. If a narrowly customized
policy denies the bucket check, use Cloudflare's standard R2 Object Read & Write permission for
that bucket.

Do not paste Cloudflare's token string, Account API Token, S3 endpoint, or jurisdiction-specific
endpoint into either key field.

## 4. Choose a media URL strategy

Blather supports two strategies.

### Recommended: Presigned URLs

Choose **Presigned URLs, bucket stays private** unless you already operate a public R2 domain.
Blather generates HTTPS download URLs that expire after one hour. You do not need to enable
R2.dev, add a custom domain, make the bucket public, or configure browser CORS for this strategy.

### Optional: Public R2 bucket URL

Choose **Public R2 bucket URL** only if the bucket already has an R2.dev URL or custom domain that
serves objects publicly.

1. In the bucket's **Settings**, enable public development access or attach a custom domain.
2. Copy the public base URL, for example `https://pub-example.r2.dev` or
   `https://media.example.com`.
3. Verify the domain uses HTTPS.

Do not use the S3 API endpoint
`https://ACCOUNT_ID.r2.cloudflarestorage.com` as the public base URL. That endpoint is for signed
API operations and is not a public bucket website.

## 5. Enter R2 settings in Blather

1. Open **Blather > Settings**.
2. Find **Cloudflare R2 staging**.
3. Enter the Cloudflare **Account ID**.
4. Enter the exact **Bucket** name.
5. Choose **Presigned URLs, bucket stays private** unless you intentionally configured a public
   URL.
6. For the presigned strategy, leave **Public R2 bucket URL** blank.
7. For the public strategy, enter the complete HTTPS public base URL.
8. Enter the R2 **Access Key ID** and **Secret Access Key**.
9. Select **Save**.
10. Select **Test connection** and confirm that Blather shows **Connection OK**.

The keys are stored in macOS Keychain. When editing an existing configuration, leave both key
fields blank to keep the saved credentials.

## 6. Test the complete media path

**Test connection** checks Blather's access to the bucket, but it does not ask Meta to fetch a
file. Complete one end-to-end test:

1. Attach one ordinary JPEG to a low-stakes Threads or Instagram post.
2. Publish only to that network.
3. Confirm the post appears with its image.
4. Delete the social post if you no longer need it.

Blather removes the staged object after success or failure. Do not expect the bucket to retain a
permanent copy of published media.

## Troubleshooting

### Test connection says access is denied

Confirm that the Access Key ID and Secret Access Key belong to the same R2 token, the token has
Object Read & Write access, and its bucket restriction includes the exact bucket. If the secret
was lost, create new credentials; Cloudflare does not reveal it again.

### Test connection says the bucket does not exist

Check the Account ID and bucket spelling. Credentials from one Cloudflare account cannot access a
bucket in another account, even if the bucket names are the same.

### Test connection works but Meta cannot fetch media

For the presigned strategy, verify that the Mac's clock is correct because signed URLs are
time-sensitive. For the public strategy, paste the base URL into a browser and confirm it is the
bucket's actual public domain, not its S3 API endpoint. Also check for Cloudflare Access, firewall,
hotlink protection, or other rules that block Meta's servers.

### A public URL returns access denied

Enable public access for the R2.dev domain or custom domain. If you do not want a public bucket,
switch Blather back to **Presigned URLs, bucket stays private** instead.

### Media works for one network but not the other

The networks impose different media format, size, duration, and aspect-ratio rules. Try a standard
JPEG first. If that works, R2 is configured and the original media likely violates a provider
rule.

### Objects remain in the bucket

Blather normally deletes staged objects immediately. If the app crashes or loses network access,
it retries cleanup for objects older than 24 hours the next time it starts. Objects created outside
Blather's `blather-staging/` prefix are not managed by Blather.

## Official references

- [Cloudflare R2 get started](https://developers.cloudflare.com/r2/get-started/)
- [R2 API tokens](https://developers.cloudflare.com/r2/api/tokens/)
- [R2 presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/)
- [R2 public buckets](https://developers.cloudflare.com/r2/buckets/public-buckets/)

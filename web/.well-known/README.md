# App Links verification

`assetlinks.json` must be served from
`https://opensplit.alturing.dev/.well-known/assetlinks.json` as
`application/json`, over HTTPS, with no redirect. Android fetches it to decide
whether this app may open `https://opensplit.alturing.dev/...` links itself
instead of bouncing to a browser.

## The fingerprint list is not optional reading

`sha256_cert_fingerprints` currently holds **only the local debug key**. That is
enough to test App Links on a development machine and is guaranteed to fail in
production.

Before release the list must contain **both**:

1. **The upload key** — the key used to sign the bundle you upload.
2. **The Google Play App Signing key** — the key Play re-signs with before
   distributing. Find it under *Play Console → Release → Setup → App signing*.

Ship only the upload key and verification passes every test you run locally and
fails for every real user, because the app they install is signed with a
certificate the file has never heard of. This is the single most common way App
Links break, and the failure is silent: links simply open in the browser.

```bash
# Upload key
keytool -list -v -keystore upload-keystore.jks -alias upload | grep SHA256

# Then verify on a device against the real, deployed file:
adb shell pm verify-app-links --re-verify com.eigeninteractive.opensplit
adb shell pm get-app-links com.eigeninteractive.opensplit
```

The second command must report `verified` for the domain. Anything else — and
it fails quietly, with no error anywhere in the app — means links will not open
natively.

## Hosting

The host must also serve an SPA fallback: every unmatched path returns
`index.html`, so `/g/<id>` and `/join/<token>` work on a cold load rather than
404ing. `web/_redirects` does this on Cloudflare Pages and Netlify. `.well-known`
must be excluded from that fallback, or Android fetches the HTML shell instead
of the JSON and verification fails.

# App Links verification

`assetlinks.json` must be served as `application/json`, over HTTPS, with no
redirect, from every host the app claims. There is exactly one:

- `https://opensplit.web.app/.well-known/assetlinks.json`

Android fetches it once per host in the App Links intent filter and decides per
host, which is the reason to claim as few as possible: a host listed there is a
promise to serve this file, from that host, matching the signing key, for as
long as any link naming it is still in someone's chat history.

A vanity domain pointed here later should redirect to `opensplit.web.app`
rather than be added as a second host. A redirect needs no `assetlinks.json` of
its own and cannot drift out of step with this one.

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
404ing. `firebase.json` does this on Firebase Hosting; `web/_redirects` does the
same on Cloudflare Pages and Netlify.

`.well-known` must be excluded from that fallback, or Android fetches the HTML
shell instead of the JSON and verification fails.

**Firebase Hosting's default `ignore` list is `["firebase.json", "**/.*",
"**/node_modules/**"]`, and `**/.*` matches `.well-known`.** Accept that default
and the directory is never uploaded at all: the URL 404s, or worse falls through
the SPA rewrite and returns HTML, and App Links quietly stop working with
nothing to explain it. `firebase.json` here deliberately does not use it. On Firebase Hosting a real
file wins over a rewrite, so the copy in `build/web/.well-known/` is served as
itself — but only because `flutter build web` copies the directory verbatim.
Check it is there before believing a deploy.

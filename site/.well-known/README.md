# App Links verification

`assetlinks.json` must be served as `application/json`, over HTTPS, with no
redirect, from every host the app claims. There is exactly one:

- `https://opensplit.eigeninteractive.com/.well-known/assetlinks.json`

Android fetches it once per host in the App Links intent filter and decides per
host, which is the reason to claim as few as possible: a host listed there is a
promise to serve this file, from that host, matching the signing key, for as
long as any link naming it is still in someone's chat history.

A vanity domain pointed here later should redirect to
`opensplit.eigeninteractive.com` rather than be added as a second host. A
redirect needs no `assetlinks.json` of its own and cannot drift out of step with
this one. `test/deep_link_host_test.dart` is what keeps the manifest and
`linkHost` from drifting apart.

## The fingerprint list is not optional reading

`sha256_cert_fingerprints` holds all **three Google Play App Signing
certificates** used by Play's quantum-ready signing:

- the original classical certificate used on Android 16 and below;
- the new classical certificate used by the hybrid signature on Android 17+;
- the post-quantum certificate used by that same Android 17+ signature.

Play chooses the appropriate signature for the device, so omitting any one of
the three makes App Links depend on the Android version that installed the app.
These, rather than the upload certificate, are what Store installs trust.

It should also hold **the upload key**, the key `android/key.properties` points
at. Play never distributes anything signed with it, but every release APK built
on this machine and installed directly is — for testing, for a bug report, for
anyone sideloading. Without its fingerprint here, App Links verify from the
Store and fail on exactly those builds, which is a confusing way to spend an
afternoon.

```bash
# Upload key, if it is not already in the list:
keytool -list -v -keystore ~/opensplit-upload.jks -alias upload | grep SHA256
```

All four certificates are shown under *Play Console → Test and release → Setup
→ App signing*. Copy every SHA-256 fingerprint from the three App signing key
sections, then add the upload certificate manually if Play's generated Digital
Asset Links snippet omits it.

Get this wrong and verification can pass on one Android generation and fail on
another, because those devices receive different signatures. The failure is
silent: links simply open in the browser.

```bash
# Verify on a device against the real, deployed file:
adb shell pm verify-app-links --re-verify com.eigeninteractive.opensplit
adb shell pm get-app-links com.eigeninteractive.opensplit
```

The second command must report `verified` for the domain. Anything else — and
it fails quietly, with no error anywhere in the app — means links will not open
natively.

## Hosting

The host must serve a fallback under `/app`: an unmatched path there returns the
client's own document, so `/app/g/<id>` and `/app/join/<token>` work on a cold
load rather than 404ing. `server/src/app.ts` does this, by hand, for paths
beginning `/app` and no others.

By hand, because none of the platform's three `not_found_handling` settings
answers the right document. `single-page-application` would hand `/app/join/xyz`
the *landing page*, and `404-page` would hand it `/404.html`. That is also what
keeps this file clear of the fallback: it lives at the host root, alongside the
landing page and the policy pages, and nothing there is reachable by a rule
scoped to `/app`.

Three things have to be true of this file and none of them is checked anywhere
that fails loudly:

- **It has to be uploaded.** `wrangler deploy` uploads the whole assets
  directory including dotfiles, and `tool/build_web.dart` copies `site/` — also
  including dotfiles — over the built client. That was not free on the previous
  host: Firebase Hosting's default `ignore` list contains `**/.*`, which matches
  `.well-known`, so accepting the default silently never uploaded the directory
  at all.
- **It has to be `application/json`.** Wrangler infers the type from the
  extension, so `.json` is enough and there is no rule for it in `_headers`.
- **It must not redirect.** Nothing in `_redirects` touches `.well-known`, and
  the trailing-slash handling only applies to HTML.

Check it is there before believing a deploy:

```bash
curl -sI https://opensplit.eigeninteractive.com/.well-known/assetlinks.json
```

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
`test/deep_link_host_test.dart` is what keeps the manifest and `linkHost` from
drifting apart.

## The fingerprint list is not optional reading

`sha256_cert_fingerprints` currently holds **the Google Play App Signing key**,
which is the certificate every install from the Play Store actually carries —
Play re-signs each upload with it, so it, and not the upload key, is what
Android checks. It is the one that has to be there.

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

Both are shown together under *Play Console → Test and release → Setup → App
signing*, and Play offers a ready-made JSON snippet there containing the app
signing key alone. Adding a second fingerprint to the array is the manual part.

Get this wrong and verification passes every test run locally and fails for
every real user, because the app they install is signed with a certificate the
file has never heard of. It is the single most common way App Links break, and
the failure is silent: links simply open in the browser.

```bash
# Verify on a device against the real, deployed file:
adb shell pm verify-app-links --re-verify com.eigeninteractive.opensplit
adb shell pm get-app-links com.eigeninteractive.opensplit
```

The second command must report `verified` for the domain. Anything else — and
it fails quietly, with no error anywhere in the app — means links will not open
natively.

## Hosting

The host must serve an SPA fallback under `/app`: an unmatched path there
returns the app shell, so `/app/g/<id>` and `/app/join/<token>` work on a cold
load rather than 404ing. `firebase.json` does this.

This file lives at the host root, outside `/app`, which is also where the
landing page and the policy pages are. That is what keeps it clear of the
fallback: the rewrite is scoped to `/app/**` and cannot reach it. It used to be
a catch-all, and then `.well-known` had to be excluded by hand.

**Firebase Hosting's default `ignore` list is `["firebase.json", "**/.*",
"**/node_modules/**"]`, and `**/.*` matches `.well-known`.** Accept that default
and the directory is never uploaded at all: the URL 404s and App Links quietly
stop working with nothing to explain it. `firebase.json` here deliberately does
not use it. The copy in `build/web/.well-known/` is put there by
`tool/build_web.dart`, which copies `site/` — dotfiles included — over the
built app. Check it is there before believing a deploy:

```bash
curl -sI https://opensplit.web.app/.well-known/assetlinks.json
```

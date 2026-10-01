# The old addresses

`opensplit.web.app` and `opensplit-app.web.app`, and the `.firebaseapp.com`
twin of each, are Firebase Hosting sites in the `opensplit-app` project from
before the move to Cloudflare. They stay, as permanent (301) redirects to
`https://opensplit.eigeninteractive.com`, keeping the path and the query
string: an old link to `/app/join/…` lands on the same page at the new
address.

Every request is redirected, so `public/` is empty on purpose. Firebase
requires the directory; redirects are applied before any file would be
looked up. The root has its own rule because the catch-all regex does not
match an empty path.

Deployed by hand, once; nothing in CI touches it. Redeploy only if this file's
neighbours change:

```sh
cd legacy-domains
pnpm dlx firebase-tools@15.26.0 deploy --only hosting
```

Before a deploy, the Hosting emulator shows exactly what each site will do:

```sh
pnpm dlx firebase-tools@15.26.0 emulators:exec --only hosting \
  'curl -sI "http://127.0.0.1:5000/app/join/abc?x=1"'
```

Android App Links: builds that claimed `opensplit.web.app` can no longer
verify it, because Android does not follow redirects for
`/.well-known/assetlinks.json`. Their links open in the browser instead and
arrive here by the redirect. Current builds claim this domain.

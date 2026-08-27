# CI, Firebase Hosting, and Google Play

## What runs

There are two workflows, with no custom CI scripts or formatter dependencies:

| Event | CI | Release |
| --- | --- | --- |
| Direct push or PR merge to `main` | Run all checks | Run the same checks again, then build and deploy |
| PR opened, updated, or reopened targeting `main` | Run all checks | Does not run |
| Manual CI run | Run all checks | Does not run |
| Manual Release run on `main` | Called again by Release | Build; deploy only if the checkbox is enabled |

`ci.yml` defines **Analyse and test**, **Database tests**, **Release tooling and
Edge Functions**, and **Build**. `release.yml` calls `ci.yml` through GitHub's
`workflow_call`, then waits for all four jobs to pass before publishing. Main
pushes deliberately run checks twice, as requested; there is only one definition
of those checks to maintain. PR jobs have no signing secrets or cloud credentials.

The release job builds with real public configuration, signs an AAB, archives
both builds and debug information, then deploys **live Firebase Hosting** and
distributes to **Google Play internal testing**. It never promotes to Play
production. Promote the tested version in Play Console when ready.

The GitHub `production` environment controls credential access. Runs are
serialized and active uploads are not cancelled. Superseded main commits are
rejected immediately before deployment. GitHub may coalesce queued release jobs;
CI checks still run for every push, but not every intermediate commit is deployed.

Web and Play are independent services, not an atomic transaction. If Play fails
after Hosting succeeds, the web deployment remains live. Fix the failure and
rerun the release job; do not automatically roll back a good web release.

**No backend deployment is included.** Provision Supabase, apply its schema,
configure Auth/SMTP, and deploy Edge Functions separately before enabling client
auto-deployment. Never edit an already-deployed migration in place.

## Code generation and drift

Yes, generation belongs in CI. Fresh jobs that analyze, test, or build Dart run
`flutter pub get --enforce-lockfile` and `dart run build_runner build`. The quality
job also generates localizations, regenerates committed Drift snapshots/helpers,
checks Dart formatting, runs automatic fixes, and requires a clean Git worktree.
`flutter analyze --fatal-infos --no-pub`, native tests, Chrome domain tests,
PostgreSQL tests, and mandatory live-adapter tests follow. The live-adapter job
fails if its local Supabase instance is unavailable.

Generated `*.g.dart`, `*.freezed.dart`, and localization Dart files are intentionally
ignored. They are rebuilt from locked inputs, not compared to nonexistent
committed copies. The drift gate covers **tracked contracts, lockfiles, source
changes, and unexpected untracked files**. Generation failure, formatting,
analysis, and tests cover regenerated Dart. A second checksum manifest or checking
in generated files is unnecessary for this source-generation policy.

App formatting uses `dart format`; Edge Functions use `deno fmt`. There is no
additional formatter for CI YAML, Markdown, or JavaScript, and no root npm
project. Node runs the existing dependency-free service-worker tests. The release
runner installs a specific Firebase CLI version globally; Flutter development
does not require npm dependencies.
[Firebase documents npm installation and recommends Application Default
Credentials for CI](https://firebase.google.com/docs/cli#cli-ci-systems).

`Gemfile.lock` pins Fastlane dependencies with frozen Bundler. Edge Functions use
their own frozen Deno lockfile. Actions use major-version tags (`@v6`, `@v2`, etc.)
and Dependabot proposes major upgrades. The Firebase CLI version is pinned in the workflow, but its
transitive npm dependencies are not locked; review CLI upgrades there explicitly.
Dart fixes run only in CI's throwaway checkout; CI fails instead of committing
or silently accepting source edits.

## 1. Prepare your accounts and GitHub environment

The commands below target the existing repository `eigeninteractive/opensplit`,
Firebase project `opensplit-app`, Hosting site `opensplit`, and Android package
`com.eigeninteractive.opensplit`. The project/site match the local `.firebaserc`;
no cloud settings have been changed by this implementation. If using a fork,
replace these values throughout.

Have GitHub repository admin access, Google Cloud permission to create service
accounts/manage IAM and Workload Identity Federation, and Play Console permission
to manage the app and its users. Install GitHub CLI (`gh`), Google Cloud CLI
(`gcloud`), and `jq` on your workstation, then authenticate interactively:

```sh
cd /Users/seenuk/projects/opensplit
gh auth login
gcloud auth login
gcloud projects describe opensplit-app --format='value(projectId,projectNumber)'
```

These logins are for one-time setup, not credentials copied into CI. No GitHub
personal access token needs to be stored in this repository's secrets.

Open [repository environments](https://github.com/eigeninteractive/opensplit/settings/environments)
→ **New environment** → name it exactly `production`. Under **Deployment branches
and tags**, choose **Selected branches and tags**, and add the branch `main` only.
Add yourself as a required reviewer during bootstrap if your GitHub plan supports
it; remove that requirement after the first successful release for automatic
main deploys. Under **Settings → Actions → General**, ensure Actions and the
third-party setup actions used by these workflows are allowed.

Protect main with the four CI job checks listed above and review of
workflow/release-code changes. Select the checks from the standalone CI run when
configuring your branch rules.
Do not expose deployment secrets to PR jobs or use `pull_request_target` to run
contributor code.

### Environment variables (not secrets)

| Name                              | Value                                                                            |
| --------------------------------- | -------------------------------------------------------------------------------- |
| `FIREBASE_PROJECT_ID`             | `opensplit-app` for the existing local project                                   |
| `FIREBASE_HOSTING_SITE`           | `opensplit` for the existing local site                                          |
| `GCP_WORKLOAD_IDENTITY_PROVIDER`  | Full provider resource name from step 2                                          |
| `FIREBASE_DEPLOY_SERVICE_ACCOUNT` | Hosting deployer's service-account email                                         |
| `PLAY_DEPLOY_SERVICE_ACCOUNT`     | Play deployer's service-account email                                            |
| `PLAY_RELEASE_STATUS`             | Optional: `completed` (default) or `draft`; draft does not distribute to testers |

Copy each public field from your gitignored `env/app.json` into a same-named
environment variable:

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
LINK_HOST
GOOGLE_WEB_CLIENT_ID
FCM_PROJECT_ID
FCM_SENDER_ID
FCM_VAPID_KEY
ANDROID_FCM_API_KEY
ANDROID_FCM_APP_ID
WEB_FCM_API_KEY
WEB_FCM_APP_ID
```

These are client identifiers, not administrator credentials. Keep API-key
restrictions and OAuth redirect URLs correct. Never use a Supabase secret or
service-role key, Google OAuth client secret, or service-account private key here.
The workflow selects only these public fields using `jq`. The existing Dart web
build validates app configuration before packaging. Before deployment, Firebase's
`target:apply` command maps the explicit project/site; CI does not inherit your
workstation's `.firebaserc`.

Validate your existing `env/app.json`, then copy only its public fields to GitHub
environment **variables**, not secrets:

```sh
dart run tool/verify_config.dart
# Continue only if the configuration check passes.
for CI_KEY in SUPABASE_URL SUPABASE_PUBLISHABLE_KEY LINK_HOST \
  GOOGLE_WEB_CLIENT_ID FCM_PROJECT_ID FCM_SENDER_ID FCM_VAPID_KEY \
  ANDROID_FCM_API_KEY ANDROID_FCM_APP_ID WEB_FCM_API_KEY WEB_FCM_APP_ID; do
  CI_VALUE=$(jq -er --arg key "$CI_KEY" \
    '.[$key] | select(type == "string" and length > 0)' env/app.json) || break
  gh variable set "$CI_KEY" --body "$CI_VALUE" \
    --repo eigeninteractive/opensplit --env production || break
done
```

## 2. Keyless Google credentials

Use GitHub OIDC → Google Workload Identity Federation → two separate service
accounts. Firebase CLI and the pinned Fastlane support the resulting credentials
file. No `FIREBASE_TOKEN` or service-account JSON private key is needed.
[Firebase CLI authentication](https://firebase.google.com/docs/cli#cli-ci-systems),
[Google authentication action](https://github.com/google-github-actions/auth),
[Fastlane authentication](https://docs.fastlane.tools/actions/upload_to_play_store/).

Run the following once as a Google Cloud administrator after confirming the
project. These are setup instructions; CI does not grant itself permissions.
Use the same terminal for this block and the variable-upload block below. If a
named service account or identity pool already exists, inspect and reuse it;
do not delete it to rerun these creation commands.

```sh
DEPLOY_PROJECT=opensplit-app
DEPLOY_REPO=eigeninteractive/opensplit
DEPLOY_NUMBER=$(gcloud projects describe "$DEPLOY_PROJECT" --format='value(projectNumber)')
DEPLOY_REPO_ID=$(gh api "repos/$DEPLOY_REPO" --jq .id)
DEPLOY_OWNER_ID=$(gh api "repos/$DEPLOY_REPO" --jq .owner.id)

gcloud services enable iam.googleapis.com cloudresourcemanager.googleapis.com \
  iamcredentials.googleapis.com sts.googleapis.com \
  firebasehosting.googleapis.com firebase.googleapis.com \
  apikeys.googleapis.com androidpublisher.googleapis.com \
  --project="$DEPLOY_PROJECT"

gcloud iam service-accounts create opensplit-hosting-ci --project="$DEPLOY_PROJECT"
gcloud iam service-accounts create opensplit-play-ci --project="$DEPLOY_PROJECT"

gcloud projects add-iam-policy-binding "$DEPLOY_PROJECT" \
  --member="serviceAccount:opensplit-hosting-ci@$DEPLOY_PROJECT.iam.gserviceaccount.com" \
  --role=roles/firebasehosting.admin
gcloud projects add-iam-policy-binding "$DEPLOY_PROJECT" \
  --member="serviceAccount:opensplit-hosting-ci@$DEPLOY_PROJECT.iam.gserviceaccount.com" \
  --role=roles/serviceusage.apiKeysViewer

gcloud iam workload-identity-pools create opensplit-github \
  --project="$DEPLOY_PROJECT" --location=global \
  --display-name='OpenSplit GitHub releases'

gcloud iam workload-identity-pools providers create-oidc main \
  --project="$DEPLOY_PROJECT" --location=global \
  --workload-identity-pool=opensplit-github \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping='google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.repository_owner_id=assertion.repository_owner_id,attribute.ref=assertion.ref,attribute.workflow_ref=assertion.workflow_ref' \
  --attribute-condition="assertion.repository_id == '$DEPLOY_REPO_ID' && assertion.repository_owner_id == '$DEPLOY_OWNER_ID' && assertion.ref == 'refs/heads/main' && assertion.workflow_ref == '$DEPLOY_REPO/.github/workflows/release.yml@refs/heads/main' && assertion.sub == 'repo:$DEPLOY_REPO:environment:production'"

for DEPLOY_ACCOUNT in opensplit-hosting-ci opensplit-play-ci; do
  gcloud iam service-accounts add-iam-policy-binding \
    "$DEPLOY_ACCOUNT@$DEPLOY_PROJECT.iam.gserviceaccount.com" \
    --project="$DEPLOY_PROJECT" --role=roles/iam.workloadIdentityUser \
    --member="principalSet://iam.googleapis.com/projects/$DEPLOY_NUMBER/locations/global/workloadIdentityPools/opensplit-github/attribute.repository_id/$DEPLOY_REPO_ID"
done

gcloud iam workload-identity-pools providers describe main \
  --project="$DEPLOY_PROJECT" --location=global \
  --workload-identity-pool=opensplit-github --format='value(name)'
```

Numeric repository and owner checks prevent reclaimed names from inheriting this
trust. The branch, environment, and `workflow_ref` restrict it to the standalone
Release workflow on main. `job_workflow_ref` is not used: only the checks are a
reusable workflow now. Allow a few minutes for IAM propagation. Do not grant the
CI service accounts project Owner/Editor or Play account-wide Admin.
[GitHub OIDC claims](https://docs.github.com/en/actions/reference/security/oidc),
[Google federation setup](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines).

Save the remaining GitHub environment variables:

```sh
DEPLOY_PROVIDER=$(gcloud iam workload-identity-pools providers describe main \
  --project="$DEPLOY_PROJECT" --location=global \
  --workload-identity-pool=opensplit-github --format='value(name)')

gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$DEPLOY_PROVIDER" \
  --repo "$DEPLOY_REPO" --env production
gh variable set FIREBASE_PROJECT_ID --body "$DEPLOY_PROJECT" \
  --repo "$DEPLOY_REPO" --env production
gh variable set FIREBASE_HOSTING_SITE --body opensplit \
  --repo "$DEPLOY_REPO" --env production
gh variable set FIREBASE_DEPLOY_SERVICE_ACCOUNT \
  --body "opensplit-hosting-ci@$DEPLOY_PROJECT.iam.gserviceaccount.com" \
  --repo "$DEPLOY_REPO" --env production
gh variable set PLAY_DEPLOY_SERVICE_ACCOUNT \
  --body "opensplit-play-ci@$DEPLOY_PROJECT.iam.gserviceaccount.com" \
  --repo "$DEPLOY_REPO" --env production
gh variable set PLAY_RELEASE_STATUS --body completed \
  --repo "$DEPLOY_REPO" --env production
```

Hosting needs Hosting Admin and API Keys Viewer for CLI deployment.
[Firebase role requirements](https://firebase.google.com/docs/projects/iam/roles-predefined-product#hosting).
The Play service account needs Play Console permissions, not project-wide Cloud
roles; see below.

In [Firebase Console](https://console.firebase.google.com/project/opensplit-app/hosting),
verify Hosting is initialized and the `opensplit` site exists. Create it there
only if it is missing. The workflow deploys this site, not every Hosting site in
the project. Its default URL is `https://opensplit.web.app`; configure your
intended custom domain there separately. No Firebase CI token or downloaded
service-account private key is needed.

## 3. Play Console and signing

1. Create the Play Console app for `com.eigeninteractive.opensplit`. Complete
   required listing, privacy/data-safety, content-rating, app-access, and
   country/tester setup. Add internal testers and give them the opt-in link.
2. Enable **Play App Signing**, preferably with Google generating/managing the
   app-signing key. Keep your existing Downloads keystore as the **upload key**.
   Google signs installed APKs; CI signs the AAB with your upload key.
   [Android signing model](https://developer.android.com/studio/publish/app-signing).
3. In Play Console → Users and permissions, invite
   `opensplit-play-ci@opensplit-app.iam.gserviceaccount.com`. Limit app access to
   OpenSplit. Grant **View app information (read-only)** and **Release apps to
   testing tracks**. Do not grant production release permission to this pipeline.
   Under **App permissions**, add OpenSplit and grant those permissions for this
   app only. Do not grant financial, order/subscription, or account-wide admin
   permissions. No developer-account-to-Cloud-project linking step is needed.
   [Play API setup](https://developers.google.com/android-publisher/getting_started).
4. The first bundle must be uploaded manually in Play Console before Fastlane
   can update the app. Run **Actions → Release → Run workflow**, select `main`, and
   leave **deploy unchecked**. This runs all gates and creates the signed AAB
   without deploying. Download `app-release.aab` from the artifact, upload it to
   **Testing → Internal testing → Create new release**, finish setup, and roll
   it out. Approve the artifact-only job if you enabled environment reviewers.
   [Fastlane first-upload requirement](https://docs.fastlane.tools/actions/upload_to_play_store/#quick-start).
5. After bootstrap, leave `PLAY_RELEASE_STATUS=completed` (or unset) so main
   pushes distribute to testers. `draft` requires manual completion in Console.
   Play's review/testing requirements still apply; an upload is not a guarantee
   of immediate availability.

### GitHub environment secrets

Add these four secrets to `production`:

Use **Settings → Environments → production → Environment secrets → Add
environment secret**, or the commands below. Do not put them in ordinary
repository variables.

| Secret                           | Contents                                                    |
| -------------------------------- | ----------------------------------------------------------- |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Base64 contents of the existing upload keystore             |
| `ANDROID_UPLOAD_STORE_PASSWORD`  | Keystore password                                           |
| `ANDROID_UPLOAD_KEY_ALIAS`       | Existing key alias, not the filename                        |
| `ANDROID_UPLOAD_KEY_PASSWORD`    | Private-key password (often the same as the store password) |

Upload the key without printing it in a terminal or pasting it into chat:

```sh
base64 -i /Users/seenuk/Downloads/upload-keystore.jks | \
  gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64 \
    --repo eigeninteractive/opensplit --env production

# Each command prompts privately for the value.
gh secret set ANDROID_UPLOAD_STORE_PASSWORD --repo eigeninteractive/opensplit --env production
gh secret set ANDROID_UPLOAD_KEY_ALIAS --repo eigeninteractive/opensplit --env production
gh secret set ANDROID_UPLOAD_KEY_PASSWORD --repo eigeninteractive/opensplit --env production
```

If you need to confirm the alias, run the following locally; it prompts for the
keystore password and lists certificate metadata, not the private key:

```sh
keytool -list -keystore /Users/seenuk/Downloads/upload-keystore.jks
```

Do not commit the key or `android/key.properties`. CI decodes the key into a
restricted temporary file, passes passwords directly to Gradle via environment
variables (no Java-properties escaping pitfalls), and deletes the temporary key
even if a later step fails. Keep an encrypted backup independently of GitHub.

The **Play app-signing** certificate's SHA-256 must be in
`site/.well-known/assetlinks.json`; add its SHA-1/SHA-256 to the relevant Firebase
Android app, OAuth Android client, and API-key restrictions. The upload key's
fingerprints alone are insufficient for Play-installed builds. Keep the upload
certificate too if you test locally signed APKs. See
[App Links setup](../site/.well-known/README.md).

Find these fingerprints in Play Console → **Test and release → Setup → App
signing** (also reachable through **App integrity**). Use the **app-signing key
certificate**, not just the upload certificate. In Firebase Console → **Project
settings → General → Your apps → Android**, add its SHA-1 and SHA-256. In Google
Cloud → **Google Auth Platform → Clients**, create/check the Android OAuth client
for this package and the Play app-signing SHA-1. Keep the web OAuth client ID as
`GOOGLE_WEB_CLIENT_ID`. Restrict the Android API key to the package/certificate and
the browser API key to the deployed web origins. These are app-login settings,
separate from the two CI deployer service accounts.

## 4. First run and enable automatic releases

1. Complete the GitHub variables/secrets and Play Console setup above before
   enabling uploads. If the initial main push already started Release, cancel
   that run while bootstrapping; do not approve an automatic upload yet.
2. Run **Release** on `main` with **deploy unchecked**. It reruns CI and produces
   the signed AAB without contacting either deployment service. Upload that
   artifact manually to Play as described above.
3. Run **Release** again on `main` with **deploy checked**. This creates a new
   version code, deploys Hosting, and uploads to Play internal testing. No code
   change is needed between the two runs.
4. Open the Hosting URL, install through the internal-testing opt-in link, and
   verify login, App Links, and push on the Play-signed build. Remove the temporary
   environment reviewer requirement when ready. Subsequent main pushes and PR
   merges then run CI and Release automatically.

You can start those two manual runs from the CLI instead of the UI:

```sh
gh workflow run release.yml --repo eigeninteractive/opensplit --ref main -f deploy=false
# After the first manual Play upload:
gh workflow run release.yml --repo eigeninteractive/opensplit --ref main -f deploy=true
```

Check configuration **names** without printing secret values:

```sh
gh variable list --repo eigeninteractive/opensplit --env production --json name
gh secret list --repo eigeninteractive/opensplit --env production
```

If authentication fails, check the provider's project **number**, its
`workflow_ref` condition, both service-account impersonation bindings, and the
exact environment name `production`. Play 403s usually require checking the Play
service account's app-level permissions, not adding Cloud IAM roles. A duplicate
version code requires a fresh run/rerun, not another upload of the same AAB.

### Version codes and retries

CI uses `GITHUB_RUN_NUMBER * 100 + GITHUB_RUN_ATTEMPT` as the Android version code.
Attempts 1–99 are supported; out-of-range codes fail before the Android build.
`pubspec.yaml` still controls the user-visible version name. This avoids reusing
a version code on reruns and is monotonic across runs of **the Release workflow**.

Use the CI-built bundle for the first manual upload and subsequent releases;
don't independently upload arbitrary larger codes. If the workflow is replaced
and its run counter resets, adjust the formula above the highest uploaded code
before deploying again. Re-run **failed jobs** to retry a failed release. A stale
main SHA is intentionally rejected; start a fresh run on current main instead.

## Local checks

Use the Ruby version in `.ruby-version`. No `npm install` is needed for checks:

```sh
bundle install
node --test test/web_service_worker_test.mjs
bundle exec fastlane lanes

flutter pub get --enforce-lockfile
flutter gen-l10n
dart run build_runner build
dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/data/generated_migrations/
dart format test/data/generated_migrations
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-infos --no-pub
flutter test
deno check --config=supabase/functions/deno.json supabase/functions/fetch-fx/index.ts supabase/functions/notify-entry/index.ts
```

CI checks drift directly with `git diff --exit-code` and
`test -z "$(git status --porcelain --untracked-files=all)"`. These require an
already-clean checkout. Locally, review intentional edits first; never discard
work just to make them pass. CI starts from checkout, so subsequent source drift
is unexpected.

No live deploy/upload is part of local validation. Verify the first real run in
GitHub Actions, confirm the Hosting URL and internal-track install, then test
OAuth, App Links, and push on the Play-signed build.

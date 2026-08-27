# Self-hosting OpenSplit

OpenSplit supports the Supabase CLI stack as its reproducible self-hosted
backend. It is the same Docker-based stack used by development and CI, so the
schema, policies, functions, Auth behavior, and PostgREST adapter are exercised
on every change rather than documented as an untested alternative.

## Start the backend

Install Docker and Supabase CLI 2.115.0, then run from the repository root:

```bash
supabase start
supabase db reset
supabase test db
flutter test test/data/supabase_integration_test.dart
```

The first command prints the local API URL and publishable key. Put those in a
gitignored `env/local.json`, using `env/local.example.json` as the template.
The migrations are the deployment unit; never maintain a second hand-edited
schema for self-hosting.

## Edge Functions

Serve the functions with the same secrets they use when hosted:

```bash
supabase functions serve --env-file supabase/functions/.env
./supabase/dev/local-notify.sh
```

The notification fan-out needs an FCM project because Firebase has no local
emulator for Cloud Messaging. Everything else works without it; the function
reports `unconfigured` instead of failing the write path.

## Internet-facing operation

The CLI stack is the supported reproducible development and validation setup.
For a public multi-user installation, start from Supabase's maintained
self-hosting deployment rather than copying the CLI containers into
production. Apply this repository's migrations in order, deploy both Edge
Functions, configure their secrets, and run the two test commands above before
pointing a client build at the instance.

Pin the Supabase release and upgrade it deliberately. Do not use `latest` for
the database images or CLI: an unreviewed backend upgrade must not share a
release with an application change.

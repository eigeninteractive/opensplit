# Audit: open items

The Cloudflare + Dart audit is done. What it settled is written down where it
applies: the type chain, the rule for required and nullable fields, and dates
in [architecture.md](architecture.md); the local schema rules in
[local-database.md](local-database.md). This file keeps only what is still
open.

## Before the first public release

- **Real local migrations.** An upgrade rebuilds the local database
  (`destructiveFallback`) and re-syncs, which loses anything recorded offline
  and never pushed. Fine for testers; it has to become ordinary migrations
  before anybody else installs the app.

## Small, whenever convenient

- **Integration tests and port 8787.** The live-Worker suite skips only when
  nothing answers, so another project on 8787 fails it instead. Probing
  `/api/health` and skipping unless it is OpenSplit would fix that.
- **The contract does not declare how requests authenticate.** No
  `securitySchemes`, so a reader of `docs/openapi.json` cannot tell a bearer
  token or a session cookie is needed. Declaring it would also change the
  generated client, so check what it emits.
- **`DateTime` query parameters** go through a hand-written Dio interceptor
  (`_IsoDatesInQueryStrings` in `lib/data/sync/api_client.dart`), because the
  generated client formats them with `DateTime.toString()`, which is not ISO
  8601.

## Later

- **Localised errors.** Screens show the server's English message. Mapping
  `ErrorCode` to local strings matters once the rest of the app is translated.

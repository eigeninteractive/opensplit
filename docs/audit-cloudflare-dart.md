# Audit: open items

What the audits settled is written down where it applies: the type chain,
required and nullable fields, and dates in [architecture.md](architecture.md);
the local schema rules in [local-database.md](local-database.md). The latest
audit and what it changed is [audit-2026-09-26.md](audit-2026-09-26.md). This
file keeps only what is still open.

## Before the first public release

- **Real local migrations.** An upgrade rebuilds the local database
  (`destructiveFallback`) and re-syncs, which loses anything recorded offline
  and never pushed. Fine for testers; it has to become ordinary migrations
  before anybody else installs the app.

## Later

- **Localised errors.** Screens show the server's English message. Mapping
  `ErrorCode` to local strings matters once the rest of the app is translated.

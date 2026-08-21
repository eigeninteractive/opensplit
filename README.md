# OpenSplit

Split expenses with friends. Free forever, no ads, works offline, open source.

OpenSplit is a local-first expense splitter for Android and the web. It exists
because every alternative either paywalls the act of logging an expense or has
no real mobile app.

**Status: in development.** Not yet released.

## What makes it different

- **Logging an expense is never gated.** No caps, no limits, no upsell. See
  [PRINCIPLES.md](PRINCIPLES.md).
- **Every read is instant.** The full journal lives on your device; balances,
  search and analytics are local SQL. No screen waits on a network.
- **Genuinely offline.** Full create/read/update/delete with no connection,
  indefinitely. Trips abroad are the main use case, not an edge case.
- **Multi-currency is core.** Balances are always per currency, never silently
  netted across one.
- **Self-hostable for real.** The server stores rows and enforces one
  invariant. It computes nothing.

## Architecture in one paragraph

A Flutter client (Riverpod, Drift, go_router) holds the entire journal in
SQLite and does all computation locally — split arithmetic, the balance fold,
debt simplification, analytics. Supabase is a paginated row feed behind a Dart
repository interface: Postgres with row-level security and a deferred
constraint trigger that enforces `sum(payers) = sum(shares) = amount` at commit.
Reads outnumber writes roughly 50:1, so putting reads on devices people already
own is what makes "free forever" credible rather than aspirational.

## Development

Requires the Flutter SDK, Docker, and the Supabase CLI.

```bash
flutter pub get
dart run build_runner build        # Drift, Freezed and Riverpod codegen
flutter test                       # domain property tests + storage tests
flutter run
```

The local backend:

```bash
supabase start                     # applies supabase/migrations in order
supabase db reset                  # rebuild from scratch
supabase test db                   # pgTAP: invariants, RLS, invite claims
```

The database tests are not optional decoration. They cover the deferred
constraint trigger rejecting unbalanced entries, that `is_group_member` does
not recurse through its own policy (Postgres 42P17, the standard failure for
this shape of schema), that entries cannot be hard-deleted, that an anonymous
account cannot destroy a group, and that an invite token can be spent exactly
once by someone with no other access to the group.

Code generation runs over Drift tables, Freezed models and Riverpod providers.
After changing any of them, re-run `dart run build_runner build`.

### Layout

```
lib/domain/         pure Dart: splitting, balance fold, simplify. No Flutter,
                    no imports from data/.
lib/data/           Drift database, repositories, sync. The only place the
                    backend is referenced.
lib/application/    Riverpod providers and view models.
lib/presentation/   screens and widgets.
supabase/           migrations, in order. 0001 is the locked initial schema.
docs/               the product requirements document.
```

The domain layer is pure functions over immutable data, which is why it is
tested with generated cases rather than examples: thousands of random entry
sets asserting that balances sum to exactly zero, that every entry balances,
that rounding is identical regardless of member order, and that applying the
suggested settlements leaves nothing owed.

## Licence

[AGPL-3.0](LICENSE). If you run a modified OpenSplit as a service, your users
are entitled to your changes.

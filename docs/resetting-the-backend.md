# Resetting development storage

Use resets only for development data whose loss is acceptable, after backing up
anything that must survive. Normal releases use incremental D1, Durable Object
and Drift migrations. Resetting storage is separate manual maintenance; temporary
deployment configurations, exports and restore scripts stay outside Git.

## Back up first

Export the required D1 account, profile and membership rows and the related
Durable Object ledger rows. Preserve identities, references, financial history,
recorded exchange rates and sequence counters together. The app's JSON export
does not include all server authentication and discovery data.

Rehearse the restore against fresh schemas and verify references, counts and
balances before deleting anything. Keep the private backup outside the checkout.
Pause application use while replacing storage so writes cannot land between
the backup and restoration.

## Durable Objects

Removing a binding or class export alone is not a complete namespace reset.
Cloudflare's declarative `exports` configuration manages namespace lifecycle.
In a temporary local deployment:

1. Remove the affected classes from the Worker's code exports.
2. Remove their `durable_objects.bindings` entries.
3. Replace their live `exports` entries with
   `{ "type": "durable-object", "state": "deleted" }`.
4. From `server/`, run `pnpm exec wrangler deploy --env=""` against the intended
   account. A temporary maintenance entrypoint can return 503 while storage is
   unavailable, without shipping product handlers that expect those bindings.

This permanently deletes each selected namespace and all of its objects. It has
no trash. Restore the normal code, bindings and live `exports` configuration
before the next product deployment; Cloudflare provisions fresh namespaces.
An object's logical name can remain the same, but its physical ID changes.
See [Cloudflare's class deletion procedure](https://developers.cloudflare.com/durable-objects/reference/durable-objects-migrations/#delete-a-durable-object-class).

The Worker, domain and secrets do not need to be deleted. Reset only the storage
that needs replacing; rebuilding group storage does not itself require resetting
the FX namespace or D1.

## D1 and restoration

D1 holds authentication, profiles and group discovery separately from each
group's financial database. A Durable Object reset leaves D1 untouched; clear or
rebuild stale discovery rows as part of the same maintenance operation.

If recreating D1 is necessary, record the new database ID in `wrangler.jsonc`
before releasing, and apply the committed D1 migrations to the fresh database.
Initialize fresh group objects using the product schema, then restore the
reviewed rows. Verify authentication, group discovery, full synchronization,
foreign keys and balances before resuming use.

Pushes to `main` deploy automatically after CI. Finish any required reset and
prepare restoration before merging; do not merge an initial-schema replacement
onto old databases. Restore all temporary local code/configuration edits before
committing the product changes.

## Device storage

Server storage and device databases are independent. A server reset does not
erase a device's cache or queued edits. Unsupported API paths must be refused
before reaching data handlers so stale clients cannot repopulate reset storage.

The app uses `opensplit-v1-<accountId>` at local schema version 1 and leaves its
earlier database files unused. Future local schema upgrades keep this filename
and migrate data and pending edits. Do not use a server reset as a substitute for
those migrations. See [the local database](local-database.md) and
[API retirement](api-upgrades.md).

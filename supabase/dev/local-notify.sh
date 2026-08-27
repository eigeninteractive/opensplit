#!/usr/bin/env bash
# Points a LOCAL Supabase stack's push fan-out at the local notify-entry.
#
# The trigger itself is in supabase/migrations/20260101000008_push.sql and is
# always there. What this writes is the two app_settings rows it reads — the
# function URL and the shared secret — which are deployment facts and so are
# data rather than schema.
#
# `supabase db reset` clears them, exactly as it clears the fx pair. The
# trigger survives; it simply no-ops until this is run again.
#
# Reads NOTIFY_WEBHOOK_SECRET from supabase/functions/.env so the secret is
# never typed on a command line or committed.
#
# Requires: supabase start, and supabase functions serve running in another
# terminal.
set -euo pipefail

cd "$(dirname "$0")/../.."

env_file="supabase/functions/.env"
[ -f "$env_file" ] || { echo "missing $env_file" >&2; exit 1; }

secret=$(grep '^NOTIFY_WEBHOOK_SECRET=' "$env_file" | cut -d= -f2-)
[ -n "$secret" ] || { echo "NOTIFY_WEBHOOK_SECRET is not set in $env_file" >&2; exit 1; }

container="supabase_db_$(basename "$PWD")"

# host.docker.internal, not 127.0.0.1: this runs inside the Postgres container,
# where localhost is the container itself and the functions are on the host.
docker exec -i "$container" psql -U postgres -v ON_ERROR_STOP=1 <<SQL
insert into app_settings (key, value) values
  ('notify_function_url',
   'http://host.docker.internal:54321/functions/v1/notify-entry'),
  ('notify_webhook_secret', '$secret')
on conflict (key) do update set value = excluded.value;
SQL

echo "notify-entry is configured for local pushes."

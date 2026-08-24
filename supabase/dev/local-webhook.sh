#!/usr/bin/env bash
# Wires the entries INSERT webhook into a LOCAL Supabase stack.
#
# In production this is a row created in the dashboard under Database →
# Webhooks. There is no dashboard locally, and `supabase db reset` drops it, so
# this recreates it — run it after every reset or push simply stops firing with
# nothing to say why.
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
drop trigger if exists on_entry_created on public.entries;
create trigger on_entry_created
  after insert on public.entries
  for each row execute function supabase_functions.http_request(
    'http://host.docker.internal:54321/functions/v1/notify-entry',
    'POST',
    '{"Content-Type":"application/json","x-webhook-secret":"$secret"}',
    '{}',
    '5000'
  );
SQL

echo "on_entry_created is wired to the local notify-entry function."

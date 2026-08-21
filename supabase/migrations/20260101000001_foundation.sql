-- ============================================================================
-- OpenSplit — foundations.
--
-- Extensions and the enumerated types every later file depends on.
--
-- The schema is organised by subject, not by the order things were thought of:
-- reference data, identity, groups, the ledger, rates, invites, push, the write
-- path, security, privileges, jobs. Each file is meant to be readable on its
-- own as the definition of that subject.
-- ============================================================================

-- gen_random_uuid()
create extension if not exists pgcrypto;

-- Outbound HTTP from Postgres, used by the scheduled rate fetch. Tolerated
-- rather than required: a self-hosted plain Postgres without it still applies
-- every migration and simply has no scheduled fetch.
do $$
begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net unavailable (%); scheduled jobs disabled', sqlerrm;
end;
$$;

do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron unavailable (%); scheduled jobs disabled', sqlerrm;
end;
$$;

-- ----------------------------------------------------------------------------
-- Types
-- ----------------------------------------------------------------------------

-- A settlement is an entry, not a separate table: one payer, one share, and it
-- folds through the identical balance path, cancelling exactly the debt the
-- expenses created.
create type entry_kind as enum ('expense', 'settlement');

create type split_kind as enum ('equal', 'exact', 'shares', 'percent');
-- 'equal'   -> weights all 1, amounts resolved by largest-remainder
-- 'exact'   -> user typed each amount; weight is null
-- 'shares'  -> weight = share count (2:1:1)
-- 'percent' -> weight = percentage (must sum to 100)

create type member_role as enum ('owner', 'member');

-- ============================================================================
-- v1 scope amendments to the locked initial schema.
--
-- These follow from PRD §8 (data model amendments) and §10 (sync trade-offs).
-- 0001 is kept verbatim as the locked artifact; every change since lives here.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- No receipt photos in v1.
--
-- Storage + egress dominate every other cost by orders of magnitude, and this
-- is the exact pressure that forced the incumbent's paywall. The column goes
-- rather than sitting unused and inviting a v1.1 "just one feature" argument.
-- ---------------------------------------------------------------------------
alter table entries drop column receipt_path;

-- ---------------------------------------------------------------------------
-- UPI settle-up handoff (India).
--
-- Payment identity is personal, not group-scoped, so it lives on profiles and
-- is exposed to co-members through the existing profiles_read policy. The
-- format check mirrors the VPA grammar: <handle>@<psp>.
-- ---------------------------------------------------------------------------
alter table profiles add column upi_vpa text;

alter table profiles add constraint upi_vpa_format
  check (upi_vpa is null or upi_vpa ~ '^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,64}$');

-- ---------------------------------------------------------------------------
-- Client version drift guard (PRD §10, §21).
--
-- An old client is old business logic. Two users on different app versions
-- could otherwise fold the same entries into different balances with nothing
-- recording why. Stamping the algorithm version onto the row means the rule
-- that produced an entry stays attached to it forever, so a future rounding
-- fix can be applied to new entries without retroactively moving settled
-- money. Existing rows are v1 by definition.
-- ---------------------------------------------------------------------------
alter table entries add column algo_version smallint not null default 1;

comment on column entries.algo_version is
  'Version of the client-side split/fold algorithm that produced this row. '
  'Never recompute historical entries under a newer version.';

-- ---------------------------------------------------------------------------
-- Cursor sync index (PRD §10).
--
-- The delta pull is:
--   select ... where group_id = ? and updated_at > cursor order by updated_at
--
-- Deliberately NOT partial on deleted_at is null: a soft delete is itself a
-- delta the client must receive, otherwise a deleted expense lives forever on
-- every device that already synced it.
-- ---------------------------------------------------------------------------
create index idx_entries_group_updated on entries (group_id, updated_at);

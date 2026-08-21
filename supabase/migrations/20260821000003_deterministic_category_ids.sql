-- ============================================================================
-- Give the global category presets fixed ids.
--
-- 0001 inserted them with gen_random_uuid(), which means every deployment —
-- and every developer's local stack — invents different ids for "Groceries".
-- That breaks the offline promise: a client has to be able to categorise an
-- expense before it has ever synced, and the category_id it writes must be one
-- the server will recognise when the entry finally arrives.
--
-- Fixing the ids makes the presets shippable inside the app bundle. They are
-- kept in step with lib/data/local/reference_data.dart.
--
-- Safe to run destructively here only because presets are reference data that
-- no entry can yet point at: group-scoped categories (group_id not null) are
-- left untouched.
-- ============================================================================

delete from categories where group_id is null;

insert into categories (id, group_id, name, icon) values
  ('00000000-0000-4000-8000-000000000001', null, 'Food & Drink',  'utensils'),
  ('00000000-0000-4000-8000-000000000002', null, 'Groceries',     'shopping-cart'),
  ('00000000-0000-4000-8000-000000000003', null, 'Transport',     'car'),
  ('00000000-0000-4000-8000-000000000004', null, 'Accommodation', 'bed'),
  ('00000000-0000-4000-8000-000000000005', null, 'Rent',          'home'),
  ('00000000-0000-4000-8000-000000000006', null, 'Utilities',     'zap'),
  ('00000000-0000-4000-8000-000000000007', null, 'Entertainment', 'film'),
  ('00000000-0000-4000-8000-000000000008', null, 'Shopping',      'shopping-bag'),
  ('00000000-0000-4000-8000-000000000009', null, 'Health',        'heart-pulse'),
  ('00000000-0000-4000-8000-00000000000a', null, 'Other',         'circle-dot');

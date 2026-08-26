import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../../domain/models/member.dart';
import '../../domain/split/splitter.dart';

/// ISO 4217 reference data, mirrored locally so that formatting works offline
/// on first run.
///
/// This is reference data rather than user data: it ships with the app and is
/// refreshed from the server, never edited on device.
@DataClassName('CurrencyRow')
class Currencies extends Table {
  TextColumn get code => text().withLength(min: 3, max: 3)();

  /// Decimal digits in the minor unit. Read it; never assume 2.
  IntColumn get exponent => integer()();
  TextColumn get symbol => text().nullable()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {code};
}

/// Cached display information for people who have accounts.
///
/// Placeholder members have no profile at all, so this table is a lookup for
/// avatars, display names and UPI handles — never the identity that financial
/// rows point at.
@DataClassName('ProfileRow')
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarUrl => text().nullable()();

  /// UPI virtual payment address, used to build a settle-up handoff. Personal,
  /// not group-scoped.
  TextColumn get upiVpa => text().nullable()();

  /// The server's timestamp, and what the profiles pull cursors on.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// What happened to an expense, mirrored from the server.
///
/// Read-only on this device: every row is written by a trigger on the server
/// and arrives by sync. Nothing here is ever generated locally, which is why
/// there is no outbox target for it and no client-side write path at all — an
/// audit trail a device can author is not an audit trail.
@DataClassName('EntryEventRow')
class EntryEvents extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text().references(Entries, #id)();
  TextColumn get groupId => text().references(Groups, #id)();

  /// The member who did it, not the account: authorship is group-scoped, so a
  /// placeholder's edits survive them claiming an account.
  TextColumn get actorId => text().references(Members, #id)();

  /// created, edited, deleted, restored.
  TextColumn get kind => text()();

  /// The diff, as JSON, for an edit. Null for everything else — "everything
  /// changed" is not a diff, and the entry itself records what it started as.
  TextColumn get changes => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('GroupRow')
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get defaultCurrency => text().references(Currencies, #code)();

  /// A 1:1 split is a two-member group with this set, not a separate concept.
  BoolColumn get isDirect => boolean().withDefault(const Constant(false))();
  BoolColumn get simplifyDebts => boolean().withDefault(const Constant(true))();

  /// Profile id of the creator, if that account still exists.
  ///
  /// Deliberately not a foreign key: a group can arrive by sync before its
  /// creator's profile row does, and refusing the insert would be worse than a
  /// dangling display name.
  ///
  /// Nullable, matching the server. A group outlives the account that made it —
  /// deleting an account sets this to null rather than taking the group down
  /// with it — so "created by nobody who still exists" is a state that arrives
  /// by sync and has to be representable here.
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// Version for last-write-wins, from the server once synced.
  ///
  /// Locally created rows carry a device clock until their first push, which is
  /// safe because a row the server has never seen cannot be in conflict with
  /// anything. From then on both sides of every comparison are server times.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MemberRow')
class Members extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// Null means a placeholder — a real member of the group who has no account
  /// yet. Claiming an invite sets this column and touches nothing else.
  TextColumn get profileId => text().nullable()();
  TextColumn get displayName => text()();
  TextColumn get role => textEnum<MemberRole>()();
  DateTimeColumn get joinedAt => dateTime()();

  /// Members are never deleted; they leave. Their financial history has to stay
  /// referenceable for past entries to make sense.
  DateTimeColumn get leftAt => dateTime().nullable()();

  /// A UPI handle recorded against this member of this group.
  ///
  /// Group-scoped on purpose. A placeholder has no profile at all, and settling
  /// with a placeholder is exactly when their payment handle is needed — so a
  /// profile-only field is missing for precisely the people who need it most.
  /// Falls back to the linked profile's when this is null.
  TextColumn get upiVpa => text().nullable()();

  /// Version for last-write-wins. See [Groups.updatedAt].
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
/// The fixed, global category list. Mirrors the server's, seeded from
/// [presetCategories] and never written to at runtime.
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Material icon name, resolved through a static map. See
  /// `category_icon.dart`.
  TextColumn get icon => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('EntryRow')
class Entries extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => textEnum<EntryKind>()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().nullable()();

  /// The currency the money was actually spent in. Never converted on write.
  TextColumn get currency => text()();

  /// Integer minor units. On the web a Dart int is a double and exact only to
  /// 2^53 — about 90 trillion rupees — which no expense will reach. The
  /// products that would overflow live in the allocator, which uses BigInt.
  IntColumn get amountMinor => integer()();
  DateTimeColumn get entryDate => dateTime()();
  TextColumn get splitKind => textEnum<SplitKind>()();

  /// Display-only snapshot of the rate to the group's default currency at the
  /// time of entry. Never re-fetched: the rate on the day is a fact about the
  /// transaction, not a live quote.
  RealColumn get fxRate => real().nullable()();
  TextColumn get fxSource => text().nullable()();
  DateTimeColumn get fxAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Sync cursor column. Server `now()` once synced, never a client clock.
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Client-generated id making a retried write idempotent.
  TextColumn get clientKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('EntryPayerRow')
class EntryPayers extends Table {
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get memberId => text().references(Members, #id)();
  IntColumn get amountMinor => integer()();

  @override
  Set<Column> get primaryKey => {entryId, memberId};
}

@DataClassName('EntryShareRow')
class EntryShares extends Table {
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get memberId => text().references(Members, #id)();
  IntColumn get amountMinor => integer()();

  /// The original weight scaled by 10^6, matching `numeric(24,6)` on the
  /// server. Null for an exact split, where the amount was the input.
  IntColumn get weightMicros => integer().nullable()();

  @override
  Set<Column> get primaryKey => {entryId, memberId};
}

/// Exchange rates, mirrored from the server.
///
/// Reference data like [Currencies], not a client-side cache: the server
/// fetches rates centrally and every device reads the same rows, so two people
/// looking at one group cannot see different estimates.
///
/// Stored against a single pivot (USD) rather than as currency pairs. A pair
/// table needs n^2 rows and makes "do we have INR to AED?" a different question
/// for every combination; against a pivot there is one row per currency per day
/// and any pair is a division. That is what removes the notion of a supported
/// pair entirely.
@DataClassName('FxRateRow')
class FxRates extends Table {
  /// Publication date as `yyyy-MM-dd`.
  ///
  /// Text rather than a DateTime because it is a date, not an instant, and
  /// because ISO dates sort lexicographically — which is the whole lookup.
  TextColumn get asOf => text()();
  TextColumn get currency => text()();

  /// Units of [currency] per one USD. USD itself is stored as exactly 1, so the
  /// pivot needs no special case.
  RealColumn get rate => real()();

  /// Which provider supplied this row. Rows for one day can come from different
  /// providers, because the server's waterfall fills gaps rather than stopping
  /// at the first success.
  TextColumn get source => text()();

  @override
  Set<Column> get primaryKey => {asOf, currency};
}

/// Pending writes waiting to reach the server. Client-only.
///
/// Every mutation lands in the local tables first and is queued here second, so
/// the UI never waits on a network round trip and a write survives the app
/// being killed mid-flight.
@DataClassName('OutboxRow')
class Outbox extends Table {
  /// `<operation>:<targetId>`.
  ///
  /// Composite on purpose: re-queuing the same row replaces the pending item
  /// instead of stacking another one, so editing an expense five times offline
  /// still results in a single push.
  TextColumn get id => text()();

  /// What kind of row this refers to: `entry`, `group` or `member`.
  TextColumn get operation => text()();

  /// The row's id in its own table.
  TextColumn get targetId => text()();

  /// JSON arguments, for operations that have no local row to read back.
  ///
  /// Row-backed operations deliberately store nothing here: the pusher reads
  /// the current local state at send time, so a queued item can never carry a
  /// stale copy of something that has been edited since.
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  /// Set when the server refused this in a way retrying cannot fix.
  ///
  /// The row is kept rather than deleted. Dropping it silently would lose a
  /// write the user believes they made, with nothing anywhere to explain the
  /// discrepancy — and "my balance is wrong" is already the hardest thing to
  /// support in an app whose state lives on the device.
  DateTimeColumn get deadLetteredAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-group delta-sync position. Client-only.
@DataClassName('SyncCursorRow')
class SyncCursors extends Table {
  TextColumn get groupId => text()();

  /// Highest server `updated_at` already pulled. Null means never synced.
  DateTimeColumn get cursor => dateTime().nullable()();

  /// Id of the last row consumed at exactly [cursor].
  ///
  /// The cursor has to be the pair, not the timestamp alone. Postgres `now()`
  /// is transaction time, so every row written in one transaction shares an
  /// `updated_at` — a bulk sync can easily produce more rows at one timestamp
  /// than a page holds. A `> timestamp` cursor would skip the rest of that
  /// batch forever; a `>= timestamp` cursor would re-read it forever. Ordering
  /// and comparing on `(updated_at, id)` terminates and loses nothing.
  TextColumn get cursorId => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {groupId};
}

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

  /// Profile id of the creator. Deliberately not a foreign key: a group can
  /// arrive by sync before its creator's profile row does, and refusing the
  /// insert would be worse than a dangling display name.
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

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

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();

  /// Null marks a global preset; otherwise a group's own addition.
  TextColumn get groupId =>
      text().nullable().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();

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
  IntColumn get algoVersion => integer().withDefault(const Constant(1))();

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

/// Cached foreign exchange rates. Client-only — this table has no server
/// counterpart.
///
/// Keyed by date so a historical entry can always be shown at the rate that
/// applied when it was created, and so an offline device can fall back to the
/// most recent rate it saw and label the figure as approximate.
@DataClassName('FxRateRow')
class FxRates extends Table {
  /// ECB publication date as `yyyy-MM-dd`.
  TextColumn get date => text()();
  TextColumn get base => text()();
  TextColumn get quote => text()();
  RealColumn get rate => real()();

  @override
  Set<Column> get primaryKey => {date, base, quote};
}

/// Pending writes waiting to reach the server. Client-only.
///
/// Every mutation lands in the local tables first and is queued here second, so
/// the UI never waits on a network round trip and a write survives the app
/// being killed mid-flight.
@DataClassName('OutboxRow')
class Outbox extends Table {
  /// The client key of the affected row, which is also what makes a retry
  /// idempotent server-side.
  TextColumn get id => text()();
  TextColumn get operation => text()();

  /// JSON arguments for the RPC.
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-group delta-sync position. Client-only.
@DataClassName('SyncCursorRow')
class SyncCursors extends Table {
  TextColumn get groupId => text()();

  /// Highest server `updated_at` already pulled. Null means never synced.
  DateTimeColumn get cursor => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {groupId};
}

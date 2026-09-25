import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/calendar_date.dart';
import '../../domain/models/kinds.dart';

/// The local mirror of the server's ledger, plus the client-only sync state.
///
/// These row classes are the app's read models: `Group`, `Member`, `Profile`,
/// `Currency` and `Category` are what screens and domain code receive. Behaviour
/// that belongs to them lives in extensions (`domain/models/*.dart`). `Entry`
/// is the one aggregate with its own type, because an expense is a row plus
/// its payers and shares.
///
/// A mirrored row's `seq` is the group sequence number the server last issued
/// for it. Null means this device created the row and the server has not
/// confirmed it yet, so it cannot be stale against anything.

/// Stores a generated wire enum by its wire value.
///
/// A value this build does not know reads back as the generator's
/// `unknownDefaultOpenApi` sentinel instead of failing the query, so a newer
/// server's new kind costs one unreadable row, not a broken sync.
class WireEnumConverter<T extends Enum> extends TypeConverter<T, String> {
  const WireEnumConverter(this._values, this._unknown);

  final List<T> _values;
  final T _unknown;

  @override
  T fromSql(String fromDb) => fromWire(_values, fromDb) ?? _unknown;

  @override
  String toSql(T value) => '$value';
}

/// A JSON object column.
class JsonMapConverter extends TypeConverter<Map<String, Object?>, String> {
  const JsonMapConverter();

  @override
  Map<String, Object?> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as Map).cast<String, Object?>();

  @override
  String toSql(Map<String, Object?> value) => jsonEncode(value);
}

/// A calendar date, stored as the `yyyy-MM-dd` text it is on the wire, so it
/// sorts and compares as text in SQL.
class CalendarDateConverter extends TypeConverter<DateTime, String> {
  const CalendarDateConverter();

  @override
  DateTime fromSql(String fromDb) => parseCalendarDate(fromDb);

  @override
  String toSql(DateTime value) => calendarDate(value);
}

/// ISO 4217 reference data, refreshed from the server and never edited here.
@DataClassName('Currency')
class Currencies extends Table {
  TextColumn get code => text().withLength(min: 3, max: 3)();

  /// Decimal digits in the minor unit. Read it; never assume 2.
  IntColumn get exponent => integer()();
  TextColumn get symbol => text().nullable()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {code};
}

/// Display details for people with accounts. Financial rows never point here:
/// they reference members, which may have no account at all.
@DataClassName('Profile')
class Profiles extends Table {
  TextColumn get id => text()();

  /// Null until somebody chooses one, which is a different fact from having
  /// chosen a name, so the app asks once instead of respecting a placeholder.
  TextColumn get displayName => text().nullable()();

  /// Personal UPI handle; a member's own handle takes precedence.
  TextColumn get upiVpa => text().nullable()();

  /// The server's timestamp, and the profile feed's cursor. Null for a row
  /// this device wrote and has not pushed.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The server's record of what happened, plus provisional lines this device
/// wrote for changes it has not pushed yet.
///
/// The server's lines replace the provisional ones for the same subject as soon
/// as they arrive. Nothing is rebuilt from these rows: balances read entries
/// only, so a bug here can make the feed wrong but never a balance.
///
/// References cascade (unlike the server) so clearing the ledger on sign-out
/// can delete members that events name.
@DataClassName('GroupEventRow')
class GroupEvents extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// A member id. Null when nobody can be named, which is ordinary for a join.
  TextColumn get actorId =>
      text().nullable().references(Members, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get createdAt => dateTime()();
  TextColumn get kind => text().map(
    const WireEnumConverter(EventKind.values, EventKind.unknownDefaultOpenApi),
  )();

  /// The entry, member or link token this is about; null when it is the group.
  /// Not a foreign key: the record outlives what it describes.
  TextColumn get subjectId => text().nullable()();

  /// The after-image, shaped by [kind]: `api.EntrySnapshot`,
  /// `api.MemberEventPayload`, `api.GroupEventPayload` or
  /// `api.LinkEventPayload`.
  TextColumn get payload => text().map(const JsonMapConverter())();

  /// `(seq, ordinal)` is the feed's total order: one change can record more
  /// than one line, and those share a `seq` and a `createdAt`. Both are null on
  /// a provisional row, which sorts after everything confirmed.
  IntColumn get seq => integer().nullable()();
  IntColumn get ordinal => integer().nullable()();

  /// Written by this device for a change the server has not confirmed. Never
  /// pushed.
  BoolColumn get isProvisional =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A set of people sharing costs. A one-to-one split is a two-member group
/// with [isDirect] set, not a second system.
@DataClassName('Group')
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// What estimated totals are shown in. Entries keep their own currency.
  TextColumn get defaultCurrency => text().references(Currencies, #code)();
  BoolColumn get isDirect => boolean().withDefault(const Constant(false))();
  BoolColumn get simplifyDebts => boolean().withDefault(const Constant(true))();

  /// The creator's member id. Not a foreign key, because the group row and
  /// its members arrive in one page in no particular order.
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  IntColumn get seq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A person's place in one group. Every financial row references a member,
/// and a member with no [profileId] is a placeholder — a full member who has
/// no account yet. Claiming an invite sets that one column.
///
/// Members are never deleted, only [leftAt] set, so past entries still
/// resolve.
@DataClassName('Member')
class Members extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get profileId => text().nullable()();
  TextColumn get displayName => text()();
  DateTimeColumn get joinedAt => dateTime()();
  DateTimeColumn get leftAt => dateTime().nullable()();

  /// This member's UPI handle in this group. Group-scoped because placeholders
  /// have no profile, and settling with one is when a handle is needed most.
  TextColumn get upiVpa => text().nullable()();
  IntColumn get seq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The global category list, from the server.
@DataClassName('Category')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// A Material icon name, resolved in `category_icon.dart`.
  TextColumn get icon => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('EntryRow')
class Entries extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text().map(
    const WireEnumConverter(EntryKind.values, EntryKind.unknownDefaultOpenApi),
  )();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().nullable()();

  /// What the money was spent in. Never converted on write.
  TextColumn get currency => text()();

  /// Integer minor units. Exact on the web up to 2^53, which no expense
  /// reaches; the products that could overflow use BigInt in the allocator.
  IntColumn get amountMinor => integer()();

  TextColumn get entryDate => text().map(const CalendarDateConverter())();
  TextColumn get splitKind => text().map(
    const WireEnumConverter(SplitKind.values, SplitKind.unknownDefaultOpenApi),
  )();

  /// Display-only rate to the group's currency on [entryDate]. Never
  /// re-fetched and never part of a balance.
  RealColumn get fxRate => real().nullable()();
  TextColumn get fxSource => text().nullable()();
  DateTimeColumn get fxAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Also the base the next edit is judged against: the server refuses an
  /// edit composed on an older `seq` only when it would move money.
  IntColumn get seq => integer().nullable()();

  /// Soft delete; entries are never removed.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Client-generated, so a retried push is not a second expense.
  TextColumn get clientKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// An edit the server refused because the expense had moved underneath it.
///
/// The ledger takes the server's version; what this device meant is parked
/// here for a person to read. One row per expense. There is deliberately no
/// "apply mine": redoing an edit happens on the ordinary edit screen, against
/// what the expense says now.
@DataClassName('EntryConflictRow')
class EntryConflicts extends Table {
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// What this device meant the expense to look like, as `api.EntrySnapshot`
  /// JSON.
  TextColumn get attempted => text()();

  /// The version the refused edit was composed against.
  IntColumn get baseSeq => integer().nullable()();

  DateTimeColumn get rejectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entryId};
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

  /// The input weight scaled by 10^6 ("2:1:1", "50/30/20"). Null for an exact
  /// split, where the amount was the input.
  IntColumn get weightMicros => integer().nullable()();

  @override
  Set<Column> get primaryKey => {entryId, memberId};
}

/// Exchange rates against a USD pivot: one row per currency per day, and any
/// pair is a division.
@DataClassName('FxRateRow')
class FxRates extends Table {
  /// Publication date, `yyyy-MM-dd`; ISO dates sort, which is the lookup.
  TextColumn get asOf => text()();
  TextColumn get currency => text()();

  /// Units of [currency] per one USD.
  RealColumn get rate => real()();

  /// Which provider supplied the row.
  TextColumn get source => text()();

  @override
  Set<Column> get primaryKey => {asOf, currency};
}

/// What an outbox item refers to. Pushed in declaration order within a batch:
/// a group before its members, members before the entries that name them.
enum OutboxTarget { group, member, entry, profile }

/// Rows this device changed and has not pushed. Client-only.
///
/// A set of dirty rows, not a log: re-queuing a row replaces its item, and the
/// pusher reads the row's current state at send time.
@DataClassName('OutboxRow')
class Outbox extends Table {
  /// `<target>:<targetId>`, so re-queuing coalesces.
  TextColumn get id => text()();
  TextColumn get target => textEnum<OutboxTarget>()();
  TextColumn get targetId => text()();

  /// Identifies one edit, so a response for an older one is not applied over
  /// a newer one made during the upload.
  TextColumn get revision => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  /// Set when the server refused this permanently. Kept, not deleted, so the
  /// person can see which write never reached the group.
  DateTimeColumn get deadLetteredAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// How far this device has read one group's history. Client-only.
@DataClassName('GroupCursorRow')
class GroupCursors extends Table {
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// The highest sequence number applied. Zero means never synced.
  IntColumn get seq => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {groupId};
}

/// Keyset cursors for feeds with no single writer (profiles live in D1, which
/// cannot issue a sequence number). Also holds the FX backfill floor.
@DataClassName('FeedCursorRow')
class FeedCursors extends Table {
  TextColumn get feed => text()();
  DateTimeColumn get cursor => dateTime().nullable()();

  /// Id of the last row consumed at exactly [cursor].
  TextColumn get cursorId => text().nullable()();

  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {feed};
}

/// A renewable cross-isolate lease on synchronisation: a background push
/// isolate and the foreground app can hold the same database.
class SyncLeases extends Table {
  TextColumn get name => text()();
  TextColumn get owner => text()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

/// Fences late network responses after this account is cleared locally.
class SyncSessions extends Table {
  TextColumn get id => text()();
  TextColumn get epoch => text()();
  BoolColumn get enabled => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

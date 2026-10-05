import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/calendar_date.dart';

/// The local mirror of the server's ledger, plus the client-only sync state.
///
/// The generated row classes (`Group`, `Member`, `Currency`, ...) are the
/// app's models; their few derived getters are in `database.dart`.

/// Stores a generated wire enum by its wire value.
class WireEnumConverter<T extends Enum> extends TypeConverter<T, String> {
  const WireEnumConverter(this._values, this._unknown);

  final List<T> _values;
  final T _unknown;

  @override
  T fromSql(String fromDb) =>
      _values.where((value) => '$value' == fromDb).firstOrNull ?? _unknown;

  @override
  String toSql(T value) => '$value';
}

/// A generated wire type stored as its JSON.
class WireJsonConverter<T> extends TypeConverter<T, String> {
  const WireJsonConverter(this._fromJson);

  final T Function(Map<String, dynamic> json) _fromJson;

  @override
  T fromSql(String fromDb) =>
      _fromJson(jsonDecode(fromDb) as Map<String, dynamic>);

  @override
  String toSql(T value) => jsonEncode(value);
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

/// How a person or a group is pictured; see `domain/avatar.dart`. Exactly the
/// field [avatarKind] reads is set.
mixin AvatarColumns on Table {
  TextColumn get avatarKind => text()
      .map(
        const WireEnumConverter(
          api.AvatarKind.values,
          api.AvatarKind.unknownDefaultOpenApi,
        ),
      )
      .withDefault(const Constant('initials'))();

  /// Null until somebody picks one; the app derives a hue from the id.
  TextColumn get avatarColor => text()
      .map(
        const WireEnumConverter(
          api.AvatarColor.values,
          api.AvatarColor.unknownDefaultOpenApi,
        ),
      )
      .nullable()();
  TextColumn get avatarEmoji => text().nullable()();
  TextColumn get avatarIcon => text()
      .map(
        const WireEnumConverter(
          api.AvatarIcon.values,
          api.AvatarIcon.unknownDefaultOpenApi,
        ),
      )
      .nullable()();

  /// An uploaded picture's key in the media store.
  TextColumn get avatarPhoto => text().nullable()();
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
class Profiles extends Table with AvatarColumns {
  TextColumn get id => text()();

  /// Null until somebody chooses one, which is a different fact from having
  /// chosen a name, so the app asks once instead of respecting a placeholder.
  TextColumn get displayName => text().nullable()();

  /// Personal UPI handle; a member's own handle takes precedence.
  TextColumn get upiVpa => text().nullable()();

  /// The server's version of this row, which the profile feed is cursored
  /// on. Null for a row this device wrote and has not pushed.
  IntColumn get version => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The server's record of what happened, plus provisional lines this device
/// wrote for changes it has not pushed yet.
@DataClassName('GroupEventRow')
@TableIndex(name: 'group_events_group', columns: {#groupId, #seq, #ordinal})
@TableIndex(name: 'group_events_subject', columns: {#subjectId})
@TableIndex(name: 'group_events_actor', columns: {#actorId})
class GroupEvents extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// A member id. Null when nobody can be named, which is ordinary for a join.
  TextColumn get actorId =>
      text().nullable().references(Members, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get createdAt => dateTime()();
  TextColumn get kind => text().map(
    const WireEnumConverter(
      api.EventKind.values,
      api.EventKind.unknownDefaultOpenApi,
    ),
  )();

  /// The entry, member or link token this is about; null when it is the group.
  /// Not a foreign key: the record outlives what it describes.
  TextColumn get subjectId => text().nullable()();

  /// What happened, as on the wire: exactly one is set, chosen by [kind].
  TextColumn get entry => text().nullable().map(
    const WireJsonConverter(api.EntrySnapshot.fromJson),
  )();
  TextColumn get member => text().nullable().map(
    const WireJsonConverter(api.MemberEventPayload.fromJson),
  )();
  TextColumn get group => text().nullable().map(
    const WireJsonConverter(api.GroupEventPayload.fromJson),
  )();
  TextColumn get link => text().nullable().map(
    const WireJsonConverter(api.LinkEventPayload.fromJson),
  )();

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
class Groups extends Table with AvatarColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// What estimated totals are shown in. Entries keep their own currency.
  TextColumn get defaultCurrency => text().references(Currencies, #code)();
  BoolColumn get isDirect => boolean().withDefault(const Constant(false))();
  BoolColumn get simplifyDebts => boolean().withDefault(const Constant(true))();

  /// A generated cover is drawn from the group's spending, so it stores
  /// nothing but the choice.
  TextColumn get coverKind => text()
      .map(
        const WireEnumConverter(
          api.CoverKind.values,
          api.CoverKind.unknownDefaultOpenApi,
        ),
      )
      .withDefault(const Constant('generated'))();
  TextColumn get coverPhoto => text().nullable()();

  /// The creator's member id. Not a foreign key, because the group row and
  /// its members arrive in one page in no particular order.
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  IntColumn get seq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A person's place in one group. Every financial row references a member, and
/// a member with no [profileId] is a placeholder — a full member who has no
/// account yet. Claiming an invite sets that one column.
@DataClassName('Member')
@TableIndex(name: 'members_group', columns: {#groupId})
@TableIndex(name: 'members_profile', columns: {#profileId})
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
@TableIndex(name: 'entries_group', columns: {#groupId, #entryDate})
class Entries extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text().map(
    const WireEnumConverter(
      api.EntryKind.values,
      api.EntryKind.unknownDefaultOpenApi,
    ),
  )();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get categoryId => text().nullable()();

  /// What the money was spent in. Never converted on write.
  TextColumn get currency => text()();

  /// Integer minor units. Exact on the web up to 2^53, which no expense
  /// reaches; the products that could overflow use BigInt in the allocator.
  IntColumn get amountMinor => integer()();

  TextColumn get entryDate => text().map(const CalendarDateConverter())();

  /// When it happened and the IANA zone it happened in, when known: both or
  /// neither, and [entryDate] is that moment's day in that zone.
  DateTimeColumn get occurredAt => dateTime().nullable()();
  TextColumn get timeZone => text().nullable()();
  TextColumn get splitKind => text().map(
    const WireEnumConverter(
      api.SplitKind.values,
      api.SplitKind.unknownDefaultOpenApi,
    ),
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
  /// edit composed on any older `seq`.
  IntColumn get seq => integer().nullable()();

  /// Soft delete; entries are never removed.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// An edit the server refused because the expense had moved underneath it.
@DataClassName('EntryConflictRow')
@TableIndex(name: 'entry_conflicts_group', columns: {#groupId})
class EntryConflicts extends Table {
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// What this device meant the expense to look like.
  TextColumn get attempted =>
      text().map(const WireJsonConverter(api.EntrySnapshot.fromJson))();

  /// The version the refused edit was composed against.
  IntColumn get baseSeq => integer().nullable()();

  DateTimeColumn get rejectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entryId};
}

@DataClassName('EntryPayerRow')
@TableIndex(name: 'entry_payers_member', columns: {#memberId})
class EntryPayers extends Table {
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get memberId => text().references(Members, #id)();
  IntColumn get amountMinor => integer()();

  @override
  Set<Column> get primaryKey => {entryId, memberId};
}

@DataClassName('EntryShareRow')
@TableIndex(name: 'entry_shares_member', columns: {#memberId})
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
@TableIndex(name: 'fx_rates_currency', columns: {#currency, #asOf})
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

/// What an outbox item refers to. Declared in dependency order, which breaks
/// a tie in [Outbox.position]: a group before its members, members before the
/// entries that name them.
enum OutboxTarget { group, member, entry, profile }

/// Rows this device changed and has not pushed. Client-only.
@DataClassName('OutboxRow')
class Outbox extends Table {
  TextColumn get target => textEnum<OutboxTarget>()();
  TextColumn get targetId => text()();

  /// Identifies one edit, so a response for an older one is not applied over
  /// a newer one made during the upload.
  TextColumn get revision => text()();

  /// Where this item is pushed, in the order this device made its changes:
  /// the server checks each write against what it already has, so a
  /// settlement has to arrive before the removal it makes possible. See
  /// `OutboxQueue.enqueue` for how a later edit moves an item.
  IntColumn get position => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  /// Set when the server refused this permanently. Kept, not deleted, so the
  /// person can see which write never reached the group.
  DateTimeColumn get deadLetteredAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {target, targetId};
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

/// Where a feed without a sequence number stands: the profile feed's opaque
/// server cursor, and the FX window's floor date.
@DataClassName('FeedCursorRow')
class FeedCursors extends Table {
  TextColumn get feed => text()();
  TextColumn get cursor => text().nullable()();

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

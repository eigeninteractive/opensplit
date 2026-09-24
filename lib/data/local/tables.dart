import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
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

  /// Null until somebody chooses one. See [Profile.displayName].
  TextColumn get displayName => text().nullable()();

  /// UPI virtual payment address, used to build a settle-up handoff. Personal,
  /// not group-scoped.
  TextColumn get upiVpa => text().nullable()();

  /// The server's timestamp, and what the profiles pull cursors on.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// What an expense looked like at one moment, and who had just changed it.
///
/// A mirror of the server's table, plus one local-only column. The server
/// writes a row for every committed change to an expense -- and is the only
/// thing that can, since no client holds a grant on it. The feed is the
/// difference between consecutive rows, worked out on read.
///
/// This replaced a table of client-authored diffs. The device composed the line
/// saying what it had changed, which meant it could describe a Rs.400 to
/// Rs.4,000 rewrite as a ten-rupee correction, or re-split a bill so somebody
/// else owed more and write no history at all. Neither is reachable now: there
/// is no diff on the wire to falsify, only the expense's own shape.
///
/// Nothing is ever rebuilt from these rows. Balances read entries, and only
/// entries -- so a bug here can make the feed wrong and can never make a
/// balance wrong.
///
/// Every reference cascades, which is where this deliberately differs from the
/// server. There, `actor_id` is ON DELETE RESTRICT so a member with history can
/// never be deleted out from under the record -- but the record it protects is
/// the server's, and this is a mirror. Locally there is nothing to protect and
/// something to break: with no action declared, an event refuses the delete of
/// the very member it names, and clearing the ledger on sign-out failed on a
/// foreign key.
@DataClassName('GroupEventRowData')
class GroupEvents extends Table {
  TextColumn get id => text()();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// The member who did it, not the account: authorship is group-scoped, so a
  /// placeholder's edits survive them claiming an account.
  ///
  /// Nullable, matching the server: a change made by something with no member
  /// row still belongs on the record, and somebody arriving on a link is
  /// exactly that until the statement creating them commits.
  TextColumn get actorId =>
      text().nullable().references(Members, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get createdAt => dateTime()();

  /// The server's `group_event_kind`, stored by its wire name.
  ///
  /// Text rather than a Drift enum column, and that is the one place this
  /// mirror deliberately loses type safety. A `textEnum` throws on a value it
  /// cannot parse, so a server that learns a new kind would break the sync of
  /// every older client that met one — on the feed, which is the least
  /// important thing in the app to be right about and a very bad thing to take
  /// the whole pull down with. Kept as text, an unknown kind is a row that
  /// stores fine and renders as nothing.
  TextColumn get kind => text()();

  /// The entry, member or invite token this is about. Null when the subject is
  /// the group itself.
  ///
  /// Deliberately not a foreign key even locally: the record describes what was
  /// true at the time, and it outlives what it describes.
  TextColumn get subjectId => text().nullable()();

  /// The after-image as JSON, in whatever shape the kind calls for.
  TextColumn get payload => text()();

  /// The sequence number this line was committed at, and its position within
  /// it.
  ///
  /// `(seq, ordinal)` is the feed's total order, and both halves are needed:
  /// one change can append more than one line — a patch that renames and
  /// archives a group is two things that happened — and those lines share a
  /// `seq` and a `createdAt`, because both are taken once per change.
  ///
  /// The server can order such lines by rowid, which is insertion order. This
  /// table cannot: rows arrive in a JSON array and land wherever SQLite puts
  /// them. So the position travels on the wire.
  ///
  /// Null on a provisional row, which by definition has no server version.
  IntColumn get seq => integer().nullable()();
  IntColumn get ordinal => integer().nullable()();

  /// Written by this device, describing a change the server has not confirmed.
  ///
  /// The whole reason the feed works offline and as a guest. Dropped the moment
  /// the server's account of the same subject arrives, so it is a placeholder
  /// for a record rather than a second opinion about one. Local only -- there
  /// is no such column on the server, and this row is never pushed.
  BoolColumn get isProvisional =>
      boolean().withDefault(const Constant(false))();

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

  /// Member id of the creator, and a member id rather than a profile id.
  ///
  /// It used to hold a profile id, which made this the one column that could
  /// empty itself: deleting an account had to null it, so "created by nobody
  /// who still exists" was a state every reader had to handle. A member is a
  /// place in this group rather than an account, and it outlives the account
  /// that claimed it — so the group can always say who started it, and the
  /// answer resolves in the same table as every other name the group shows.
  ///
  /// Deliberately not a foreign key: the group row and its members arrive in
  /// the same page but in no guaranteed order within it.
  ///
  /// Still nullable here, unlike on the server, because this device writes the
  /// row before it has a sequence number and a local-only group is a real
  /// state. Set from creation onwards.
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// The sequence number this row was last received at, or null.
  ///
  /// Null means this device invented the row and the server has not confirmed
  /// it. There is no device-clock equivalent and that is the improvement: a
  /// locally created row simply has no server version yet, rather than
  /// carrying one made up out of a clock that must never decide a conflict.
  ///
  /// This replaced an `updatedAt` that was doing three jobs — sync cursor,
  /// last-write-wins version, and conflict base — none of which it could do
  /// safely, because a client can write a timestamp. See [Entries.seq].
  IntColumn get seq => integer().nullable()();

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

  /// The sequence number this row was last received at. See [Groups.seq].
  IntColumn get seq => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
/// The fixed, global category list. Mirrors the server's, seeded from
/// the server's preset list, and never written to at runtime.
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

  /// The group sequence number this row was last received at.
  ///
  /// One column where there used to be two. `updatedAt` was the sync cursor
  /// and the last-write-wins version; `baseUpdatedAt` was the server version an
  /// edit had been composed against. They had to be separate because a local
  /// edit overwrote `updatedAt` with a device clock and left the base alone.
  ///
  /// A sequence number is only ever issued by the server, so a local edit
  /// invents nothing and this keeps saying what the server last said — which
  /// *is* the base. The push sends it, and the server refuses the write only
  /// when the base has moved and applying the edit would move money.
  ///
  /// Null for a row this device invented and has never pushed: there is no
  /// version to be stale against, so the write is an insert and can never be
  /// refused as a conflict.
  IntColumn get seq => integer().nullable()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Client-generated id making a retried write idempotent.
  TextColumn get clientKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// An edit the server refused because the expense had changed underneath it.
///
/// The third outcome, and it needed to be. The outbox has two: retry with
/// backoff, or set aside permanently. A stale write is neither -- retrying
/// sends the same stale base and is refused identically forever, and it is not
/// permanent because a person can look at both versions and decide.
///
/// So the ledger converges and the intention is parked here. That direction is
/// deliberate: holding the local version instead would leave this device's
/// balances disagreeing with everybody else's for as long as nobody noticed,
/// which is the exact failure this app has spent two redesigns removing. The
/// money follows the server; what you meant becomes something to review.
///
/// One row per expense. A second refused edit replaces the first, because what
/// is being kept is "what this device last wanted this expense to say", not a
/// history of attempts.
///
/// What is deliberately NOT here is a way to re-apply it in one tap. Re-doing
/// an edit is the same act as making it, and the app already has a screen for
/// that; a second write path whose whole purpose is "overwrite what they just
/// corrected, without reading it" would be a worse version of the problem the
/// server check exists to catch. This says what happened and what you had
/// typed. Deciding is done the ordinary way, on the expense itself.
@DataClassName('EntryConflictRow')
class EntryConflicts extends Table {
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// The entry as this device meant to write it, through the wire codec.
  ///
  /// Kept so the notice can say what you had put, which is usually enough to
  /// decide whether you still care -- if somebody else already set the amount
  /// you were setting, there is nothing left to do.
  ///
  /// Stored whole rather than as a diff. A diff would need a base to be read
  /// against, and the base is precisely what has moved.
  TextColumn get attempted => text()();

  /// The version the refused edit was composed against.
  ///
  /// Kept so the notice can fetch exactly what the server has now and show the
  /// two side by side, rather than asking the person to remember.
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

  /// Identifies this particular edit, including edits made during an upload.
  TextColumn get revision => text().withDefault(const Constant(''))();

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

/// How far this device has read one group's history. Client-only.
///
/// One row per group, holding one integer, where there used to be four rows
/// per group each holding a `(timestamp, id)` pair. The group's Durable Object
/// is the only thing that writes it, so it can hand out a strictly increasing
/// number — and a number that is unique per change needs no tiebreak.
///
/// That is what removed the second column. A Postgres `now()` is transaction
/// time, so every row written in one transaction shared an `updated_at`: a
/// `>` cursor would skip the rest of a batch forever and a `>=` cursor would
/// re-read it forever, and the only fix was to order on the pair. None of that
/// arises here.
@DataClassName('GroupCursorRow')
class GroupCursors extends Table {
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();

  /// The highest sequence number already applied. Zero means never synced,
  /// which is also where a fresh cursor starts, so there is no null case.
  IntColumn get seq => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {groupId};
}

/// How far this device has read a feed that no single writer owns.
///
/// Profiles live in D1, which several requests write concurrently, so there is
/// nothing there that can issue a sequence number. Those feeds keep a
/// `(timestamp, id)` keyset cursor, and keeping the two kinds in separate
/// tables says plainly that they are different mechanisms rather than one
/// mechanism with nullable halves.
@DataClassName('FeedCursorRow')
class FeedCursors extends Table {
  /// A stable feed name. Changing it strands the old cursor and re-reads the
  /// feed from the beginning, which is safe but not free.
  TextColumn get feed => text()();

  /// Highest server timestamp already pulled. Null means never synced.
  DateTimeColumn get cursor => dateTime().nullable()();

  /// Id of the last row consumed at exactly [cursor]. Without it, rows sharing
  /// a timestamp are either skipped or re-read forever.
  TextColumn get cursorId => text().nullable()();

  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {feed};
}

/// A short, renewable cross-isolate lease for account synchronization.
///
/// Native push handling can open the same account database in a background
/// isolate while the foreground app is alive. An in-memory mutex cannot span
/// those isolates, so this row is the final authority on whether a sync may
/// start. It is a lease rather than a permanent flag so a killed process never
/// wedges synchronization forever.
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

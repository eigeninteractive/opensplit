import '../../domain/models/entry.dart';
import '../../domain/models/entry_snapshot.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';
import 'change_feed.dart';
import 'sync_cursor.dart';

/// Raised when the server rejects a write.
class RemoteRejected implements Exception {
  const RemoteRejected(this.message, {this.permanent = false});

  final String message;

  /// True when retrying cannot help — a violated invariant, a permission
  /// failure. The outbox drops these rather than retrying forever.
  final bool permanent;

  @override
  String toString() => 'RemoteRejected: $message';
}

/// The entire surface the client needs from a server.
///
/// Deliberately tiny, and deliberately free of business logic: the server
/// stores facts and enforces one invariant. Everything else — splitting,
/// folding balances, simplifying debts, analytics — happens on the device.
///
/// Nothing above `data/` names a backend, so this interface is what makes the
/// self-hosting promise real rather than aspirational, and what provides an
/// exit if the hosted backend's terms change.
abstract interface class RemoteLedgerApi {
  /// Writes an entry with its payers and shares in one transaction.
  ///
  /// Idempotent on `clientKey`: a retry after a dropped connection is safe and
  /// produces no duplicate. Returns the stored entry, carrying the server's
  /// `updatedAt` — never the client's clock, which is what makes last-write-
  /// wins meaningful across devices with different times.
  Future<Entry> upsertEntry(Entry entry);

  /// Soft-deletes an entry, returning it with the server's new `updatedAt`.
  Future<Entry> deleteEntry(String entryId);

  /// This group's expenses, changed strictly after [since].
  ///
  /// Includes soft-deleted rows. A deletion is a change like any other; filter
  /// it out and a deleted expense lives forever on every device that had
  /// already synced it.
  Future<ChangePage<Entry>> pullEntries({
    required String groupId,
    SyncCursor? since,
    required int limit,
  });

  /// Every group this account is currently a member of.
  ///
  /// Without this a device can only ever sync groups it already knows about,
  /// and there is no way to come to know about one: everything else here is
  /// scoped to a `groupId` the caller has to supply. A second device, or a
  /// reinstall, would show an empty app forever — with the data sitting on the
  /// server, readable, and never asked for.
  ///
  /// Groups left behind are excluded. Leaving is the one way membership ends,
  /// and rediscovering a group on the next sync would undo it.
  ///
  /// Deliberately not a feed, and the one thing here that answers "which"
  /// rather than "what changed": a feed needs a cursor, a cursor needs
  /// somewhere to start, and on the device this exists for there is nothing
  /// local to start from.
  Future<List<String>> pullMyGroupIds();

  /// One group's own row, if it changed strictly after [since].
  ///
  /// A page of at most one row, which is worth stating because it looks like
  /// ceremony and is not. Routed through the same cursor as everything else, a
  /// settled group costs an empty answer per sync instead of refetching its row
  /// — and syncs are frequent now that every write triggers one.
  Future<ChangePage<Group>> pullGroup({
    required String groupId,
    SyncCursor? since,
    required int limit,
  });

  /// This group's members, changed strictly after [since].
  ///
  /// Includes members who have left: `left_at` is a column, so leaving is a
  /// change to pull rather than a row to stop sending.
  Future<ChangePage<Member>> pullMembers({
    required String groupId,
    SyncCursor? since,
    required int limit,
  });

  /// Returns the stored row, so the caller can adopt the server's
  /// `updated_at` instead of leaving a device clock in the version column.
  Future<Group> pushGroup(Group group);

  /// Returns the stored row. See [pushGroup].
  Future<Member> pushMember(Member member);

  /// Every profile belonging to somebody you share a group with, plus your own.
  ///
  /// This is what makes a name change travel. Names used to be copied into
  /// `members.display_name` per group, so renaming yourself meant rewriting a
  /// row in every group you were in — and only the ones this device knew about.
  /// Now the name lives on the account and this pull carries it, with the same
  /// `updated_at` cursor everything else uses so a sync fetches only what
  /// actually changed.
  ///
  /// Account-wide rather than per group, and correct because `profiles_read`
  /// already scopes it: your own row plus anybody sharing a group with you. Per
  /// group, somebody in three of your groups was fetched three times.
  Future<ChangePage<Profile>> pullProfiles({
    SyncCursor? since,
    required int limit,
  });

  /// Writes your own name and payment handle. The server refuses any other row.
  Future<Profile> pushProfile(Profile profile);

  /// What has happened to this group's expenses since [since].
  ///
  /// Read-only, and there is deliberately no push counterpart. The server
  /// writes these rows itself, from the expense it actually committed, and no
  /// client holds an insert grant on the table -- which is what makes a feed
  /// line something a reader can trust rather than something the editing device
  /// asserted about itself.
  ///
  /// This replaced a push. While the client authored these rows it could
  /// describe its own edit however it liked, and could re-split a bill so
  /// somebody else owed more while recording nothing at all. Both are
  /// unexpressible now: there is no diff on the wire, only the expense's own
  /// shape at each moment, and the difference between consecutive shapes is
  /// worked out on the device that reads them.
  ///
  /// Cursored on `(created_at, id)` rather than `(updated_at, id)`, and that is
  /// the only way this feed differs from the others: these rows are append-only
  /// and never revised, so there is no second write to order against the first.
  Future<ChangePage<EntrySnapshot>> pullEntrySnapshots({
    required String groupId,
    SyncCursor? since,
    required int limit,
  });

  /// Exchange rates published on or after [since] (`yyyy-MM-dd`).
  ///
  /// Reference data, identical for every user, and immutable once published —
  /// a rate for a past date never changes — so the client keeps a high-water
  /// mark and only ever asks for what came after it.
  Future<List<RemoteFxRate>> pullFxRates({required String since});

  /// Asks the server to fetch rates for a currency on a date it has never
  /// needed before.
  ///
  /// Fire and forget. The daily job keeps recent dates topped up; this covers
  /// an expense backdated past whatever we hold. The rate arrives on a later
  /// sync, so callers must not wait on it.
  Future<void> requestFxBackfill({
    required DateTime asOf,
    required String currency,
  });
}

/// One published rate, against USD.
class RemoteFxRate {
  const RemoteFxRate({
    required this.asOf,
    required this.currency,
    required this.rate,
    required this.source,
  });

  /// Publication date, `yyyy-MM-dd`.
  final String asOf;
  final String currency;

  /// Units of [currency] per one USD.
  final double rate;
  final String source;
}

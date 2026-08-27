import '../../domain/models/entry.dart';
import '../../domain/models/entry_event.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';
import 'sync_cursor.dart';

/// One page of a group's delta feed.
class EntryDelta {
  const EntryDelta({
    required this.entries,
    required this.nextCursor,
    required this.hasMore,
  });

  /// Includes soft-deleted entries. A deletion is a delta like any other; if it
  /// were filtered out, a deleted expense would live forever on every device
  /// that had already synced it.
  final List<Entry> entries;
  final SyncCursor? nextCursor;
  final bool hasMore;
}

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

  /// Rows written strictly after [cursor], ordered by `(updated_at, id)`.
  Future<EntryDelta> pullEntries({
    required String groupId,
    SyncCursor? cursor,
    int limit = 200,
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
  Future<List<String>> pullMyGroupIds();

  Future<Group?> pullGroup(String groupId);

  Future<List<Member>> pullMembers(String groupId);

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
  Future<List<Profile>> pullProfiles({DateTime? since});

  /// Writes your own name and payment handle. The server refuses any other row.
  Future<Profile> pushProfile(Profile profile);

  /// What has happened to this group's expenses since [since].
  Future<List<EntryEvent>> pullEntryEvents({
    required String groupId,
    DateTime? since,
  });

  /// Appends one line to a group's activity feed.
  ///
  /// The device that made the change is the one that describes it, exactly as
  /// it is the device that authors the expense itself. The server's job is to
  /// refuse an event attributed to somebody else, or to a group the caller is
  /// not in, and to make sure no event is ever revised or removed afterwards —
  /// which `entry_events_insert` and the absence of any update or delete policy
  /// together do.
  ///
  /// This replaced a SECURITY DEFINER trigger. The trigger could only fire for
  /// a write that reached the server, so on a device that was offline — or a
  /// guest whose backend was unreachable — the feed stayed empty no matter how
  /// many expenses were added, which is the one screen in the app that did not
  /// work from the local database.
  /// Returns the row as stored, whose `created_at` is the server's and which
  /// the caller adopts — see [entryEventToJson] for why the clock cannot be
  /// this device's.
  Future<EntryEvent> pushEntryEvent(EntryEvent event);

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

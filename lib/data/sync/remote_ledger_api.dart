import '../../domain/models/entry.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
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

  Future<Group?> pullGroup(String groupId);

  Future<List<Member>> pullMembers(String groupId);

  Future<void> pushGroup(Group group);

  Future<void> pushMember(Member member);
}

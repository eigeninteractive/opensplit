import 'sync_cursor.dart';

/// One page of a feed's changes, oldest first.
class ChangePage<T> {
  const ChangePage({
    required this.rows,
    required this.cursor,
    required this.hasMore,
  });

  /// Nothing changed. [cursor] stays where it was.
  ChangePage.empty() : rows = const <Never>[], cursor = null, hasMore = false;

  final List<T> rows;

  /// Where the feed stands after [rows], or null when [rows] is empty.
  ///
  /// Supplied by the adapter from the wire rows rather than derived from the
  /// parsed models. A domain model is free to leave its version nullable — a
  /// group that predates versioning has no `updated_at` — and a cursor is not,
  /// so deriving it would push a `!` into the one place that must not guess.
  final SyncCursor? cursor;

  /// Whether the server has more waiting beyond [cursor].
  final bool hasMore;
}

/// One resource that can be pulled incrementally.
///
/// Every feed in this app is the same shape: rows ordered by a server-owned
/// timestamp paired with an id, asked for strictly after the pair last
/// consumed, applied locally, cursor advanced. Naming that shape once is what
/// makes the parts that actually differ — what a page means, and what applying
/// it does — the only thing each implementation has to say.
///
/// It replaced five hand-rolled pulls with five different cursor semantics:
/// entries paged by keyset, profiles and activity by *offset* over a filtered
/// set, groups and members not at all. Two of those were wrong. Offset paging
/// over `updated_at > since` re-sorts under its own feet — bump a profile
/// mid-sweep and it moves to the end, shifting every row after its old
/// position back by one, so the row at the next offset is never read and the
/// cursor advances past it regardless. And a cursor on the timestamp alone
/// drops rows that share it, which is not hypothetical: `now()` is transaction
/// time, so `redeem_invite` writes a profile and a member at one instant.
///
/// [SyncEngine.drain] is the whole engine, and it is short. Correctness lives
/// there once instead of in five places.
abstract interface class ChangeFeed<T> {
  /// This feed's row in `sync_cursors`.
  ///
  /// Stable across releases: changing it strands the old cursor and re-pulls
  /// the feed from the beginning, which is safe but not free.
  String get key;

  /// Rows changed strictly after [since], oldest first, at most [limit] of
  /// them.
  Future<ChangePage<T>> fetch({SyncCursor? since, required int limit});

  /// Writes [rows] locally, returning how many actually changed anything.
  ///
  /// A row the local copy already has at least as new a version of is counted
  /// as unchanged: the pull is allowed to arrive after a local edit that has
  /// not been pushed yet, and must not undo it.
  Future<int> apply(List<T> rows);
}

/// Position in a [ChangeFeed].
///
/// A pair rather than a timestamp, because the timestamp is not unique:
/// Postgres `now()` is transaction time, so a batch written in one transaction
/// shares a single value. Rows are ordered by `(at, id)` and the client asks
/// for everything strictly after the pair it last consumed.
///
/// [at] rather than `updatedAt`, because it is not always `updated_at`: the
/// activity feed is append-only and orders on `created_at`. What matters to a
/// cursor is that the column is server-owned and monotonic per row, not which
/// column it is.
class SyncCursor implements Comparable<SyncCursor> {
  const SyncCursor(this.at, this.id);

  final DateTime at;
  final String id;

  @override
  int compareTo(SyncCursor other) {
    final byTime = at.compareTo(other.at);
    return byTime != 0 ? byTime : id.compareTo(other.id);
  }

  bool isBefore(SyncCursor other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is SyncCursor && other.at == at && other.id == id;

  @override
  int get hashCode => Object.hash(at, id);

  @override
  String toString() => 'SyncCursor(${at.toIso8601String()}, $id)';
}

/// Position in a group's delta feed.
///
/// A pair rather than a timestamp, because `updated_at` is not unique: Postgres
/// `now()` is transaction time, so a batch written in one transaction shares a
/// single value. Rows are ordered by `(updated_at, id)` and the client asks for
/// everything strictly after the pair it last consumed.
class SyncCursor implements Comparable<SyncCursor> {
  const SyncCursor(this.updatedAt, this.id);

  final DateTime updatedAt;
  final String id;

  @override
  int compareTo(SyncCursor other) {
    final byTime = updatedAt.compareTo(other.updatedAt);
    return byTime != 0 ? byTime : id.compareTo(other.id);
  }

  bool isBefore(SyncCursor other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is SyncCursor && other.updatedAt == updatedAt && other.id == id;

  @override
  int get hashCode => Object.hash(updatedAt, id);

  @override
  String toString() => 'SyncCursor(${updatedAt.toIso8601String()}, $id)';
}

import 'package:opensplit/domain/activity/snapshot_diff.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/models/entry_snapshot.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

/// What a feed line says, worked out from two snapshots of the same expense.
///
/// The rules used to live on the writing device, which composed the diff and
/// pushed it. They live here instead, on the reading device, over records the
/// server wrote -- so a line can no longer be anything its author preferred it
/// to be.
void main() {
  final at = DateTime.utc(2026, 8, 27, 9);
  var seq = 0;

  EntrySnapshot snap({
    int amountMinor = 40000,
    String description = 'Dinner',
    String currency = 'INR',
    String? notes,
    String? categoryId,
    DateTime? entryDate,
    DateTime? deletedAt,
    Map<String, int> shares = const {'m1': 40000},
    Map<String, int> payers = const {'m1': 40000},
    String? actorId = 'm1',
  }) => EntrySnapshot(
    id: 'snap-${seq++}',
    entryId: 'e1',
    groupId: 'g1',
    actorId: actorId,
    createdAt: at,
    description: description,
    currency: currency,
    amountMinor: amountMinor,
    entryDate: entryDate ?? DateTime.utc(2026, 8, 20),
    splitKind: SplitKind.equal,
    categoryId: categoryId,
    notes: notes,
    deletedAt: deletedAt,
    payers: [
      for (final row in payers.entries)
        MemberAmount(memberId: row.key, amountMinor: row.value),
    ]..sort((a, b) => a.memberId.compareTo(b.memberId)),
    shares: [
      for (final row in shares.entries)
        MemberAmount(memberId: row.key, amountMinor: row.value),
    ]..sort((a, b) => a.memberId.compareTo(b.memberId)),
  );

  test('the first snapshot of an expense is its creation', () {
    final event = describeSnapshot(previous: null, current: snap());

    expect(event.kind, EntryEventKind.created);
    expect(
      event.changes,
      isEmpty,
      reason:
          '"everything changed" is not a diff, and the snapshot itself is '
          'already the record of what it started as',
    );
    expect(event.actorId, 'm1');
    expect(event.entryId, 'e1');
  });

  test('an edit records what changed, from and to', () {
    final event = describeSnapshot(
      previous: snap(),
      current: snap(amountMinor: 30000, payers: {'m1': 30000},
          shares: {'m1': 30000}),
    );

    expect(event.kind, EntryEventKind.edited);
    final amount = event.changes.firstWhere(
      (c) => c.field == 'amount_minor',
    );
    expect(amount.from, '40000');
    expect(amount.to, '30000');
  });

  test('several changes come back in one stable order', () {
    final event = describeSnapshot(
      previous: snap(),
      current: snap(description: 'Lunch', notes: 'split evenly'),
    );

    expect(
      event.changes.map((c) => c.field),
      ['description', 'notes'],
      reason: 'sorted by field, so an edit reads the same on every device',
    );
  });

  test('saving something unchanged is not an edit', () {
    expect(diffSnapshots(snap(), snap()), isEmpty);
    expect(
      recordsSameShape(snap(), snap()),
      isTrue,
      reason: 'a re-saved editor must not add a line to anybody\'s feed',
    );
  });

  test('an empty string and a null are the same absence', () {
    expect(diffSnapshots(snap(notes: null), snap(notes: '')), isEmpty);
  });

  test('clearing a field records it as cleared, not as a change to empty', () {
    final event = describeSnapshot(
      previous: snap(notes: 'split evenly'),
      current: snap(notes: null),
    );
    final change = event.changes.single;
    expect(change.field, 'notes');
    expect(change.from, 'split evenly');
    expect(change.to, isNull);
  });

  test('a soft delete is a deletion, not an edit of a timestamp', () {
    final event = describeSnapshot(
      previous: snap(),
      current: snap(deletedAt: at),
    );
    expect(event.kind, EntryEventKind.deleted);
    expect(event.changes, isEmpty);
  });

  test('and undeleting is a restore', () {
    final event = describeSnapshot(
      previous: snap(deletedAt: at),
      current: snap(),
    );
    expect(event.kind, EntryEventKind.restored);
  });

  test('a change nobody can be named for is still a change', () {
    final event = describeSnapshot(
      previous: null,
      current: snap(actorId: null),
    );
    expect(event.actorId, isNull);
    expect(
      event.kind,
      EntryEventKind.created,
      reason:
          'silence would be the worse answer: a change with no member row '
          'behind it still has to be on the record',
    );
  });

  // -------------------------------------------------------------------------
  // The split, which is where money actually moves
  // -------------------------------------------------------------------------
  test('re-splitting a bill is reported per member, both sides', () {
    // The total does not move, so the balance invariant is satisfied and the
    // expense looks untouched. A hundred rupees has still changed hands.
    final event = describeSnapshot(
      previous: snap(shares: {'m1': 20000, 'm2': 20000}),
      current: snap(shares: {'m1': 30000, 'm2': 10000}),
    );

    expect(event.kind, EntryEventKind.edited);
    expect(event.changes.map((c) => c.field), ['share:m1', 'share:m2']);
    expect(event.changes.first.from, '20000');
    expect(event.changes.first.to, '30000');
  });

  test('somebody added to a split reads as a share set, not changed', () {
    final event = describeSnapshot(
      previous: snap(shares: {'m1': 40000}),
      current: snap(shares: {'m1': 20000, 'm2': 20000}),
    );

    final added = event.changes.firstWhere((c) => c.field == 'share:m2');
    expect(added.from, isNull);
    expect(added.to, '20000');
  });

  test('somebody dropped from a split reads as a share cleared', () {
    final event = describeSnapshot(
      previous: snap(shares: {'m1': 20000, 'm2': 20000}),
      current: snap(shares: {'m1': 40000}),
    );

    final dropped = event.changes.firstWhere((c) => c.field == 'share:m2');
    expect(dropped.from, '20000');
    expect(dropped.to, isNull);
  });

  test('who paid is reported too', () {
    final event = describeSnapshot(
      previous: snap(payers: {'m1': 40000}),
      current: snap(payers: {'m2': 40000}),
    );

    expect(
      event.changes.map((c) => c.field).toList()..sort(),
      ['paid:m1', 'paid:m2'],
    );
  });

  test('a re-split is not mistaken for an unchanged expense', () {
    expect(
      recordsSameShape(
        snap(shares: {'m1': 20000, 'm2': 20000}),
        snap(shares: {'m1': 30000, 'm2': 10000}),
      ),
      isFalse,
      reason:
          'the dedup rule must not swallow the one edit that moves money '
          'without moving the total',
    );
  });
}

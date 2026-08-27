import 'package:opensplit/domain/activity/entry_events.dart';
import 'package:opensplit/domain/models/entry.dart';
import 'package:opensplit/domain/models/entry_event.dart';
import 'package:opensplit/domain/split/splitter.dart';
import 'package:test/test.dart';

/// The rules the server's trigger used to hold, now held here — where they can
/// run with no server in sight, which is the entire reason they moved.
void main() {
  final at = DateTime.utc(2026, 8, 27, 9);

  Entry entryOf({
    int amountMinor = 40000,
    String description = 'Dinner',
    String currency = 'INR',
    String? notes,
    String? categoryId,
    DateTime? entryDate,
    DateTime? deletedAt,
  }) => Entry(
    id: 'e1',
    groupId: 'g1',
    kind: EntryKind.expense,
    description: description,
    categoryId: categoryId,
    currency: currency,
    amountMinor: amountMinor,
    entryDate: entryDate ?? DateTime.utc(2026, 8, 20),
    splitKind: SplitKind.equal,
    payers: [EntryPayer(memberId: 'm1', amountMinor: amountMinor)],
    shares: [EntryShare(memberId: 'm1', amountMinor: amountMinor)],
    notes: notes,
    createdBy: 'm1',
    createdAt: at,
    updatedAt: at,
    deletedAt: deletedAt,
  );

  EntryEvent? describe(Entry? before, Entry after, {String? actor = 'm1'}) =>
      describeEntryWrite(
        before: before,
        after: after,
        actorId: actor,
        id: 'ev1',
        at: at,
      );

  test('a new expense is a created event, with no diff', () {
    final event = describe(null, entryOf())!;

    expect(event.kind, EntryEventKind.created);
    expect(
      event.changes,
      isEmpty,
      reason:
          '"everything changed" is not a diff, and the entry itself is '
          'already the record of what it started as',
    );
    expect(event.actorId, 'm1');
    expect(event.entryId, 'e1');
  });

  test('an edit records what changed, from and to', () {
    final event = describe(entryOf(), entryOf(amountMinor: 30000))!;

    expect(event.kind, EntryEventKind.edited);
    expect(event.changes, [
      const FieldChange(field: 'amount_minor', from: '40000', to: '30000'),
    ]);
  });

  test('several changes come back in one stable order', () {
    final event = describe(
      entryOf(),
      entryOf(amountMinor: 30000, description: 'Lunch', currency: 'EUR'),
    )!;

    expect(event.changes.map((c) => c.field), [
      'amount_minor',
      'currency',
      'description',
    ], reason: 'sorted, so an event reads identically wherever it was written');
  });

  test('saving something unchanged is not an edit', () {
    expect(
      describe(entryOf(), entryOf()),
      isNull,
      reason:
          'a re-saved editor and a retried sync both land here, and a feed '
          'full of "Ravi edited nothing" is worse than no feed',
    );
  });

  test('an empty string and a null are the same absence', () {
    expect(
      describe(entryOf(notes: null), entryOf(notes: '')),
      isNull,
      reason:
          'the editor writes empty, the server holds null; comparing them '
          'literally would report an edit on every round trip',
    );
  });

  test('clearing a field records it as cleared, not as a change to empty', () {
    final event = describe(entryOf(notes: 'Split with Arun'), entryOf())!;

    expect(event.changes.single.field, 'notes');
    expect(event.changes.single.to, isNull);
  });

  test('a soft delete is a deletion, not an edit of deleted_at', () {
    final event = describe(entryOf(), entryOf(deletedAt: at))!;

    expect(event.kind, EntryEventKind.deleted);
    expect(event.changes, isEmpty);
  });

  test('and undeleting is a restore', () {
    final event = describe(entryOf(deletedAt: at), entryOf())!;

    expect(event.kind, EntryEventKind.restored);
  });

  test('nothing is recorded when there is nobody to attribute it to', () {
    expect(
      describe(null, entryOf(), actor: null),
      isNull,
      reason: 'an event with no actor is a row the feed cannot render',
    );
  });

  test(
    'the date is compared as a date, in the form the diff has always held',
    () {
      final event = describe(
        entryOf(),
        entryOf(entryDate: DateTime.utc(2026, 8, 21)),
      )!;

      expect(event.changes.single.field, 'entry_date');
      expect(event.changes.single.from, '2026-08-20');
      expect(event.changes.single.to, '2026-08-21');
    },
  );
}

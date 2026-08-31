import 'dart:async';

import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:test/test.dart';

void main() {
  test('external sync refresh re-runs live database queries', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final rows = StreamIterator(db.select(db.groups).watch());
    addTearDown(rows.cancel);
    expect(await rows.moveNext(), isTrue);
    expect(rows.current, isEmpty);

    // customStatement stands in for the second connection used by Android's
    // background isolate: the file changed, but this connection did not issue
    // the write through a Drift statement and therefore emitted no update.
    await db.customStatement(
      'INSERT INTO groups '
      '(id, name, default_currency, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        'g1',
        'Goa Trip',
        'INR',
        DateTime.utc(2026, 8, 31).toIso8601String(),
        DateTime.utc(2026, 8, 31).toIso8601String(),
      ],
    );

    db.refreshAfterExternalSync();

    expect(await rows.moveNext(), isTrue);
    expect(rows.current.single.name, 'Goa Trip');
  });
}

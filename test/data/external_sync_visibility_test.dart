import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:opensplit/data/local/database.dart';
import 'package:test/test.dart';

import '../harness.dart';

/// The push handler wakes in its own Flutter engine and writes through its
/// own connection to the same file, which Drift on this connection never sees.
void main() {
  late Directory directory;
  late AppDatabase app;
  late AppDatabase handler;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('opensplit');
    final file = File('${directory.path}/ledger.sqlite');
    app = AppDatabase(NativeDatabase(file));
    await seedReferenceData(app);
    handler = AppDatabase(NativeDatabase(file));
  });

  tearDown(() async {
    await app.close();
    await handler.close();
    await directory.delete(recursive: true);
  });

  Future<void> writeGroupFromHandler() => handler.customStatement(
    'INSERT INTO groups (id, name, default_currency, created_at, seq) '
    'VALUES (?, ?, ?, ?, ?)',
    ['g1', 'Goa Trip', 'INR', DateTime.utc(2026, 8, 31).toIso8601String(), 7],
  );

  test('a write from another connection re-runs live queries', () async {
    final rows = StreamIterator(app.select(app.groups).watch());
    addTearDown(rows.cancel);
    expect(await rows.moveNext(), isTrue);
    expect(rows.current, isEmpty);

    await writeGroupFromHandler();
    await app.noticeWritesElsewhere();

    expect(await rows.moveNext(), isTrue);
    expect(rows.current.single.name, 'Goa Trip');
  });

  test('nothing is re-run when no other connection wrote', () async {
    var emitted = 0;
    final subscription = app
        .select(app.groups)
        .watch()
        .listen((_) => emitted++);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(emitted, 1);

    // A write of this connection's own, to a table the stream does not read:
    // Drift already knows about these, and they leave data_version alone.
    await app.customStatement(
      "INSERT INTO fx_rates (as_of, currency, rate, source) "
      "VALUES ('2026-09-01', 'EUR', 0.9, 'test')",
    );
    await app.noticeWritesElsewhere();
    await pumpEventQueue();

    expect(emitted, 1);
  });
}

import 'package:drift/drift.dart';

import '../local/database.dart';

/// Currency reference data, read from the local table seeded at first run.
final class DriftCurrencyRepository {
  DriftCurrencyRepository(this._db);

  final AppDatabase _db;

  Future<List<Currency>> all() async {
    final rows = await (_db.select(
      _db.currencies,
    )..orderBy([(t) => OrderingTerm.asc(t.code)])).get();
    return [for (final row in rows) row];
  }

  /// The currency for [code], or null if it is not one this build knows.
  Future<Currency?> byCode(String code) async {
    final row = await (_db.select(
      _db.currencies,
    )..where((t) => t.code.equals(code))).getSingleOrNull();
    return row;
  }

  Stream<List<Currency>> watchAll() =>
      (_db.select(_db.currencies)..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .watch()
          .map((rows) => [for (final row in rows) row]);
}

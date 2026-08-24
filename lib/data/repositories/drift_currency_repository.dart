import 'package:drift/drift.dart';

import '../../domain/models/currency.dart';
import '../local/database.dart';
import 'mappers.dart';

/// Currency reference data, read from the local table seeded at first run.
///
/// Exists so that no caller is ever tempted to hardcode an exponent. Every
/// conversion between a typed amount and stored minor units goes through a
/// [Currency] fetched here — JPY has no minor unit and KWD has three, so an
/// assumed 2 is a shipped bug in two directions.
final class DriftCurrencyRepository {
  DriftCurrencyRepository(this._db);

  final AppDatabase _db;

  Future<List<Currency>> all() async {
    final rows = await (_db.select(
      _db.currencies,
    )..orderBy([(t) => OrderingTerm.asc(t.code)])).get();
    return [for (final row in rows) row.toDomain()];
  }

  /// The currency for [code], or null if it is not one this build knows.
  Future<Currency?> byCode(String code) async {
    final row = await (_db.select(
      _db.currencies,
    )..where((t) => t.code.equals(code))).getSingleOrNull();
    return row?.toDomain();
  }

  Stream<List<Currency>> watchAll() =>
      (_db.select(_db.currencies)..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);
}

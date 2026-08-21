import 'package:drift/drift.dart';

import '../../domain/models/currency.dart';
import '../../domain/repositories/currency_repository.dart';
import '../local/database.dart';
import 'mappers.dart';

/// Currency reference data, read from the local table seeded at first run.
final class DriftCurrencyRepository implements CurrencyRepository {
  DriftCurrencyRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Currency>> all() async {
    final rows = await (_db.select(
      _db.currencies,
    )..orderBy([(t) => OrderingTerm.asc(t.code)])).get();
    return [for (final row in rows) row.toDomain()];
  }

  @override
  Future<Currency?> byCode(String code) async {
    final row = await (_db.select(
      _db.currencies,
    )..where((t) => t.code.equals(code))).getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Stream<List<Currency>> watchAll() =>
      (_db.select(_db.currencies)..orderBy([(t) => OrderingTerm.asc(t.code)]))
          .watch()
          .map((rows) => [for (final row in rows) row.toDomain()]);
}

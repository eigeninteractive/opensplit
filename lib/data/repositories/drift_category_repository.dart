import 'package:drift/drift.dart';

import '../local/database.dart';

/// Reads the fixed category list seeded into the local database.
final class DriftCategoryRepository {
  DriftCategoryRepository(this._db);

  final AppDatabase _db;

  /// Rowid order, which is insertion order, which is the order in
  /// the server's preset list — sorted by how often a thing is actually shared
  /// rather than alphabetically. Sorting by name here would undo that.
  SimpleSelectStatement<$CategoriesTable, Category> get _query =>
      _db.select(_db.categories);

  /// Every category, in the order they are offered.
  Stream<List<Category>> watchAll() =>
      _query.watch().map((rows) => [for (final row in rows) row]);

  Future<List<Category>> all() async {
    final rows = await _query.get();
    return [for (final row in rows) row];
  }
}

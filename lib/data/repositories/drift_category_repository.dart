import 'package:drift/drift.dart';

import '../../domain/models/category.dart';
import '../local/database.dart';
import 'mappers.dart';

/// Reads the fixed category list seeded into the local database.
///
/// There is no create and no delete. The list is reference data, the same on
/// every device and on the server, which is the only way an entry's category
/// can mean the same thing to the person who recorded it and the person
/// reading the group's spending a month later.
final class DriftCategoryRepository {
  DriftCategoryRepository(this._db);

  final AppDatabase _db;

  /// Rowid order, which is insertion order, which is the order in
  /// [presetCategories] — sorted by how often a thing is actually shared
  /// rather than alphabetically. Sorting by name here would undo that.
  SimpleSelectStatement<$CategoriesTable, CategoryRow> get _query =>
      _db.select(_db.categories);

  /// Every category, in the order they are offered.
  Stream<List<Category>> watchAll() =>
      _query.watch().map((rows) => [for (final row in rows) row.toDomain()]);

  Future<List<Category>> all() async {
    final rows = await _query.get();
    return [for (final row in rows) row.toDomain()];
  }
}

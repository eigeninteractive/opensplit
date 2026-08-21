import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../local/database.dart';
import 'mappers.dart';

final class DriftCategoryRepository implements CategoryRepository {
  DriftCategoryRepository(this._db, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  SimpleSelectStatement<$CategoriesTable, CategoryRow> _query(String groupId) =>
      _db.select(_db.categories)
        ..where((t) => t.groupId.isNull() | t.groupId.equals(groupId))
        ..orderBy([
          // Presets first, then the group's own additions, each alphabetical.
          (t) => OrderingTerm.asc(t.groupId),
          (t) => OrderingTerm.asc(t.name),
        ]);

  @override
  Stream<List<Category>> watchForGroup(String groupId) => _query(
    groupId,
  ).watch().map((rows) => [for (final row in rows) row.toDomain()]);

  @override
  Future<List<Category>> forGroup(String groupId) async {
    final rows = await _query(groupId).get();
    return [for (final row in rows) row.toDomain()];
  }

  @override
  Future<Category> create(
    String groupId, {
    required String name,
    String? icon,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A category needs a name.');
    }

    final category = Category(
      id: _uuid.v4(),
      groupId: groupId,
      name: trimmed,
      icon: icon,
    );
    await _db
        .into(_db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: category.id,
            groupId: Value(groupId),
            name: category.name,
            icon: Value(icon),
          ),
        );
    return category;
  }

  @override
  Future<void> remove(String categoryId) async {
    await (_db.delete(_db.categories)
          // Presets are shared by every group and are not a group's to delete.
          ..where((t) => t.id.equals(categoryId) & t.groupId.isNotNull()))
        .go();
  }
}

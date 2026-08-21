import '../models/category.dart';

abstract interface class CategoryRepository {
  /// Categories available to a group: the global presets plus its own.
  Stream<List<Category>> watchForGroup(String groupId);

  Future<List<Category>> forGroup(String groupId);

  Future<Category> create(String groupId, {required String name, String? icon});

  /// Removes a group's own category. Entries that used it keep their history
  /// and simply become uncategorised, because `category_id` is nullable and
  /// deleting a label must never delete a fact about money.
  Future<void> remove(String categoryId);
}

import '../models/category.dart';

abstract interface class CategoryRepository {
  /// Every category, in the order they are offered.
  Stream<List<Category>> watchAll();

  Future<List<Category>> all();
}

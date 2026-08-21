import 'package:freezed_annotation/freezed_annotation.dart';

part 'category.freezed.dart';

/// A spend category.
///
/// A null [groupId] marks a global preset shipped with the app; a non-null one
/// is a group's own addition. Both live in the same table so that an entry's
/// `category_id` has a single meaning.
@freezed
abstract class Category with _$Category {
  const factory Category({
    required String id,
    String? groupId,
    required String name,
    String? icon,
  }) = _Category;

  const Category._();

  bool get isPreset => groupId == null;
}

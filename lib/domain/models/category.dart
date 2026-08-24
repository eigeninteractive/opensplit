import 'package:freezed_annotation/freezed_annotation.dart';

part 'category.freezed.dart';

/// A spend category.
///
/// The list is global, fixed, and identical on every device and on the server.
/// There are deliberately no per-group categories: one invented on a phone
/// would tag entries with an id nobody else recognises, and "by category" would
/// quietly mean something different to each member.
@freezed
abstract class Category with _$Category {
  const factory Category({
    required String id,
    required String name,

    /// Material icon name, resolved through a static map in the UI layer.
    required String icon,
  }) = _Category;
}

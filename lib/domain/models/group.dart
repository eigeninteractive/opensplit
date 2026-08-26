import 'package:freezed_annotation/freezed_annotation.dart';

part 'group.freezed.dart';

/// A set of people sharing costs.
///
/// A one-to-one split is not a separate concept: it is a two-member group with
/// [isDirect] set. There is deliberately no second system for "friends", which
/// would otherwise duplicate the entire balance and settlement path.
@freezed
abstract class Group with _$Group {
  const factory Group({
    required String id,
    required String name,

    /// The currency totals are summarised in. Individual entries keep their own
    /// currency; this only decides what the estimated roll-up is shown in.
    required String defaultCurrency,
    @Default(false) bool isDirect,
    @Default(true) bool simplifyDebts,
    String? createdBy,
    required DateTime createdAt,
    DateTime? archivedAt,

    /// Version for last-write-wins, from the server once synced.
    ///
    /// Null on a row this device created and has not yet pushed, which cannot
    /// be in conflict with anything — the server has never seen it.
    DateTime? updatedAt,
  }) = _Group;

  const Group._();

  bool get isArchived => archivedAt != null;
}

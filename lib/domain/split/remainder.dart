import 'allocation.dart';

/// Why fixed values cannot yet form a complete allocation.
enum RemainderProblem {
  noMembers,
  invalidOverrides,
  overallocated,
  unallocated,
}

/// Fixed values plus an equal allocation of the remainder to automatic rows.
///
/// Presence in [overrides] means fixed; absence means automatic. Values are
/// integer units, so money and percentages can use the same calculation.
/// Invalid drafts keep valid fixed values, but never invent negative shares
/// or silently change an override to make the total balance.
final class RemainderAllocation {
  factory RemainderAllocation({
    required int total,
    required Set<String> memberIds,
    required Map<String, int?> overrides,
    String? seed,
  }) {
    if (total < 0) throw ArgumentError('A total must be non-negative.');
    final automatic = memberIds.difference(overrides.keys.toSet());
    final values = <String, int>{};
    final invalid = <String>{};
    for (final id in memberIds.intersection(overrides.keys.toSet())) {
      final value = overrides[id];
      if (value == null || value < 0) {
        invalid.add(id);
      } else {
        values[id] = value;
      }
    }
    final remaining =
        (BigInt.from(total) -
                values.values.fold(
                  BigInt.zero,
                  (sum, value) => sum + BigInt.from(value),
                ))
            .toInt();
    final problem = switch (true) {
      _ when memberIds.isEmpty => RemainderProblem.noMembers,
      _ when invalid.isNotEmpty => RemainderProblem.invalidOverrides,
      _ when remaining < 0 => RemainderProblem.overallocated,
      _ when automatic.isEmpty && remaining > 0 => RemainderProblem.unallocated,
      _ => null,
    };
    if (problem == null && automatic.isNotEmpty) {
      final allocated = allocateLargestRemainder(
        totalMinor: remaining,
        parties: [for (final id in automatic) (memberId: id, weightMicros: 1)],
        seed: seed,
      );
      values.addAll(allocated);
    }
    return RemainderAllocation._(
      values: Map.unmodifiable(values),
      automatic: Set.unmodifiable(automatic),
      invalid: Set.unmodifiable(invalid),
      remaining: remaining,
      problem: problem,
    );
  }

  const RemainderAllocation._({
    required this.values,
    required this.automatic,
    required this.invalid,
    required this.remaining,
    required this.problem,
  });

  /// All resolved values when balanced, or the valid overrides when not.
  final Map<String, int> values;

  /// Selected members whose values follow the remainder.
  final Set<String> automatic;

  /// Selected members with an unreadable or negative override.
  final Set<String> invalid;

  /// Units left after the valid fixed values, before automatic allocation.
  final int remaining;

  /// Null when [values] contains a complete, balanced allocation.
  final RemainderProblem? problem;

  /// Whether these values are ready to become a split or payer allocation.
  bool get isBalanced => problem == null;
}

import 'allocation.dart';

/// How the shares of an entry were specified by the user.
///
/// Mirrors the `split_kind` enum in Postgres.
enum SplitKind { equal, exact, shares, percent }

/// A share after resolution: what this member owes, plus the rule that produced
/// it.
///
/// Both halves are persisted. [amountMinor] is an immutable historical fact —
/// if only the rule were stored, a future rounding fix would retroactively move
/// money that has already been settled. [weightMicros] keeps the user's intent
/// ("2:1:1") editable — if only the amount were stored, reopening the split
/// screen could not show what was originally meant. It is null for
/// [SplitKind.exact], where the amount *is* the input.
typedef ResolvedShare = ({String memberId, int amountMinor, int? weightMicros});

/// Raised when a split cannot be resolved because the inputs are inconsistent.
///
/// These are user-facing conditions ("percentages add up to 97%"), not bugs, so
/// they carry a message the UI can show directly.
class SplitException implements Exception {
  const SplitException(this.message);
  final String message;

  @override
  String toString() => 'SplitException: $message';
}

/// How an entry's total is divided among members.
///
/// Every variant resolves to the same shape — integer minor units summing to
/// exactly the entry total — so downstream code (the balance fold, the sync
/// payload, the invariant trigger) never branches on split kind.
sealed class SplitSpec {
  const SplitSpec();

  SplitKind get kind;

  /// Resolves this specification against [totalMinor].
  ///
  /// The result sums to exactly [totalMinor] and is ordered by member id.
  /// Throws [SplitException] if the inputs do not describe a valid split.
  List<ResolvedShare> resolve(int totalMinor);
}

/// Split evenly. The overwhelming majority of real expenses.
///
/// Rounding leftovers are distributed by largest remainder, so ₹100 across
/// three people is 33.34 / 33.33 / 33.33 rather than three amounts that quietly
/// fail to add up.
final class EqualSplit extends SplitSpec {
  const EqualSplit(this.memberIds);

  final List<String> memberIds;

  @override
  SplitKind get kind => SplitKind.equal;

  @override
  List<ResolvedShare> resolve(int totalMinor) {
    if (memberIds.isEmpty) {
      throw const SplitException('An expense needs at least one participant.');
    }
    if (memberIds.toSet().length != memberIds.length) {
      throw const SplitException('The same person is listed twice.');
    }

    final allocation = allocateLargestRemainder(
      totalMinor: totalMinor,
      parties: [
        for (final id in memberIds) (memberId: id, weightMicros: weightScale),
      ],
    );
    return [
      for (final entry in allocation.entries)
        (
          memberId: entry.key,
          amountMinor: entry.value,
          weightMicros: weightScale,
        ),
    ];
  }
}

/// The user typed each amount directly. No allocation, only validation.
final class ExactSplit extends SplitSpec {
  const ExactSplit(this.amountsByMemberId);

  final Map<String, int> amountsByMemberId;

  @override
  SplitKind get kind => SplitKind.exact;

  @override
  List<ResolvedShare> resolve(int totalMinor) {
    if (amountsByMemberId.isEmpty) {
      throw const SplitException('An expense needs at least one participant.');
    }
    for (final amount in amountsByMemberId.values) {
      if (amount < 0) {
        throw const SplitException('A share cannot be negative.');
      }
    }

    final sum = amountsByMemberId.values.fold(0, (a, b) => a + b);
    if (sum != totalMinor) {
      throw SplitException(
        'The shares add up to $sum, but the total is $totalMinor.',
      );
    }

    final ids = amountsByMemberId.keys.toList()..sort();
    return [
      for (final id in ids)
        (
          memberId: id,
          amountMinor: amountsByMemberId[id]!,
          weightMicros: null,
        ),
    ];
  }
}

/// Proportional split by share count — "Ravi eats twice as much", 2:1:1.
final class SharesSplit extends SplitSpec {
  const SharesSplit(this.sharesByMemberId);

  /// Whole share counts per member, e.g. `{'a': 2, 'b': 1}`.
  final Map<String, int> sharesByMemberId;

  @override
  SplitKind get kind => SplitKind.shares;

  @override
  List<ResolvedShare> resolve(int totalMinor) {
    if (sharesByMemberId.isEmpty) {
      throw const SplitException('An expense needs at least one participant.');
    }
    for (final shares in sharesByMemberId.values) {
      if (shares < 0) {
        throw const SplitException('A share count cannot be negative.');
      }
    }
    if (sharesByMemberId.values.every((s) => s == 0)) {
      throw const SplitException('At least one person needs a share.');
    }

    final parties = [
      for (final entry in sharesByMemberId.entries)
        (memberId: entry.key, weightMicros: entry.value * weightScale),
    ];
    final allocation = allocateLargestRemainder(
      totalMinor: totalMinor,
      parties: parties,
    );
    return [
      for (final entry in allocation.entries)
        (
          memberId: entry.key,
          amountMinor: entry.value,
          weightMicros: sharesByMemberId[entry.key]! * weightScale,
        ),
    ];
  }
}

/// Proportional split by percentage. Percentages must total exactly 100.
///
/// Percentages are held as integer micros (33.333333% is `33333333`) to match
/// the `numeric(24,6)` weight column and to make "adds up to 100" an exact
/// integer comparison rather than a float tolerance.
final class PercentSplit extends SplitSpec {
  const PercentSplit(this.percentMicrosByMemberId);

  final Map<String, int> percentMicrosByMemberId;

  /// Total that percentages must reach: 100, scaled by 10^6.
  static const int fullPercentMicros = 100 * weightScale;

  @override
  SplitKind get kind => SplitKind.percent;

  @override
  List<ResolvedShare> resolve(int totalMinor) {
    if (percentMicrosByMemberId.isEmpty) {
      throw const SplitException('An expense needs at least one participant.');
    }
    for (final percent in percentMicrosByMemberId.values) {
      if (percent < 0) {
        throw const SplitException('A percentage cannot be negative.');
      }
    }

    final sum = percentMicrosByMemberId.values.fold(0, (a, b) => a + b);
    if (sum != fullPercentMicros) {
      final shown = (sum / weightScale).toStringAsFixed(2);
      throw SplitException('Percentages add up to $shown%, not 100%.');
    }

    final parties = [
      for (final entry in percentMicrosByMemberId.entries)
        (memberId: entry.key, weightMicros: entry.value),
    ];
    final allocation = allocateLargestRemainder(
      totalMinor: totalMinor,
      parties: parties,
    );
    return [
      for (final entry in allocation.entries)
        (
          memberId: entry.key,
          amountMinor: entry.value,
          weightMicros: percentMicrosByMemberId[entry.key]!,
        ),
    ];
  }
}

/// Validates the payer side of an entry.
///
/// Payers are always explicit amounts — there is no "split the paying" mode —
/// so this only checks the invariant the server will enforce anyway, but does
/// it before the row is written rather than after a round trip.
///
/// Returns the payers ordered by member id. Throws [SplitException] on
/// mismatch.
List<({String memberId, int amountMinor})> resolvePayers({
  required int totalMinor,
  required Map<String, int> amountsByMemberId,
}) {
  if (amountsByMemberId.isEmpty) {
    throw const SplitException('Someone has to have paid.');
  }
  for (final amount in amountsByMemberId.values) {
    if (amount <= 0) {
      throw const SplitException('A payment must be more than zero.');
    }
  }

  final sum = amountsByMemberId.values.fold(0, (a, b) => a + b);
  if (sum != totalMinor) {
    throw SplitException(
      'Payments add up to $sum, but the total is $totalMinor.',
    );
  }

  final ids = amountsByMemberId.keys.toList()..sort();
  return [
    for (final id in ids) (memberId: id, amountMinor: amountsByMemberId[id]!),
  ];
}

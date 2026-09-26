import '../models/kinds.dart';
import 'allocation.dart';

export '../models/kinds.dart' show SplitKind;

/// A share after resolution: what this member owes, plus the rule that produced
/// it.
typedef ResolvedShare = ({String memberId, int amountMinor, int? weightMicros});

/// Raised when a split cannot be resolved because the inputs are inconsistent.
class SplitException implements Exception {
  const SplitException(this.message);
  final String message;

  @override
  String toString() => 'SplitException: $message';
}

/// How an entry's total is divided among members.
sealed class SplitSpec {
  const SplitSpec();

  SplitKind get kind;

  /// Resolves this specification against [totalMinor].
  List<ResolvedShare> resolve(int totalMinor, {String? seed});
}

/// Split evenly. The overwhelming majority of real expenses.
final class EqualSplit extends SplitSpec {
  const EqualSplit(this.memberIds);

  final List<String> memberIds;

  @override
  SplitKind get kind => SplitKind.equal;

  @override
  List<ResolvedShare> resolve(int totalMinor, {String? seed}) {
    if (memberIds.isEmpty) {
      throw const SplitException('An expense needs at least one participant.');
    }
    if (memberIds.toSet().length != memberIds.length) {
      throw const SplitException('The same person is listed twice.');
    }

    final allocation = allocateLargestRemainder(
      totalMinor: totalMinor,
      seed: seed,
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
  List<ResolvedShare> resolve(int totalMinor, {String? seed}) {
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
        (memberId: id, amountMinor: amountsByMemberId[id]!, weightMicros: null),
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
  List<ResolvedShare> resolve(int totalMinor, {String? seed}) {
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
      seed: seed,
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
final class PercentSplit extends SplitSpec {
  const PercentSplit(this.percentMicrosByMemberId);

  final Map<String, int> percentMicrosByMemberId;

  /// Total that percentages must reach: 100, scaled by 10^6.
  static const int fullPercentMicros = 100 * weightScale;

  @override
  SplitKind get kind => SplitKind.percent;

  @override
  List<ResolvedShare> resolve(int totalMinor, {String? seed}) {
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
      seed: seed,
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

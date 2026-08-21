/// One participant in a weighted allocation.
///
/// [weightMicros] is the weight scaled by 10^6, matching the `numeric(24,6)`
/// precision of `entry_shares.weight` in Postgres. Keeping weights as integers
/// rather than doubles is deliberate: floating point makes "every device
/// produces identical paise" an aspiration rather than a guarantee.
typedef WeightedParty = ({String memberId, int weightMicros});

/// Scale factor between a weight and its integer micro representation.
const int weightScale = 1000000;

/// Splits [totalMinor] across [parties] in proportion to their weights, using
/// the largest-remainder method on integer minor units.
///
/// The result always sums to exactly [totalMinor] — that is the entire point,
/// and it is what the deferred `assert_entry_balanced` trigger checks
/// server-side. Each party first receives the floor of its exact share; the
/// leftover units (strictly fewer than there are parties) go one apiece to the
/// parties with the largest truncated remainders.
///
/// Ties on remainder are broken by ascending `memberId`, and the input order is
/// never consulted, so shuffling [parties] cannot change the outcome. Two
/// devices folding the same entry therefore agree to the paise.
///
/// Intermediate products are computed in [BigInt]. On the web a Dart `int` is a
/// JavaScript double and loses precision beyond 2^53; a plausible amount such
/// as ₹10,00,00,000 multiplied by a 10^6-scaled weight already exceeds that.
/// The cost is irrelevant for the handful of members in a group; silently wrong
/// arithmetic on one of the two shipping platforms is not.
///
/// Returns a map keyed by member id, iterating in ascending id order. Throws
/// [ArgumentError] if the inputs cannot produce a valid allocation.
Map<String, int> allocateLargestRemainder({
  required int totalMinor,
  required List<WeightedParty> parties,
}) {
  if (parties.isEmpty) {
    throw ArgumentError.value(parties, 'parties', 'must not be empty');
  }
  if (totalMinor < 0) {
    throw ArgumentError.value(totalMinor, 'totalMinor', 'must not be negative');
  }

  final seen = <String>{};
  for (final party in parties) {
    if (!seen.add(party.memberId)) {
      throw ArgumentError.value(
        parties,
        'parties',
        'duplicate member ${party.memberId}',
      );
    }
    if (party.weightMicros < 0) {
      throw ArgumentError.value(
        parties,
        'parties',
        'negative weight for member ${party.memberId}',
      );
    }
  }

  // Sort up front so both the floor pass and the remainder tiebreak see a
  // canonical order regardless of how the caller assembled the list.
  final sorted = [...parties]..sort((a, b) => a.memberId.compareTo(b.memberId));

  final totalWeight = sorted.fold(
    BigInt.zero,
    (sum, p) => sum + BigInt.from(p.weightMicros),
  );
  if (totalWeight == BigInt.zero) {
    throw ArgumentError.value(
      parties,
      'parties',
      'total weight is zero; nothing to allocate against',
    );
  }

  final total = BigInt.from(totalMinor);
  final base = <int>[];
  final remainders = <BigInt>[];
  var allocated = 0;

  for (final party in sorted) {
    final exact = total * BigInt.from(party.weightMicros);
    final floor = (exact ~/ totalWeight).toInt();
    base.add(floor);
    remainders.add(exact.remainder(totalWeight));
    allocated += floor;
  }

  // Strictly less than sorted.length, since every remainder is < totalWeight.
  final leftover = totalMinor - allocated;

  // Indices ordered by descending remainder, ties by ascending member id.
  // The comparator is total rather than leaning on `sorted` plus a stable sort:
  // Dart's List.sort is explicitly not guaranteed stable, so equal remainders
  // could otherwise land in an implementation-defined order and two devices
  // would disagree by one paisa on exactly the inputs — equal splits — that
  // produce ties most often.
  final order = List<int>.generate(sorted.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      if (byRemainder != 0) return byRemainder;
      return sorted[a].memberId.compareTo(sorted[b].memberId);
    });

  for (var i = 0; i < leftover; i++) {
    base[order[i]] += 1;
  }

  // A Dart map literal preserves insertion order, and `sorted` is by member
  // id, so the result iterates in ascending id order.
  final result = <String, int>{};
  for (var i = 0; i < sorted.length; i++) {
    result[sorted[i].memberId] = base[i];
  }
  return result;
}

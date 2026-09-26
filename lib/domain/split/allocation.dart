/// One participant in a weighted allocation.
typedef WeightedParty = ({String memberId, int weightMicros});

/// Scale factor between a weight and its integer micro representation.
const int weightScale = 1000000;

/// Splits [totalMinor] across [parties] in proportion to their weights, using
/// the largest-remainder method on integer minor units.
Map<String, int> allocateLargestRemainder({
  required int totalMinor,
  required List<WeightedParty> parties,
  String? seed,
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

  // Where the tiebreak starts walking. Zero without a seed, which preserves
  // the plain ascending-id order for callers that have no entry to key on.
  final offset = seed == null ? 0 : _hash(seed) % sorted.length;

  // Indices ordered by descending remainder, ties by rotated member order.
  int rotated(int index) => (index - offset + sorted.length) % sorted.length;

  final order = List<int>.generate(sorted.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      if (byRemainder != 0) return byRemainder;
      return rotated(a).compareTo(rotated(b));
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

/// FNV-1a, 32 bit, computed in [BigInt].
int _hash(String value) {
  final mask = BigInt.from(0xffffffff);
  final prime = BigInt.from(0x01000193);
  var hash = BigInt.from(0x811c9dc5);

  for (var i = 0; i < value.length; i++) {
    hash = (hash ^ BigInt.from(value.codeUnitAt(i)));
    hash = (hash * prime) & mask;
  }
  return hash.toInt();
}

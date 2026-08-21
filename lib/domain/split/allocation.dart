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
/// Ties on remainder are broken by rotating through the parties in ascending
/// `memberId` order, starting at a position derived from [seed]. The input
/// order is never consulted, so shuffling [parties] cannot change the outcome,
/// and two devices folding the same entry agree to the paise.
///
/// The rotation matters more than it looks. An equal split gives every party an
/// identical remainder, so the tiebreak alone decides who absorbs the extra
/// minor unit — and a fixed tiebreak means the same person absorbs it on every
/// equal split, forever. It is one paisa at a time, but it is systematic, and
/// "why is my share always a paisa more?" is a question with no good answer.
/// Seeding with the entry id moves it around while keeping the allocation a
/// pure function of the entry: no cursor, no randomness, and an edit to the
/// same entry reproduces the same split.
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
  // The comparator is total rather than leaning on `sorted` plus a stable sort:
  // Dart's List.sort is explicitly not guaranteed stable, so equal remainders
  // could otherwise land in an implementation-defined order and two devices
  // would disagree by one paisa on exactly the inputs — equal splits — that
  // produce ties most often.
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
///
/// The BigInt is not caution, it is required. Masking the product to 32 bits
/// afterwards looks sufficient and is not: the FNV prime is about 2^24, so
/// `hash * prime` reaches 2^56 before the mask, and on the web a Dart `int` is
/// a JavaScript double that is only exact to 2^53. The multiply loses low bits
/// before anything gets masked, and the two platforms then disagree.
///
/// That is not an abstract risk. This function was written with a plain
/// multiply first, and the VM and Chrome picked different members for the same
/// entry id — which on two real devices means an Android phone and the web app
/// splitting one expense differently and the sync flip-flopping between them.
/// The golden test pins specific seeds to specific members and runs on both.
///
/// Nothing here needs to resist an attacker, only to be reproducible on every
/// device that folds the entry.
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

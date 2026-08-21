import '../models/entry.dart';

/// Narrows what an analytics question is asked about.
class AnalyticsFilter {
  const AnalyticsFilter({
    required this.groupId,
    this.from,
    this.to,
    this.memberId,
    this.categoryId,
    this.currency,
    this.query = '',
  });

  final String groupId;
  final DateTime? from;
  final DateTime? to;

  /// Restrict to entries this member has a share in.
  final String? memberId;
  final String? categoryId;

  /// Analytics are always per currency. Mixing them would require inventing a
  /// rate, and a total that silently depends on one is worse than no total.
  final String? currency;

  /// Free text, matched against descriptions and notes.
  final String query;

  AnalyticsFilter copyWith({
    DateTime? from,
    DateTime? to,
    String? memberId,
    String? categoryId,
    String? currency,
    String? query,
    bool clearFrom = false,
    bool clearTo = false,
    bool clearMember = false,
    bool clearCategory = false,
  }) => AnalyticsFilter(
    groupId: groupId,
    from: clearFrom ? null : (from ?? this.from),
    to: clearTo ? null : (to ?? this.to),
    memberId: clearMember ? null : (memberId ?? this.memberId),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    currency: currency ?? this.currency,
    query: query ?? this.query,
  );

  bool get isNarrowed =>
      from != null ||
      to != null ||
      memberId != null ||
      categoryId != null ||
      query.trim().isNotEmpty;
}

/// One row of an aggregate.
class SpendBucket {
  const SpendBucket({
    required this.key,
    required this.label,
    required this.currency,
    required this.amountMinor,
    required this.entryCount,
  });

  /// Category id, member id, or a period like `2026-08`.
  final String key;
  final String label;
  final String currency;
  final int amountMinor;
  final int entryCount;
}

/// Local analytics.
///
/// Every one of these is SQL over data already on the device: no endpoint, no
/// per-query cost, no cache to invalidate, and it all works with no connection.
/// Searching your own expense history is not something worth charging for.
///
/// Settlements are excluded throughout. Paying a friend back is not spending,
/// and counting it would double every settled expense.
abstract interface class AnalyticsRepository {
  Future<List<Entry>> search(AnalyticsFilter filter);

  Future<List<SpendBucket>> spendByCategory(AnalyticsFilter filter);

  /// What each member personally consumed — the sum of their shares, not what
  /// they happened to pay.
  Future<List<SpendBucket>> spendByMember(AnalyticsFilter filter);

  /// Totals by calendar month.
  Future<List<SpendBucket>> spendByMonth(AnalyticsFilter filter);

  /// Currencies this group actually holds, most used first.
  Future<List<String>> currenciesUsed(String groupId);
}

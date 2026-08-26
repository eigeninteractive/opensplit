import 'package:drift/drift.dart';

import '../../domain/models/entry.dart';
import '../../domain/analytics/analytics_query.dart';
import '../local/database.dart';
import 'drift_entry_repository.dart';

/// Local analytics.
///
/// Every one of these is SQL over data already on the device: no endpoint, no
/// per-query cost, no cache to invalidate, and it all works with no connection.
/// Searching your own expense history is not something worth charging for.
///
/// All of it is watched rather than fetched. Every query here already declares
/// what it reads from, which is the expensive half of making it live, and the
/// alternative is a screen that answers as of the moment it was opened: a sync
/// landing behind an open Insights tab, or an expense added in the pane beside
/// it, would leave totals that disagree with the list they were computed from
/// and nothing on screen to say so.
///
/// Settlements are excluded throughout. Paying a friend back is not spending,
/// and counting it would double every settled expense.
final class DriftAnalyticsRepository {
  /// [_entries] hydrates the rows a search matches.
  ///
  /// Injected rather than constructed here, so there is one place that knows
  /// how an entry is assembled from its three tables and analytics is a caller
  /// of it rather than a second copy.
  DriftAnalyticsRepository(this._db, this._entries);

  final AppDatabase _db;
  final DriftEntryRepository _entries;

  /// Builds the shared WHERE clause and its variables.
  ///
  /// `kind = 'expense'` and `deleted_at IS NULL` are not optional: a settlement
  /// is a transfer, not spending, and counting one would inflate every figure
  /// on the screen.
  ({String sql, List<Variable<Object>> vars}) _where(
    AnalyticsFilter filter, {
    String alias = 'e',
  }) {
    final clauses = <String>[
      "$alias.group_id = ?",
      "$alias.kind = 'expense'",
      '$alias.deleted_at IS NULL',
    ];
    final vars = <Variable<Object>>[Variable<String>(filter.groupId)];

    if (filter.currency != null) {
      clauses.add('$alias.currency = ?');
      vars.add(Variable<String>(filter.currency!));
    }
    if (filter.categoryId != null) {
      clauses.add('$alias.category_id = ?');
      vars.add(Variable<String>(filter.categoryId!));
    }
    if (filter.from != null) {
      clauses.add('$alias.entry_date >= ?');
      vars.add(Variable<String>(_iso(filter.from!)));
    }
    if (filter.to != null) {
      clauses.add('$alias.entry_date <= ?');
      vars.add(Variable<String>(_iso(filter.to!)));
    }
    if (filter.memberId != null) {
      clauses.add(
        'EXISTS (SELECT 1 FROM entry_shares s '
        'WHERE s.entry_id = $alias.id AND s.member_id = ?)',
      );
      vars.add(Variable<String>(filter.memberId!));
    }

    final match = _ftsMatch(filter.query);
    if (match != null) {
      clauses.add(
        '$alias.rowid IN '
        '(SELECT rowid FROM entries_fts WHERE entries_fts MATCH ?)',
      );
      vars.add(Variable<String>(match));
    }

    return (sql: clauses.join(' AND '), vars: vars);
  }

  /// Turns user input into an FTS5 query.
  ///
  /// Each term is quoted so that punctuation cannot be read as FTS5 operators —
  /// an apostrophe or a stray `*` would otherwise be a syntax error thrown at
  /// someone who was only typing a restaurant name. A trailing `*` makes it
  /// match as you type.
  static String? _ftsMatch(String query) {
    final terms = query
        .replaceAll('"', ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return null;
    return terms.map((t) => '"$t"*').join(' ');
  }

  static String _iso(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).toIso8601String();

  Stream<List<Entry>> search(AnalyticsFilter filter) {
    final where = _where(filter);
    return _db
        .customSelect(
          'SELECT e.id FROM entries e WHERE ${where.sql} '
          'ORDER BY e.entry_date DESC, e.created_at DESC',
          variables: where.vars,
          readsFrom: {_db.entries, _db.entryShares},
        )
        .watch()
        // Hydrating only what matched, rather than the group's whole journal
        // and then discarding most of it. A search for one restaurant used to
        // load every expense in the group on every keystroke.
        .asyncMap(
          (rows) => _entries.getByIds([
            for (final row in rows) row.read<String>('id'),
          ]),
        );
  }

  Stream<List<SpendBucket>> _aggregate({
    required AnalyticsFilter filter,
    required String keyExpression,
    required String labelExpression,
    required String from,
    required Set<ResultSetImplementation<Object, Object>> readsFrom,
    required String amountExpression,
    String? extraJoin,
  }) {
    final where = _where(filter);
    return _db
        .customSelect(
          'SELECT $keyExpression AS bucket_key, '
          '$labelExpression AS bucket_label, '
          'e.currency AS currency, '
          'SUM($amountExpression) AS total, '
          'COUNT(DISTINCT e.id) AS entries '
          'FROM $from ${extraJoin ?? ''} '
          'WHERE ${where.sql} '
          'GROUP BY bucket_key, e.currency '
          'ORDER BY total DESC',
          variables: where.vars,
          readsFrom: readsFrom,
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              SpendBucket(
                key: row.read<String?>('bucket_key') ?? '',
                label: row.read<String?>('bucket_label') ?? 'Uncategorised',
                currency: row.read<String>('currency'),
                amountMinor: row.read<int>('total'),
                entryCount: row.read<int>('entries'),
              ),
          ],
        );
  }

  Stream<List<SpendBucket>> spendByCategory(AnalyticsFilter filter) =>
      _aggregate(
        filter: filter,
        keyExpression: "COALESCE(e.category_id, '')",
        labelExpression: "COALESCE(c.name, 'Uncategorised')",
        from: 'entries e',
        extraJoin: 'LEFT JOIN categories c ON c.id = e.category_id',
        amountExpression: 'e.amount_minor',
        readsFrom: {_db.entries, _db.categories, _db.entryShares},
      );

  /// What each member personally consumed — the sum of their shares, not what
  /// they happened to pay.
  Stream<List<SpendBucket>> spendByMember(AnalyticsFilter filter) => _aggregate(
    filter: filter,
    keyExpression: 's.member_id',
    labelExpression: "COALESCE(m.display_name, '—')",
    from: 'entries e',
    extraJoin:
        'JOIN entry_shares s ON s.entry_id = e.id '
        'LEFT JOIN members m ON m.id = s.member_id',
    // A member's own spend is what they owed, not what they paid: one person
    // putting the whole bill on their card did not consume all of it.
    amountExpression: 's.amount_minor',
    readsFrom: {_db.entries, _db.entryShares, _db.members},
  );

  /// Totals by calendar month.
  Stream<List<SpendBucket>> spendByMonth(AnalyticsFilter filter) {
    return _aggregate(
      filter: filter,
      keyExpression: 'substr(e.entry_date, 1, 7)',
      labelExpression: 'substr(e.entry_date, 1, 7)',
      from: 'entries e',
      amountExpression: 'e.amount_minor',
      readsFrom: {_db.entries, _db.entryShares},
      // Chronological rather than largest-first: a trend read out of order is
      // not a trend.
    ).map((buckets) => buckets..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// Currencies this group actually holds, most used first.
  Stream<List<String>> currenciesUsed(String groupId) {
    return _db
        .customSelect(
          "SELECT currency, COUNT(*) AS n FROM entries "
          "WHERE group_id = ? AND deleted_at IS NULL "
          'GROUP BY currency ORDER BY n DESC',
          variables: [Variable<String>(groupId)],
          readsFrom: {_db.entries},
        )
        .watch()
        .map((rows) => [for (final row in rows) row.read<String>('currency')]);
  }
}

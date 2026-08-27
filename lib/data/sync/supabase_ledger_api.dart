import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/entry.dart';
import '../../domain/models/entry_snapshot.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';
import 'change_feed.dart';
import 'remote_ledger_api.dart';
import 'sync_cursor.dart';
import 'wire.dart';

/// The Supabase implementation of the remote ledger contract.
///
/// Everything above `data/` speaks [RemoteLedgerApi]. Swapping this for a
/// self-hosted Postgres, or for a different provider entirely, is a matter of
/// writing another class of this size — which is what makes the self-hosting
/// promise a weekend port rather than a rewrite, and what provides the exit if
/// the hosted pricing moves.
final class SupabaseLedgerApi implements RemoteLedgerApi {
  SupabaseLedgerApi(this._client);

  final SupabaseClient _client;

  /// Rows per request on the one sweep that still pages itself.
  ///
  /// Comfortably under PostgREST's `max_rows`, which is 1000 by default and is
  /// a silent ceiling: a larger request is not an error, it is a short answer,
  /// with nothing in the response to say it was cut. Every change feed now
  /// takes its page size from the caller and reports `hasMore`, so the engine
  /// does the paging; rates are the exception, being a high-water mark rather
  /// than a cursor.
  static const int _pageSize = 500;

  /// One keyset page of a change feed.
  ///
  /// Every feed in the schema is shaped for this: `(group_id, updated_at, id)`
  /// on entries and members, `(updated_at, id)` on groups and profiles,
  /// `(group_id, created_at, id)` on activity. One implementation, so a feed
  /// cannot quietly acquire its own paging semantics.
  ///
  /// Keyset rather than `range()`, and that is a correctness matter rather than
  /// a performance one. Offset paging over `<time> > since` re-sorts under its
  /// own feet: bump a profile mid-sweep and it moves to the end of the
  /// ordering, shifting every row after its old position back by one, so the
  /// row that lands on the next offset boundary is never read — and the cursor
  /// advances past it anyway. That skip was permanent.
  Future<ChangePage<T>> _keyset<T>({
    required String table,
    required SyncCursor? since,
    required int limit,
    required T Function(Map<String, dynamic>) parse,
    String columns = '*',
    String timeColumn = 'updated_at',
    Map<String, String> equals = const {},
  }) async {
    try {
      var query = _client.from(table).select(columns);
      for (final filter in equals.entries) {
        query = query.eq(filter.key, filter.value);
      }

      if (since != null) {
        // Row-value comparison, spelled out because PostgREST has no syntax for
        // `(updated_at, id) > (?, ?)`. Anything strictly after the pair.
        //
        // Both values are double-quoted. Inside an `or=(...)` group PostgREST
        // treats `.` `,` `:` `(` `)` as structural, and an ISO-8601 timestamp
        // is full of them — unquoted, the filter parses into something else
        // and quietly matches nothing, so paging stops after the first page
        // and the rest of the feed never arrives.
        final at = '"${since.at.toUtc().toIso8601String()}"';
        query = query.or(
          '$timeColumn.gt.$at,and($timeColumn.eq.$at,id.gt."${since.id}")',
        );
      }

      // `ascending` must be stated: supabase_dart's order() defaults to
      // DESCENDING, which silently reverses the feed. The cursor then walks
      // backwards from the newest row, re-reading what it has already applied
      // and never reaching the oldest — a group would sync its two most recent
      // expenses and then quietly stop.
      final rows = await query
          .order(timeColumn, ascending: true)
          .order('id', ascending: true)
          // One extra row purely to answer hasMore without a count.
          .limit(limit + 1);

      final page = rows.take(limit).toList();

      return ChangePage(
        rows: [for (final row in page) parse(row)],
        // Read off the wire rather than the parsed model: the timestamp is
        // `not null` in the schema and nullable in the domain models, and a
        // cursor is the one place that must not fall back to a guess.
        cursor: page.isEmpty
            ? null
            : SyncCursor(
                DateTime.parse(page.last[timeColumn] as String),
                page.last['id'] as String,
              ),
        hasMore: rows.length > limit,
      );
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  /// Embedded selects, aliased so the payload matches the wire codec.
  static const String _entryColumns =
      '*, '
      'payers:entry_payers(member_id,amount_minor), '
      'shares:entry_shares(member_id,amount_minor,weight)';

  @override
  Future<Entry> upsertEntry(Entry entry, {DateTime? baseUpdatedAt}) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'upsert_entry',
        params: {
          'p_id': entry.id,
          'p_group_id': entry.groupId,
          'p_currency': entry.currency,
          'p_amount': entry.amountMinor,
          'p_payers': [
            for (final payer in entry.payers)
              {'member_id': payer.memberId, 'amount_minor': payer.amountMinor},
          ],
          'p_shares': [
            for (final share in entry.shares)
              {
                'member_id': share.memberId,
                'amount_minor': share.amountMinor,
                'weight': share.weightMicros == null
                    ? null
                    : share.weightMicros! / 1000000,
              },
          ],
          'p_description': entry.description,
          'p_kind': entry.kind.name,
          'p_split_kind': entry.splitKind.name,
          'p_entry_date': entry.entryDate.toIso8601String().split('T').first,
          'p_category_id': entry.categoryId,
          'p_notes': entry.notes,
          'p_fx_rate': entry.fxRate,
          'p_fx_source': entry.fxSource,
          'p_client_key': entry.clientKey,
          'p_base_updated_at': baseUpdatedAt?.toUtc().toIso8601String(),
        },
      );

      // The RPC returns the entries row alone. Payers and shares are exactly
      // what was just written, so they are carried over rather than re-fetched.
      return entryFromJson(
        row,
      ).copyWith(payers: entry.payers, shares: entry.shares);
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<Entry> deleteEntry(
    String entryId, {
    required DateTime baseUpdatedAt,
  }) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'delete_entry',
        params: {
          'p_entry_id': entryId,
          'p_base_updated_at': baseUpdatedAt.toUtc().toIso8601String(),
        },
      );
      return entryFromJson(row);
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<ChangePage<Entry>> pullEntries({
    required String groupId,
    SyncCursor? since,
    required int limit,
  }) =>
      // Soft-deleted rows are deliberately included: a deletion is a change,
      // and filtering it out would strand the row on every device that has it.
      _keyset(
        table: 'entries',
        columns: _entryColumns,
        equals: {'group_id': groupId},
        since: since,
        limit: limit,
        parse: entryFromJson,
      );

  @override
  Future<List<String>> pullMyGroupIds() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];

    try {
      // members_read admits your own rows — is_group_member() is true of them
      // by definition — so this needs no RPC and no extra policy. A row you
      // have left fails that same predicate, which is why `left_at` is filtered
      // here as documentation rather than as the thing doing the work.
      final rows = await _client
          .from('members')
          .select('group_id')
          .eq('profile_id', uid)
          .isFilter('left_at', null);

      return [for (final row in rows) row['group_id'] as String];
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<ChangePage<Group>> pullGroup({
    required String groupId,
    SyncCursor? since,
    required int limit,
  }) => _keyset(
    table: 'groups',
    equals: {'id': groupId},
    since: since,
    limit: limit,
    parse: groupFromJson,
  );

  @override
  Future<ChangePage<Member>> pullMembers({
    required String groupId,
    SyncCursor? since,
    required int limit,
  }) => _keyset(
    table: 'members',
    equals: {'group_id': groupId},
    since: since,
    limit: limit,
    parse: memberFromJson,
  );

  @override
  Future<Group> pushGroup(Group group) async {
    try {
      // select().single() so the server's updated_at comes straight back. Note
      // this needs a SELECT policy as well as an INSERT one: an upsert that
      // returns rows is refused without it, and the error names the INSERT
      // policy, which is nothing to do with it.
      final row = await _client
          .from('groups')
          .upsert(groupToJson(group))
          .select()
          .single();
      return groupFromJson(row);
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<Member> pushMember(Member member) async {
    try {
      final row = await _client
          .from('members')
          .upsert(memberToJson(member))
          .select()
          .single();
      return memberFromJson(row);
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<ChangePage<Profile>> pullProfiles({
    SyncCursor? since,
    required int limit,
  }) =>
      // No group filter and none needed: profiles_read already limits this to
      // your own row plus anybody sharing a group with you, so asking for
      // "everything I can see" returns exactly the set that matters.
      _keyset(
        table: 'profiles',
        since: since,
        limit: limit,
        parse: profileFromJson,
      );

  @override
  Future<Profile> pushProfile(Profile profile) async {
    try {
      final row = await _client
          .from('profiles')
          .upsert(profileToJson(profile))
          .select()
          .single();
      return profileFromJson(row);
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<ChangePage<EntrySnapshot>> pullEntrySnapshots({
    required String groupId,
    SyncCursor? since,
    required int limit,
  }) => _keyset(
    table: 'entry_events',
    timeColumn: 'created_at',
    equals: {'group_id': groupId},
    since: since,
    limit: limit,
    parse: entrySnapshotFromJson,
  );

  @override
  Future<List<RemoteFxRate>> pullFxRates({required String since}) async {
    final rates = <RemoteFxRate>[];

    try {
      // Paged, because this is the one pull with no cursor on it. A device with
      // no rates asks for a 400-day window, which at sixteen currencies is
      // thousands of rows — and an unpaged request would come back truncated at
      // max_rows with no indication that it had been. The high-water mark then
      // advances by only as much as arrived, so the table filled in a few
      // hundred rows per sync and a fresh install spent days catching up to
      // today's rate.
      for (var offset = 0; ; offset += _pageSize) {
        final rows = await _client
            .from('fx_rates')
            .select('as_of, currency, rate, source')
            .gte('as_of', since)
            .order('as_of', ascending: true)
            .order('currency', ascending: true)
            .range(offset, offset + _pageSize - 1);

        rates.addAll([
          for (final row in rows)
            RemoteFxRate(
              asOf: row['as_of'] as String,
              currency: (row['currency'] as String).trim(),
              // numeric arrives as a string from PostgREST, since a double
              // cannot represent every numeric exactly.
              rate: double.parse('${row['rate']}'),
              source: row['source'] as String,
            ),
        ]);

        if (rows.length < _pageSize) break;
      }
    } on PostgrestException catch (e) {
      throw _translate(e);
    }

    return rates;
  }

  @override
  Future<void> requestFxBackfill({
    required DateTime asOf,
    required String currency,
  }) async {
    try {
      await _client.rpc(
        'request_fx_backfill',
        params: {'p_as_of': _isoDay(asOf), 'p_currency': currency},
      );
    } catch (_) {
      // The server decides whether this is worth doing at all — it refuses
      // dates it already covers, repeats within the hour, and anything past a
      // global ceiling. A failure here costs an estimate, never a balance.
    }
  }

  static String _isoDay(DateTime date) {
    final utc = date.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  /// Decides whether a failure is worth retrying.
  ///
  /// A violated invariant or a denied permission will be refused identically
  /// forever; retrying only wedges everything queued behind it. Anything else —
  /// a dropped connection, a timeout, a restart — is transient and deserves the
  /// backoff.
  RemoteRejected _translate(PostgrestException e) {
    const permanentCodes = {
      '23514', // check_violation — the balance invariant
      '23503', // foreign_key_violation
      '23505', // unique_violation
      '42501', // insufficient_privilege — RLS, or a member guard, refused
      '2BP01', // dependent_objects_still_exist — a group with expenses in it
      'P0002', // no_data_found
    };

    // serialization_failure, raised by upsert_entry when an edit was composed
    // against a version somebody has since changed. Standard, and semantically
    // exact -- but it must be named here, because the default for an unlisted
    // code is "transient", and retrying this one resends the same stale base
    // forever.
    if (e.code == '40001') {
      return RemoteRejected(e.message, kind: RejectionKind.stale);
    }

    return RemoteRejected(
      e.message,
      kind: permanentCodes.contains(e.code)
          ? RejectionKind.permanent
          : RejectionKind.transient,
    );
  }
}

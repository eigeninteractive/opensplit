import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/entry.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import 'remote_ledger_api.dart';
import 'sync_cursor.dart';
import 'wire.dart';

/// The one file in this codebase that knows Supabase exists.
///
/// Everything above `data/` speaks [RemoteLedgerApi]. Swapping this for a
/// self-hosted Postgres, or for a different provider entirely, is a matter of
/// writing another class of this size — which is what makes the self-hosting
/// promise a weekend port rather than a rewrite, and what provides the exit if
/// the hosted pricing moves.
final class SupabaseLedgerApi implements RemoteLedgerApi {
  SupabaseLedgerApi(this._client);

  final SupabaseClient _client;

  /// Embedded selects, aliased so the payload matches the wire codec.
  static const String _entryColumns =
      '*, '
      'payers:entry_payers(member_id,amount_minor), '
      'shares:entry_shares(member_id,amount_minor,weight)';

  @override
  Future<Entry> upsertEntry(Entry entry) async {
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
          'p_algo_version': entry.algoVersion,
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
  Future<Entry> deleteEntry(String entryId) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'delete_entry',
        params: {'p_entry_id': entryId},
      );
      return entryFromJson(row);
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<EntryDelta> pullEntries({
    required String groupId,
    SyncCursor? cursor,
    int limit = 200,
  }) async {
    try {
      var query = _client
          .from('entries')
          .select(_entryColumns)
          .eq('group_id', groupId);

      if (cursor != null) {
        // Row-value comparison, spelled out because PostgREST has no syntax for
        // `(updated_at, id) > (?, ?)`. Anything strictly after the pair.
        //
        // Both values are double-quoted. Inside an `or=(...)` group PostgREST
        // treats `.` `,` `:` `(` `)` as structural, and an ISO-8601 timestamp
        // is full of them — unquoted, the filter parses into something else
        // and quietly matches nothing, so paging stops after the first page
        // and the rest of the group never arrives.
        final at = '"${cursor.updatedAt.toUtc().toIso8601String()}"';
        query = query.or(
          'updated_at.gt.$at,and(updated_at.eq.$at,id.gt."${cursor.id}")',
        );
      }

      // Soft-deleted rows are deliberately included: a deletion is a delta, and
      // filtering it out would strand the row on every device that had it.
      // `ascending` must be stated: supabase_dart's order() defaults to
      // DESCENDING, which silently reverses the feed. The cursor then walks
      // backwards from the newest row, re-reading what it has already applied
      // and never reaching the oldest — a group would sync its two most recent
      // expenses and then quietly stop.
      final rows = await query
          .order('updated_at', ascending: true)
          .order('id', ascending: true)
          .limit(limit + 1);

      final parsed = [for (final row in rows.take(limit)) entryFromJson(row)];

      return EntryDelta(
        entries: parsed,
        nextCursor: parsed.isEmpty
            ? cursor
            : SyncCursor(parsed.last.updatedAt, parsed.last.id),
        // One extra row was requested purely to answer this without a count.
        hasMore: rows.length > limit,
      );
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<Group?> pullGroup(String groupId) async {
    final row = await _client
        .from('groups')
        .select()
        .eq('id', groupId)
        .maybeSingle();
    return row == null ? null : groupFromJson(row);
  }

  @override
  Future<List<Member>> pullMembers(String groupId) async {
    final rows = await _client.from('members').select().eq('group_id', groupId);
    return [for (final row in rows) memberFromJson(row)];
  }

  @override
  Future<void> pushGroup(Group group) async {
    try {
      await _client.from('groups').upsert(groupToJson(group));
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
  }

  @override
  Future<void> pushMember(Member member) async {
    try {
      await _client.from('members').upsert(memberToJson(member));
    } on PostgrestException catch (e) {
      throw _translate(e);
    }
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
      '42501', // insufficient_privilege — RLS refused
      'P0002', // no_data_found
    };
    return RemoteRejected(
      e.message,
      permanent: permanentCodes.contains(e.code),
    );
  }
}

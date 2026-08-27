import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/entry.dart';
import '../../domain/models/entry_snapshot.dart';
import '../../domain/models/group.dart';
import '../../domain/models/member.dart';
import '../../domain/models/profile.dart';
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

  /// Rows per request on every unbounded sweep.
  ///
  /// Comfortably under PostgREST's `max_rows`, which is 1000 by default and is
  /// a silent ceiling: a larger request is not an error, it is a short answer,
  /// with nothing in the response to say it was cut. Anything here that reads
  /// "everything since a cursor" has to page, because the alternative is a
  /// cursor that advances by only as much as arrived and a device that takes
  /// days to catch up — which is exactly what the rate table did.
  static const int _pageSize = 500;

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
  Future<List<Profile>> pullProfiles({DateTime? since}) async {
    // No group filter and none needed: profiles_read already limits this to
    // your own row plus anybody sharing a group with you, so asking for
    // "everything I can see" returns exactly the set that matters. Doing it
    // per group would fetch the same person once per group they are in.
    final profiles = <Profile>[];

    // Paged by offset rather than by advancing the cursor, and ordered by
    // (updated_at, id) so the offsets mean something. Advancing the cursor
    // between pages would need the same row-value comparison pullEntries
    // spells out, because two profiles genuinely can share an updated_at —
    // redeem_invite writes a profile and a member in one transaction.
    for (var offset = 0; ; offset += _pageSize) {
      var query = _client.from('profiles').select();
      // UTC and ISO, matching how the entries cursor is written. A local-zone
      // string here would silently shift the boundary by the offset and skip
      // every change made inside it.
      if (since != null) {
        query = query.gt('updated_at', since.toUtc().toIso8601String());
      }

      final rows = await query
          .order('updated_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + _pageSize - 1);

      profiles.addAll([for (final row in rows) profileFromJson(row)]);
      if (rows.length < _pageSize) break;
    }

    return profiles;
  }

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
  Future<List<EntrySnapshot>> pullEntrySnapshots({
    required String groupId,
    DateTime? since,
  }) async {
    final snapshots = <EntrySnapshot>[];

    // Paged, and it matters most here: a device seeing an active group for the
    // first time asks for its entire history at once. Truncated at max_rows,
    // the high-water mark would advance only as far as the page reached and the
    // feed would fill in a thousand rows per sync.
    for (var offset = 0; ; offset += _pageSize) {
      var query = _client.from('entry_events').select().eq('group_id', groupId);
      if (since != null) {
        query = query.gt('created_at', since.toUtc().toIso8601String());
      }

      final rows = await query
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + _pageSize - 1);

      snapshots.addAll([for (final row in rows) entrySnapshotFromJson(row)]);
      if (rows.length < _pageSize) break;
    }

    return snapshots;
  }

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
    return RemoteRejected(
      e.message,
      permanent: permanentCodes.contains(e.code),
    );
  }
}

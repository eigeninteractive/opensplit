import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/member.dart';
import '../../domain/repositories/invite_api.dart';
import 'wire.dart';

final class SupabaseInviteApi implements InviteApi {
  SupabaseInviteApi(this._client);

  final SupabaseClient _client;

  @override
  Future<InviteLink> create(String memberId) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'create_invite',
        params: {'p_member_id': memberId},
      );
      return InviteLink(
        token: row['token'] as String,
        groupId: row['group_id'] as String,
        memberId: row['member_id'] as String,
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    } on PostgrestException catch (e) {
      throw InviteRejected(e.message);
    }
  }

  @override
  Future<Member> redeem(String token) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'redeem_invite',
        params: {'p_token': token},
      );
      return memberFromJson(row);
    } on PostgrestException catch (e) {
      // The RPC's messages are already written to be read by a person —
      // "This invite link has already been used" — so they pass straight
      // through rather than being replaced by something vaguer.
      throw InviteRejected(e.message);
    }
  }
}

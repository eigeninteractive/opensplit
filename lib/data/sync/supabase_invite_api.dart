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
  Future<InvitePreview?> peek(String token) async {
    // A set-returning function, so PostgREST hands back an array rather than
    // the single object create_invite returns.
    final rows = await _client.rpc<List<dynamic>>(
      'peek_invite',
      params: {'p_token': token},
    );
    if (rows.isEmpty) return null;

    final row = rows.first as Map<String, dynamic>;
    return InvitePreview(
      groupId: row['group_id'] as String,
      groupName: row['group_name'] as String,
      memberName: row['member_name'] as String,
      inviterName: row['inviter_name'] as String,
      memberCount: row['member_count'] as int,
      isRedeemed: row['is_redeemed'] as bool,
      isExpired: row['is_expired'] as bool,
      isMember: row['is_member'] as bool,
    );
  }

  @override
  Future<LinkTarget?> peekLink(String token) async {
    // The named invite first, because it is the older shape and the one a link
    // sitting in somebody's chat history is most likely to be. Both are keyed
    // by a uuid in separate tables, so a token can only ever be one of them.
    final invite = await peek(token);
    if (invite != null) return MemberInviteTarget(invite);

    final rows = await _client.rpc<List<dynamic>>(
      'peek_group_link',
      params: {'p_token': token},
    );
    if (rows.isEmpty) return null;

    final row = rows.first as Map<String, dynamic>;
    return GroupLinkTarget(
      GroupLinkPreview(
        groupId: row['group_id'] as String,
        groupName: row['group_name'] as String,
        inviterName: row['inviter_name'] as String? ?? 'Someone',
        memberCount: row['member_count'] as int,
        isExpired: row['is_expired'] as bool,
        isRevoked: row['is_revoked'] as bool,
        isMember: row['is_member'] as bool,
      ),
    );
  }

  @override
  Future<GroupLink> createGroupLink(String groupId) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'create_group_link',
        params: {'p_group_id': groupId},
      );
      return _linkFrom(row);
    } on PostgrestException catch (e) {
      throw InviteRejected(e.message);
    }
  }

  @override
  Future<void> revokeGroupLink(String groupId) async {
    try {
      await _client.rpc<void>(
        'revoke_group_link',
        params: {'p_group_id': groupId},
      );
    } on PostgrestException catch (e) {
      throw InviteRejected(e.message);
    }
  }

  @override
  Future<GroupLink?> currentGroupLink(String groupId) async {
    // A plain select rather than an RPC: members hold SELECT on group_links
    // under a policy, and there is no decision to make here that the policy is
    // not already making.
    final rows = await _client
        .from('group_links')
        .select()
        .eq('group_id', groupId)
        .isFilter('revoked_at', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .limit(1);

    if (rows.isEmpty) return null;
    return _linkFrom(rows.first);
  }

  @override
  Future<List<LinkPlaceholder>> placeholdersFor(String token) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_link_placeholders',
      params: {'p_token': token},
    );
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        LinkPlaceholder(
          memberId: row['member_id'] as String,
          displayName: row['display_name'] as String,
        ),
    ];
  }

  @override
  Future<Member> joinWithLink(String token, {String? memberId}) async {
    try {
      final row = await _client.rpc<Map<String, dynamic>>(
        'join_with_link',
        params: {'p_token': token, 'p_member_id': memberId},
      );
      return memberFromJson(row);
    } on PostgrestException catch (e) {
      // The RPC's messages are written to be read by a person, so they pass
      // straight through rather than being replaced by something vaguer.
      throw InviteRejected(e.message);
    }
  }

  GroupLink _linkFrom(Map<String, dynamic> row) => GroupLink(
    token: row['token'] as String,
    groupId: row['group_id'] as String,
    expiresAt: DateTime.parse(row['expires_at'] as String),
  );

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

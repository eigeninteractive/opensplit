import 'package:dio/dio.dart';
import 'package:opensplit_api/opensplit_api.dart' as api;

import '../../domain/models/member.dart';
import '../../domain/repositories/invite_api.dart';

/// Links, over the generated client.
///
/// Thin like its ledger counterpart: every rule about who may mint a link,
/// whether a token is still good and what claiming a place does lives in the
/// group's Durable Object. What is here is translation, plus the two places
/// where the wire's shape and the app's differ on purpose.
///
/// ## One preview, two kinds
///
/// The server answers `GET /links/{token}` with one flat shape carrying a
/// `kind`, because the person holding a URL cannot know which kind it is and
/// should not have to — they tapped a link. The app wants the opposite: a
/// sealed [LinkTarget] whose two cases carry only the fields that apply, so a
/// screen cannot read `memberName` off an open link. Widening on `kind` is
/// what this file does about that, once.
///
/// ## Refusals are for reading
///
/// [InviteRejected] carries the server's own sentence rather than a code. These
/// messages are written for the person holding the link — "this link has been
/// turned off" — and the screen shows them verbatim, which is why nothing here
/// re-words them.
class CloudflareInviteApi implements InviteApi {
  CloudflareInviteApi(this._client);

  final api.OpensplitApi _client;

  api.InvitesApi get _invites => _client.getInvitesApi();

  @override
  Future<InviteLink> create({
    required String groupId,
    required String memberId,
  }) => _guard(() async {
    final invite = _required(
      await _invites.createInvite(groupId: groupId, memberId: memberId),
    );

    // The group comes from the caller rather than the response. A member id is
    // only meaningful inside one group now that members are group-scoped, so
    // whoever asked for this link already had to hold both.
    return InviteLink(
      token: invite.token,
      groupId: groupId,
      memberId: invite.memberId,
      expiresAt: invite.expiresAt,
    );
  });

  @override
  Future<InvitePreview?> peek(String token) async =>
      switch (await peekLink(token)) {
        MemberInviteTarget(:final preview) => preview,
        // An open link is a real link, and this is not the method that reads
        // one. Null rather than a throw: the caller asked whether this token
        // is an invite, and it is not.
        _ => null,
      };

  @override
  Future<LinkTarget?> peekLink(String token) => _guard(() async {
    final api.LinkPreview preview;
    try {
      preview = _required(await _invites.peekLink(token: token));
    } on DioException catch (error) {
      // A token that names nothing, and a token that names a group which has
      // since been collected. Both are dead links and the screen says so; only
      // a real failure is worth surfacing as one.
      if (error.response?.statusCode case 404 || 410) return null;
      rethrow;
    }

    if (preview.kind == api.LinkPreviewKindEnum.invite) {
      final memberName = preview.memberName;

      // An invite hands over one named place, so a preview with no name on it
      // is not an invite this app can show. Unreachable in practice — the
      // token and the member row are written in one transaction — and reported
      // as a dead link rather than rendered as a blank.
      if (memberName == null) return null;

      return MemberInviteTarget(
        InvitePreview(
          groupId: preview.groupId,
          groupName: preview.groupName,
          memberName: memberName,
          inviterName: _inviter(preview.inviterName),
          memberCount: preview.memberCount,
          isRedeemed: preview.isRedeemed,
          isExpired: preview.isExpired,
          isMember: preview.isMember,
        ),
      );
    }

    return GroupLinkTarget(
      GroupLinkPreview(
        groupId: preview.groupId,
        groupName: preview.groupName,
        inviterName: _inviter(preview.inviterName),
        memberCount: preview.memberCount,
        isExpired: preview.isExpired,
        isRevoked: preview.isRevoked,
        isMember: preview.isMember,
      ),
    );
  });

  @override
  // A named invite names the place; there is nothing to choose and no name to
  // supply, so the server falls back to the one already on the account.
  Future<Member> redeem(String token) => _join(token, api.JoinRequest());

  @override
  Future<Member> joinWithLink(
    String token, {
    String? memberId,
    String? displayName,
  }) => _join(
    token,
    // Never both. Claiming a place keeps the name the group already knows, and
    // sending one alongside a `memberId` would suggest otherwise to anybody
    // reading the request.
    api.JoinRequest(
      memberId: memberId,
      displayName: memberId == null ? displayName : null,
    ),
  );

  @override
  Future<GroupLink> createGroupLink(String groupId) => _guard(() async {
    final minted = _required(await _invites.createGroupLink(groupId: groupId));
    return GroupLink(
      token: minted.token,
      groupId: groupId,
      expiresAt: minted.expiresAt,
    );
  });

  @override
  Future<void> revokeGroupLink(String groupId) =>
      _guard(() async => _invites.revokeGroupLink(groupId: groupId));

  @override
  Future<GroupLink?> currentGroupLink(String groupId) => _guard(() async {
    final live = _required(await _invites.getGroupLink(groupId: groupId)).link;
    if (live == null) return null;

    return GroupLink(
      token: live.token,
      groupId: groupId,
      expiresAt: live.expiresAt,
    );
  });

  @override
  Future<List<LinkPlaceholder>> placeholdersFor(String token) =>
      _guard(() async {
        final page = _required(await _invites.linkPlaceholders(token: token));
        return [
          for (final place in page.placeholders)
            LinkPlaceholder(
              memberId: place.memberId,
              displayName: place.displayName,
            ),
        ];
      });

  // ------------------------------------------------------------- translation

  Future<Member> _join(String token, api.JoinRequest request) =>
      _guard(() async {
        final joined = _required(
          await _invites.joinWithLink(token: token, joinRequest: request),
        );

        // The one response that names its group, and it has to: the caller
        // held a token, and the next thing the screen does is open the group.
        final member = joined.member;
        return Member(
          id: member.id,
          groupId: joined.groupId,
          profileId: member.profileId,
          displayName: member.displayName,
          joinedAt: member.joinedAt,
          leftAt: member.leftAt,
          upiVpa: member.upiVpa,
          seq: member.seq,
        );
      });

  /// Who sent this, in a sentence.
  ///
  /// The server reports null when the member who minted the link cannot be
  /// resolved, which a foreign key makes unreachable while the link exists —
  /// collecting a group deletes its links along with its members. The fallback
  /// is here so that if it ever does happen the screen reads "Someone invited
  /// you to Goa trip" rather than printing the word null, and nothing stores
  /// it: this is a rendering, not a name.
  static String _inviter(String? name) => name ?? 'Someone';

  static T _required<T>(Response<T> response) {
    final body = response.data;
    if (body == null) {
      throw const InviteRejected('The server answered with no body.');
    }
    return body;
  }

  /// Turns a refusal into the one the screens already catch.
  ///
  /// The server's own sentence, kept verbatim. These are written for the person
  /// holding the link — "someone has already claimed that place", "this link
  /// has been turned off" — and re-wording them here would replace the one
  /// thing the server knows and the screen does not.
  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      final body = error.response?.data;
      final envelope = body is Map ? body['error'] : null;
      final message = envelope is Map ? envelope['message'] as String? : null;

      throw InviteRejected(
        message ??
            (error.response == null
                ? 'Could not reach the server.'
                : 'The server refused that (${error.response?.statusCode}).'),
      );
    }
  }
}

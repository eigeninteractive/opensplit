import 'package:opensplit_api/opensplit_api.dart' as api;

import 'api_client.dart';

/// The URL a link token is shared as.
String joinUrl(String host, String token) => 'https://$host/app/join/$token';

/// Invites and open links, over the generated client. Throws [ApiFailure].
class Invites {
  Invites(api.OpensplitApi client) : _invites = client.getInvitesApi();

  final api.InvitesApi _invites;

  /// A link handing over one unclaimed place. Reissuing invalidates any
  /// previous link for that place.
  Future<api.Invite> create(String groupId, String memberId) =>
      fetch(_invites.createInvite(groupId: groupId, memberId: memberId));

  /// What [token] is for, read without spending it and without a session.
  /// Null for a token that names nothing, or a group since collected.
  Future<api.LinkPreview?> preview(String token) async {
    try {
      return await fetch(_invites.peekLink(token: token));
    } on ApiFailure catch (failure) {
      if (failure.code
          case api.ErrorCode.inviteInvalid ||
              api.ErrorCode.noGroup ||
              api.ErrorCode.groupPurged ||
              api.ErrorCode.inviteExpired) {
        return null;
      }
      rethrow;
    }
  }

  /// The unclaimed places [token]'s group is holding. Needs a session: these
  /// are other people's names.
  Future<List<api.Placeholder>> placeholders(String token) async =>
      (await fetch(_invites.linkPlaceholders(token: token))).placeholders;

  /// Spends [token]: claims [memberId] if given, otherwise arrives as somebody
  /// new under [displayName] (or the account's own name). A named invite
  /// needs neither.
  Future<api.Joined> join(
    String token, {
    String? memberId,
    String? displayName,
  }) => fetch(
    _invites.joinWithLink(
      token: token,
      joinRequest: api.JoinRequest(
        memberId: memberId,
        displayName: memberId == null ? displayName : null,
      ),
    ),
  );

  /// Mints the group's one live open link, revoking whatever preceded it.
  Future<api.GroupLink> createGroupLink(String groupId) =>
      fetch(_invites.createGroupLink(groupId: groupId));

  Future<void> revokeGroupLink(String groupId) =>
      fetch(_invites.revokeGroupLink(groupId: groupId));

  /// The group's live link, or null when there is none.
  Future<api.GroupLink?> currentGroupLink(String groupId) async =>
      (await fetch(_invites.getGroupLink(groupId: groupId))).link;
}

/// How the join screen reads a preview.
extension LinkPreviewReading on api.LinkPreview {
  bool get isOpenLink => kind == api.LinkKind.groupLink;

  /// Null only if the member who minted it cannot be resolved, which the
  /// schema makes unreachable while the link exists; rendered, not stored.
  String get inviter => inviterName ?? 'Someone';
}

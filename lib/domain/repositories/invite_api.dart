import '../models/member.dart';

/// A link that hands over one unclaimed place in a group.
class InviteLink {
  const InviteLink({
    required this.token,
    required this.groupId,
    required this.memberId,
    required this.expiresAt,
  });

  /// Single-use and expiring. Never a raw member id: a member id in a URL means
  /// anyone who ever sees that link can take over that person's financial
  /// identity in the group, permanently.
  final String token;

  final String groupId;
  final String memberId;
  final DateTime expiresAt;

  /// The URL to share. The same address is a web route and an Android App Link,
  /// so someone without the app opens the web build and it simply works.
  ///
  /// Under `/app/` because that is where the client is served: the site root is
  /// static marketing pages, and the App Links filter claims `/app` alone so a
  /// tap on the privacy policy opens a browser rather than the installed app.
  /// go_router never sees this prefix — `<base href="/app/">` absorbs it — so
  /// the route is still `/join/:token` on the Dart side.
  String urlFor(String host) => 'https://$host/app/join/$token';
}

/// What a link is for, read without spending it.
///
/// Exists so that the invitation can be shown before the account question is
/// asked. Redeeming first and asking afterwards is the ordering that locked
/// people out of their own groups: the slot went to whatever account happened
/// to hold the session, and the token — single use — was gone.
class InvitePreview {
  const InvitePreview({
    required this.groupName,
    required this.memberName,
    required this.inviterName,
    required this.memberCount,
    required this.isRedeemed,
    required this.isExpired,
    required this.isMember,
    required this.groupId,
  });

  final String groupId;

  final String groupName;

  /// The name on the place being handed over — what the person who sent the
  /// link called you.
  final String memberName;

  final String inviterName;
  final int memberCount;

  /// Spent and expired are reported rather than collapsed into "invalid",
  /// because they need different things said about them and only one of them
  /// is worth asking for a new link over.
  final bool isRedeemed;
  final bool isExpired;

  /// Whether whoever asked is already in this group under another name.
  ///
  /// Redeeming would be refused — one person cannot hold two places in a group
  /// — so the screen offers the group instead of a button that cannot work.
  final bool isMember;

  bool get isUsable => !isRedeemed && !isExpired && !isMember;
}

/// Raised when a link cannot be claimed. The messages are written for people.
class InviteRejected implements Exception {
  const InviteRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class InviteApi {
  /// Issues a link for an unclaimed place. Reissuing invalidates any previous
  /// link for that place.
  Future<InviteLink> create(String memberId);

  /// Describes [token] without redeeming it. Null if no such link exists.
  ///
  /// Works with no session, which is the point: whoever just tapped the link
  /// has not been asked who they are yet.
  Future<InvitePreview?> peek(String token);

  /// Spends a token, attaching the current account to the place it names.
  ///
  /// Throws [InviteRejected] if the link is unknown, spent, expired, or the
  /// caller is already in the group.
  Future<Member> redeem(String token);
}

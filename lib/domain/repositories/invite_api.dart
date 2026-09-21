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

/// A link that lets anybody holding it into a group.
///
/// Distinct from [InviteLink], which hands over one named place to one person.
/// This is the link you paste into a chat whose guest list you do not have yet,
/// and it is a genuinely bigger claim: possession is the whole authorisation,
/// and it is good for any number of arrivals until it expires or is revoked.
class GroupLink {
  const GroupLink({
    required this.token,
    required this.groupId,
    required this.expiresAt,
  });

  final String token;
  final String groupId;
  final DateTime expiresAt;

  /// The same address shape an invite uses, so there is one link format, one
  /// App Links filter and one route. Which kind of link a token names is the
  /// server's business, not the URL's.
  String urlFor(String host) => 'https://$host/app/join/$token';
}

/// What a group link is for, read without joining.
class GroupLinkPreview {
  const GroupLinkPreview({
    required this.groupId,
    required this.groupName,
    required this.inviterName,
    required this.memberCount,
    required this.isExpired,
    required this.isRevoked,
    required this.isMember,
  });

  final String groupId;
  final String groupName;
  final String inviterName;
  final int memberCount;

  /// Reported separately rather than collapsed into "invalid", because they
  /// need different things said about them: an expired link wants a new one, a
  /// revoked link means somebody decided it should stop working.
  final bool isExpired;
  final bool isRevoked;

  /// Whether whoever asked is already in this group.
  final bool isMember;

  bool get isUsable => !isExpired && !isRevoked && !isMember;
}

/// An unclaimed place in a group, offered to somebody arriving on a link.
///
/// The thing that stops one shared link turning a group of six into a group of
/// twelve: the people already typed in are shown to each arrival, so claiming
/// "Priya" is a single-column update rather than a seventh member row beside
/// the placeholder that was already her.
class LinkPlaceholder {
  const LinkPlaceholder({required this.memberId, required this.displayName});

  final String memberId;
  final String displayName;
}

/// What a `/join/:token` link turned out to name.
///
/// One route serves both kinds, so the screen asks once and switches on the
/// answer. Sealed, so a third kind of link could not be added without every
/// reader being made to account for it.
sealed class LinkTarget {
  const LinkTarget();
}

final class MemberInviteTarget extends LinkTarget {
  const MemberInviteTarget(this.preview);
  final InvitePreview preview;
}

final class GroupLinkTarget extends LinkTarget {
  const GroupLinkTarget(this.preview);
  final GroupLinkPreview preview;
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

  /// Works out which kind of link [token] is, without spending it.
  ///
  /// Null if it is neither. Works with no session, which is the point: the
  /// person holding it has not been asked who they are yet.
  Future<LinkTarget?> peekLink(String token);

  /// Mints the group's one live open link, revoking whatever preceded it.
  Future<GroupLink> createGroupLink(String groupId);

  /// Turns the group's open link off without minting another.
  Future<void> revokeGroupLink(String groupId);

  /// The group's live link, if it has one. Null when nobody has minted one or
  /// the last one has expired or been revoked.
  Future<GroupLink?> currentGroupLink(String groupId);

  /// The unclaimed places [token]'s group is holding.
  ///
  /// Requires a session, unlike [peekLink]: these are other people's names, and
  /// the arrival has chosen an account by the time this is asked.
  Future<List<LinkPlaceholder>> placeholdersFor(String token);

  /// Walks in on [token], claiming [memberId] if it is one of the places the
  /// group was already holding.
  ///
  /// Throws [InviteRejected] if the link is unknown, revoked, expired, the
  /// place is taken, or the caller is already in the group.
  Future<Member> joinWithLink(String token, {String? memberId});
}

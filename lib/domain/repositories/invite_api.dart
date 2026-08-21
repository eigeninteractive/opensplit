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
  String urlFor(String host) => 'https://$host/join/$token';
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

  /// Spends a token, attaching the current account to the place it names.
  ///
  /// Throws [InviteRejected] if the link is unknown, spent, expired, or the
  /// caller is already in the group.
  Future<Member> redeem(String token);
}

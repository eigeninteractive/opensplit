import 'models/member.dart';
import 'models/profile.dart';

/// Resolves the name shown for a group member.
String memberDisplayName(Member member, Profile? profile) {
  final claimed = profile?.id == member.profileId
      ? profile?.displayName?.trim() ?? ''
      : '';
  return claimed.isEmpty ? member.displayName : claimed;
}

import 'models/member.dart';
import 'models/profile.dart';

/// Resolves the name shown for a group member.
///
/// A claimed account profile is canonical across every group. The member row
/// remains the fallback for placeholders and for the brief interval before a
/// newly claimed profile reaches this device.
String memberDisplayName(Member member, Profile? profile) {
  final claimed = profile?.id == member.profileId
      ? profile?.displayName?.trim() ?? ''
      : '';
  return claimed.isEmpty ? member.displayName : claimed;
}

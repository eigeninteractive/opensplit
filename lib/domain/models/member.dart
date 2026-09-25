import '../../data/local/database.dart';

export '../../data/local/database.dart' show Member;

extension MemberState on Member {
  /// Nobody has claimed this place yet.
  bool get isPlaceholder => profileId == null;

  bool get isActive => leftAt == null;
}

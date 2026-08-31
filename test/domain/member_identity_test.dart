import 'package:opensplit/domain/member_identity.dart';
import 'package:opensplit/domain/models/member.dart';
import 'package:opensplit/domain/models/profile.dart';
import 'package:test/test.dart';

void main() {
  final claimed = Member(
    id: 'member-brinda',
    groupId: 'group-home',
    profileId: 'profile-brinda',
    displayName: 'Brinda',
    joinedAt: _joinedAt,
  );

  test('a claimed profile is the canonical display name', () {
    expect(
      memberDisplayName(
        claimed,
        const Profile(id: 'profile-brinda', displayName: ' Brinda D '),
      ),
      'Brinda D',
    );
  });

  test('a placeholder uses the name stored on the member', () {
    expect(
      memberDisplayName(claimed.copyWith(profileId: null), null),
      'Brinda',
    );
  });

  test('a missing or unnamed profile falls back to the member', () {
    expect(memberDisplayName(claimed, null), 'Brinda');
    expect(
      memberDisplayName(
        claimed,
        const Profile(id: 'profile-brinda', displayName: '  '),
      ),
      'Brinda',
    );
  });

  test('a different profile cannot rename the member', () {
    expect(
      memberDisplayName(
        claimed,
        const Profile(id: 'profile-someone-else', displayName: 'Someone'),
      ),
      'Brinda',
    );
  });
}

final _joinedAt = DateTime.utc(2026, 1, 1);

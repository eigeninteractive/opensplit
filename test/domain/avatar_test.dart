import 'package:flutter_test/flutter_test.dart';
import 'package:opensplit/domain/avatar.dart';
import 'package:opensplit_api/opensplit_api.dart'
    show AvatarColor, AvatarIcon, AvatarKind;

void main() {
  group('an avatar', () {
    test('goes to its columns and back unchanged', () {
      for (final avatar in [
        const InitialsAvatar(),
        const InitialsAvatar(color: AvatarColor.teal),
        const EmojiAvatar('🏖️', color: AvatarColor.amber),
        const IconAvatar(AvatarIcon.sailing),
        const PhotoAvatar('avatars/p/1.webp', color: AvatarColor.pink),
      ]) {
        expect(Avatar.fromColumns(avatar.columns), avatar);
      }
    });

    test('sets only the field its kind reads', () {
      expect(const EmojiAvatar('🏏').columns, (
        kind: AvatarKind.emoji,
        color: null,
        emoji: '🏏',
        icon: null,
        photo: null,
      ));
    });

    test('shows as initials when its kind is missing what it needs', () {
      // A newer build's icon, or a row whose field never arrived.
      for (final columns in [
        (
          kind: AvatarKind.icon,
          color: AvatarColor.blue,
          emoji: null,
          icon: AvatarIcon.unknownDefaultOpenApi,
          photo: null,
        ),
        (
          kind: AvatarKind.emoji,
          color: AvatarColor.blue,
          emoji: null,
          icon: null,
          photo: null,
        ),
        (
          kind: AvatarKind.unknownDefaultOpenApi,
          color: AvatarColor.blue,
          emoji: null,
          icon: null,
          photo: null,
        ),
      ]) {
        expect(
          Avatar.fromColumns(columns),
          const InitialsAvatar(color: AvatarColor.blue),
        );
      }
    });

    test('keeps its picture when only its hue changes', () {
      expect(
        const EmojiAvatar('🏏').withColor(AvatarColor.green),
        const EmojiAvatar('🏏', color: AvatarColor.green),
      );
    });
  });

  group('the hue before anybody picks one', () {
    test('is the same on every run and every platform', () {
      // Pinned, because a hash that drifted would repaint everyone's avatar.
      expect(stableHash(''), 0x811c9dc5);
      expect(stableHash('a'), 0xe40c292c);
      expect(
        hueFor('0195f3a2-8b1e-7c3d-9f42-1a2b3c4d5e6f'),
        isA<AvatarColor>(),
      );
      expect(
        hueFor('0195f3a2-8b1e-7c3d-9f42-1a2b3c4d5e6f'),
        hueFor('0195f3a2-8b1e-7c3d-9f42-1a2b3c4d5e6f'),
      );
    });

    test('spreads ids across every hue', () {
      final hues = {for (var i = 0; i < 200; i++) hueFor('member-$i')};
      expect(hues, containsAll(avatarHues));
      expect(hues, isNot(contains(AvatarColor.unknownDefaultOpenApi)));
    });
  });

  group('initials', () {
    test('come from the first and last words', () {
      expect(initialsOf('Ana Lima'), 'AL');
      expect(initialsOf('ana'), 'A');
      expect(initialsOf('Ana Maria  da Silva'), 'AS');
      expect(initialsOf('Flat 4B'), 'F4');
      expect(initialsOf('  '), '');
    });

    test('keep a letter whole when a mark combines with it', () {
      // "Émile" spelt with a combining acute: two code points, one letter.
      expect(initialsOf('émile'), 'É');
    });
  });
}

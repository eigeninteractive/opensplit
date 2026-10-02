import 'package:material_ui/material_ui.dart';
import 'package:opensplit_api/opensplit_api.dart' show AvatarIcon;

import '../../application/ledger_providers.dart';
import '../../data/local/database.dart';
import '../../domain/avatar.dart';
import '../theme.dart';

/// A person or a group, in a circle: a [CircleAvatar] on the avatar's hue.
///
/// [id] is whose avatar it is, which decides the hue until somebody picks one.
/// The name is beside the avatar wherever one appears, so the circle is left
/// out of the semantics tree rather than read out twice.
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.avatar,
    required this.name,
    required this.id,
    this.radius = 20,
  });

  final Avatar avatar;
  final String name;
  final String id;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = AvatarPalette.of(context)[avatar.color ?? hueFor(id)];
    final textTheme = Theme.of(context).textTheme;

    final child = switch (avatar) {
      EmojiAvatar(:final emoji) => Text(
        emoji,
        style: TextStyle(fontSize: radius),
      ),
      IconAvatar(:final icon) => Icon(avatarIconData(icon), size: radius),
      // Nothing can upload a photo yet, so one cannot be shown either.
      InitialsAvatar() || PhotoAvatar() => switch (initialsOf(name)) {
        // Somebody who has not chosen a name yet.
        '' => Icon(Icons.person_outline, size: radius),
        final initials => Text(initials, style: _initialsStyle(textTheme)),
      },
    };

    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: child,
      ),
    );
  }

  /// The type scale's step that fits the circle, rather than a size of its
  /// own.
  TextStyle? _initialsStyle(TextTheme theme) => switch (radius) {
    < 16 => theme.labelMedium,
    < 24 => theme.titleSmall,
    < 32 => theme.titleMedium,
    < 44 => theme.headlineSmall,
    _ => theme.headlineMedium,
  };
}

/// A member: their account's avatar once they have one, otherwise initials on
/// a hue of their own.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.ledger,
    required this.member,
    this.radius = 20,
  });

  final GroupLedger ledger;
  final Member member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final profile = ledger.profiles[member.profileId];
    return AvatarView(
      avatar: profile?.avatar ?? const InitialsAvatar(),
      name: ledger.nameOfMember(member),
      // The account's id where there is one, so a person keeps one hue across
      // every group they are in.
      id: member.profileId ?? member.id,
      radius: radius,
    );
  }
}

/// The Material Symbol for [icon].
IconData avatarIconData(AvatarIcon icon) => switch (icon) {
  AvatarIcon.flight => Icons.flight_rounded,
  AvatarIcon.luggage => Icons.luggage_rounded,
  AvatarIcon.beachAccess => Icons.beach_access_rounded,
  AvatarIcon.hiking => Icons.hiking_rounded,
  AvatarIcon.sailing => Icons.sailing_rounded,
  AvatarIcon.train => Icons.train_rounded,
  AvatarIcon.directionsCar => Icons.directions_car_rounded,
  AvatarIcon.home => Icons.home_rounded,
  AvatarIcon.apartment => Icons.apartment_rounded,
  AvatarIcon.restaurant => Icons.restaurant_rounded,
  AvatarIcon.localCafe => Icons.local_cafe_rounded,
  AvatarIcon.localBar => Icons.local_bar_rounded,
  AvatarIcon.celebration => Icons.celebration_rounded,
  AvatarIcon.cake => Icons.cake_rounded,
  AvatarIcon.sportsSoccer => Icons.sports_soccer_rounded,
  AvatarIcon.sportsCricket => Icons.sports_cricket_rounded,
  AvatarIcon.sportsBasketball => Icons.sports_basketball_rounded,
  AvatarIcon.fitnessCenter => Icons.fitness_center_rounded,
  AvatarIcon.musicNote => Icons.music_note_rounded,
  AvatarIcon.school => Icons.school_rounded,
  AvatarIcon.work => Icons.work_rounded,
  AvatarIcon.pets => Icons.pets_rounded,
  AvatarIcon.favorite => Icons.favorite_rounded,
  AvatarIcon.familyRestroom => Icons.family_restroom_rounded,
  AvatarIcon.unknownDefaultOpenApi => Icons.category_rounded,
};

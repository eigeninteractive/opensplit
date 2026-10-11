import 'package:material_ui/material_ui.dart';

import '../../data/local/database.dart';
import '../../domain/avatar.dart';
import 'avatar_view.dart';
import 'shared_element.dart';

/// Keeps the selected group's identity visible as its detail page opens.
///
/// A fitted avatar scales the circle and its contents together during Flutter's
/// stock Hero flight. Deep links need no source hero; reduced motion skips it.
class GroupAvatarHero extends StatelessWidget {
  const GroupAvatarHero({
    super.key,
    required this.group,
    required this.radius,
    this.avatar,
  });

  final Group group;
  final double radius;

  /// The unsaved picture shown in the group's picture editor.
  final Avatar? avatar;

  @override
  Widget build(BuildContext context) => SharedElement(
    tag: ('group-avatar', group.id),
    child: SizedBox.square(
      dimension: radius * 2,
      child: FittedBox(
        child: AvatarView(
          avatar: avatar ?? group.avatar,
          name: group.name,
          id: group.id,
          radius: radius,
        ),
      ),
    ),
  );
}

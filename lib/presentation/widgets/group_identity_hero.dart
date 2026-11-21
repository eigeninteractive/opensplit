import 'package:material_ui/material_ui.dart';

import '../../data/local/database.dart';
import '../../domain/avatar.dart';
import 'avatar_view.dart';

/// Shares the group avatar between the list, header, and picture editor.
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
  Widget build(BuildContext context) => HeroMode(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: ('group-avatar', group.id),
      transitionOnUserGestures: true,
      placeholderBuilder: settledRouteHeroPlaceholder,
      child: Material(
        type: MaterialType.transparency,
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
      ),
    ),
  );
}

/// Shares a group name between the list card and the detail header.
class GroupNameHero extends StatelessWidget {
  const GroupNameHero({
    super.key,
    required this.group,
    required this.style,
    this.maxLines,
  });

  final Group group;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: ('group-name', group.id),
      transitionOnUserGestures: true,
      placeholderBuilder: settledRouteHeroPlaceholder,
      flightShuttleBuilder: _flight,
      child: Material(
        type: MaterialType.transparency,
        child: Text(
          group.name,
          style: style,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: maxLines,
          overflow: maxLines == null
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
        ),
      ),
    ),
  );

  static Widget _flight(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    Text label(BuildContext endpoint) =>
        ((endpoint.widget as Hero).child as Material).child! as Text;
    final from = label(fromContext);
    final to = label(toContext);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            to.data!,
            style: TextStyle.lerp(
              from.style,
              to.style,
              direction == HeroFlightDirection.push
                  ? animation.value
                  : 1 - animation.value,
            ),
            textScaler: to.textScaler,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Restores a static group Hero if overlapping pops skip its return flight.
Widget settledRouteHeroPlaceholder(
  BuildContext context,
  Size size,
  Widget child,
) {
  // The Groups list is current in its own navigator while the root navigator
  // covers the whole destination with a detail page.
  final route =
      ModalRoute.of(Navigator.of(context).context) ?? ModalRoute.of(context);
  if (route == null) return SizedBox.fromSize(size: size);
  final entering = route.animation;
  final covering = route.secondaryAnimation;
  return ListenableBuilder(
    listenable: Listenable.merge([entering, covering]),
    builder: (context, _) {
      final settled =
          route.isCurrent &&
          (entering?.isCompleted ?? true) &&
          (covering?.isDismissed ?? true);
      return settled ? child : SizedBox.fromSize(size: size);
    },
  );
}

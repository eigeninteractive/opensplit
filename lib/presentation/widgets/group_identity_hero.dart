import 'package:material_ui/material_ui.dart';

import '../../data/local/database.dart';
import '../navigation.dart';

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

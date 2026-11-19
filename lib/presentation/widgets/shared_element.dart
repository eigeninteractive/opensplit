import 'package:material_ui/material_ui.dart';

/// A visual shared by two routes, with the system's reduced-motion preference.
class SharedElement extends StatelessWidget {
  const SharedElement({
    super.key,
    required this.tag,
    required this.child,
    this.placeholderBuilder,
  });

  final Object tag;
  final Widget child;

  /// What occupies this endpoint when the hero is flying.
  final HeroPlaceholderBuilder? placeholderBuilder;

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: tag,
      transitionOnUserGestures: true,
      placeholderBuilder: placeholderBuilder,
      child: Material(type: MaterialType.transparency, child: child),
    ),
  );
}

/// Shares a label or value with an editable field without flying its controls.
///
/// The field stays on its route. Only its text flies, with explicit styles so
/// the overlay cannot inherit a different font, colour or text scale.
class SharedText extends StatelessWidget {
  const SharedText({
    super.key,
    required this.tag,
    required this.text,
    required this.style,
    this.maxLines = 1,
    this.child,
    this.placeholderBuilder,
  });

  final Object tag;
  final String text;
  final TextStyle style;

  /// The visible line limit; null lets the label wrap without truncation.
  final int? maxLines;
  final Widget? child;

  /// What occupies this endpoint when the hero is flying.
  final HeroPlaceholderBuilder? placeholderBuilder;

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: tag,
      transitionOnUserGestures: true,
      placeholderBuilder: placeholderBuilder,
      flightShuttleBuilder: _flight,
      child: _TextEndpoint(
        text: text,
        style: style,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
        child: child,
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
    final from = (fromContext.widget as Hero).child as _TextEndpoint;
    final to = (toContext.widget as Hero).child as _TextEndpoint;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            to.text,
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

/// Restores a static hero if overlapping pops skip its return flight.
Widget settledRouteHeroPlaceholder(
  BuildContext context,
  Size size,
  Widget child,
) {
  // The Groups list lives in a nested navigator. Its first page stays current
  // there even while the root navigator covers the whole Groups destination.
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

class _TextEndpoint extends StatelessWidget {
  const _TextEndpoint({
    required this.text,
    required this.style,
    required this.textScaler,
    required this.maxLines,
    this.child,
  });

  final String text;
  final TextStyle style;
  final TextScaler textScaler;
  final int? maxLines;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child:
        child ??
        Text(
          text,
          style: style,
          textScaler: textScaler,
          maxLines: maxLines,
          overflow: maxLines == null
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
        ),
  );
}

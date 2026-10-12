import 'package:material_ui/material_ui.dart';

/// A visual shared by two routes, with the system's reduced-motion preference.
class SharedElement extends StatelessWidget {
  const SharedElement({super.key, required this.tag, required this.child});

  final Object tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: tag,
      transitionOnUserGestures: true,
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
  });

  final Object tag;
  final String text;
  final TextStyle style;

  /// The visible line limit; null lets the label wrap without truncation.
  final int? maxLines;
  final Widget? child;

  @override
  Widget build(BuildContext context) => HeroMode(
    enabled: !MediaQuery.disableAnimationsOf(context),
    child: Hero(
      tag: tag,
      transitionOnUserGestures: true,
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

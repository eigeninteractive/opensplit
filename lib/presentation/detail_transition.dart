import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Opens an expense or payment from the bounds of its row.
void openDetail(
  BuildContext context,
  String location, {
  required Color color,
  required BorderRadius corners,
}) {
  context.push<void>(
    location,
    extra: MediaQuery.disableAnimationsOf(context)
        ? null
        : _DetailOrigin(context: context, color: color, corners: corners),
  );
}

/// Builds the same page for both a tap and a direct link.
Page<void> detailPage(GoRouterState state, Widget child) {
  final arguments = {...state.pathParameters, ...state.uri.queryParameters};
  return switch (state.extra) {
    final _DetailOrigin origin => _DetailPage(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: arguments,
      restorationId: state.pageKey.value,
      origin: origin,
      child: child,
    ),
    _ => MaterialPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: arguments,
      restorationId: state.pageKey.value,
      child: child,
    ),
  };
}

class _DetailOrigin {
  const _DetailOrigin({
    required this.context,
    required this.color,
    required this.corners,
  });

  final BuildContext context;
  final Color color;
  final BorderRadius corners;

  // GoRouter serializes extra for browser history. A restored page has no
  // live source widget and opens with the normal platform transition.
  Object? toJson() => null;

  RRect? boundsIn(BuildContext navigatorContext) {
    if (!context.mounted) return null;
    final source = context.findRenderObject();
    final navigator = navigatorContext.findRenderObject();
    if (source is! RenderBox || navigator is! RenderBox) return null;
    if (!source.attached || !source.hasSize || !navigator.hasSize) return null;

    Rect boundsOf(RenderObject box) => MatrixUtils.transformRect(
      box.getTransformTo(navigator),
      box.paintBounds,
    );

    final viewport = RenderAbstractViewport.maybeOf(source);
    var bounds = boundsOf(source).intersect(Offset.zero & navigator.size);
    if (viewport != null) bounds = bounds.intersect(boundsOf(viewport));
    return bounds.isFinite && !bounds.isEmpty ? corners.toRRect(bounds) : null;
  }
}

class _DetailPage extends MaterialPage<void> {
  const _DetailPage({
    required super.key,
    required super.name,
    required super.arguments,
    required super.restorationId,
    required this.origin,
    required super.child,
  });

  final _DetailOrigin origin;

  @override
  Route<void> createRoute(BuildContext context) => _DetailRoute(this);
}

class _DetailRoute extends PageRoute<void>
    with MaterialRouteTransitionMixin<void> {
  _DetailRoute(_DetailPage page)
    : super(settings: page, allowSnapshotting: false);

  _DetailPage get _page => settings as _DetailPage;
  RRect? _bounds;
  late final CurvedAnimation _expansion;

  @override
  Duration get transitionDuration => _bounds == null
      ? super.transitionDuration
      : const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => _bounds == null
      ? super.reverseTransitionDuration
      : const Duration(milliseconds: 220);

  @override
  bool get maintainState => _page.maintainState;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  void install() {
    super.install();
    _expansion = CurvedAnimation(
      parent: animation!,
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.fastOutSlowIn.flipped,
    );
  }

  @override
  void dispose() {
    _expansion.dispose();
    super.dispose();
  }

  @override
  TickerFuture didPush() {
    _bounds = _page.origin.boundsIn(navigator!.context);
    return super.didPush();
  }

  @override
  bool didPop(void result) {
    _bounds = popGestureInProgress
        ? null
        : _page.origin.boundsIn(navigator!.context);
    return super.didPop(result);
  }

  bool _transforms(BuildContext context) =>
      _bounds != null &&
      !popGestureInProgress &&
      !MediaQuery.disableAnimationsOf(context);

  @override
  DelegatedTransitionBuilder get delegatedTransition =>
      (context, animation, secondary, allowSnapshotting, child) {
        // Keep the previous page at its laid-out position behind the growing
        // surface. During predictive Back, use the platform's own preview.
        if (_transforms(context)) return child;
        return super.delegatedTransition?.call(
          context,
          animation,
          secondary,
          allowSnapshotting,
          child,
        );
      };

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => ListenableBuilder(
    listenable: animation,
    builder: (context, _) {
      final source = _transforms(context) && !animation.isCompleted
          ? _bounds
          : null;
      final progress = source == null ? 1.0 : animation.value;
      final expansion = source == null ? 1.0 : _expansion.value;
      return ClipRRect(
        clipBehavior: source == null ? Clip.none : Clip.antiAlias,
        clipper: source == null ? null : _SurfaceClipper(source, expansion),
        child: ColoredBox(
          color: _page.origin.color.withValues(
            alpha: source != null
                ? const Interval(0, 0.15).transform(progress)
                : 0,
          ),
          child: Opacity(
            // Give the surface time to become opaque and move away from the
            // row before revealing the new page's text.
            opacity: const Interval(0.25, 0.7).transform(progress),
            child: Transform.translate(
              // Keep the incoming content with the moving top-left edge.
              offset:
                  (source?.outerRect.topLeft ?? Offset.zero) * (1 - expansion),
              // Keep Flutter's gesture handler mounted while suppressing the
              // standard page motion during the container transform.
              child: super.buildTransitions(
                context,
                source == null ? animation : kAlwaysCompleteAnimation,
                secondaryAnimation,
                child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SurfaceClipper extends CustomClipper<RRect> {
  const _SurfaceClipper(this.source, this.progress);

  final RRect source;
  final double progress;

  @override
  RRect getClip(Size size) => RRect.lerp(
    source,
    BorderRadius.zero.toRRect(Offset.zero & size),
    progress,
  )!;

  @override
  bool shouldReclip(_SurfaceClipper oldClipper) =>
      source != oldClipper.source || progress != oldClipper.progress;
}

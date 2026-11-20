import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Opens a routed detail page from the bounds of the tapped card or row.
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

  @override
  bool get maintainState => _page.maintainState;

  @override
  Widget buildContent(BuildContext context) => _page.child;

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
      final transforming = _transforms(context) && !animation.isCompleted;
      final progress = transforming ? animation.value : 1.0;
      return ClipRRect(
        clipBehavior: transforming ? Clip.antiAlias : Clip.none,
        clipper: transforming ? _SurfaceClipper(_bounds!, progress) : null,
        child: ColoredBox(
          color: _page.origin.color.withValues(
            alpha: transforming
                ? const Interval(0, 0.2).transform(progress)
                : 0,
          ),
          child: Opacity(
            opacity: const Interval(0.15, 0.85).transform(progress),
            // Keep the Material route's gesture handler mounted. Only its
            // page motion is suppressed while the container is moving.
            child: super.buildTransitions(
              context,
              transforming ? kAlwaysCompleteAnimation : animation,
              secondaryAnimation,
              child,
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
    Curves.easeInOutCubicEmphasized.transform(progress),
  )!;

  @override
  bool shouldReclip(_SurfaceClipper oldClipper) =>
      source != oldClipper.source || progress != oldClipper.progress;
}

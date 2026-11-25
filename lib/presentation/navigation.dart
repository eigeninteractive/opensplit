import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The minimum window width for the labeled navigation sidebar.
const navigationSidebarMinWidth = 1200.0;

/// An editor result that changes what the details route can display.
enum EntryEditResult {
  /// The expense or payment was deleted successfully.
  deleted,
}

/// Maps native App Links and authentication detours onto internal app routes.
String? redirectAppRoute(Uri uri, {required bool signedIn}) {
  final path = uri.path;
  if (path == '/app' || path.startsWith('/app/')) {
    final internal = path.substring('/app'.length);
    return Uri(
      path: internal.isEmpty ? '/' : internal,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  final open = path == '/welcome' || path.startsWith('/join/');
  if (!signedIn && !open) {
    return Uri(
      path: '/welcome',
      queryParameters: {'from': uri.toString()},
    ).toString();
  }
  if (signedIn && path == '/welcome') {
    return safeReturnLocation(uri.queryParameters['from']);
  }
  return null;
}

/// Accepts only an internal return destination, never an external redirect.
String safeReturnLocation(String? location) {
  final uri = location == null ? null : Uri.tryParse(location);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      uri.path == '/welcome' ||
      uri.path.startsWith('/app')) {
    return '/';
  }
  return uri.toString();
}

/// Where a sign-in that leaves the app should land when it comes back.
String returnDestination(Uri current) => current.path == '/welcome'
    ? safeReturnLocation(current.queryParameters['from'])
    : safeReturnLocation(current.toString());

/// Returns [result] to the previous screen, or goes to [fallback].
void goBack<T>(BuildContext context, String fallback, {T? result}) {
  if (context.canPop()) {
    context.pop(result);
  } else {
    context.go(fallback);
  }
}

/// Restores a shared element if overlapping pops skip its return flight.
Widget settledRouteHeroPlaceholder(
  BuildContext context,
  Size size,
  Widget child,
) {
  // A shell destination stays current in its own navigator while a root
  // route covers it. Its placeholder must follow the covering route.
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

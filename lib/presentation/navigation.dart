import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

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

/// Goes back one screen, or to [fallback] when there is no back to go to.
void goBack(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

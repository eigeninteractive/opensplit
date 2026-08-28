import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Maps native App Links and authentication detours onto internal app routes.
///
/// The browser removes `/app/` through its base URL. Android hands the full
/// path to the router, so it needs the same normalization explicitly.
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
///
/// On the welcome screen the destination is whatever sent the user there — an
/// invite link, usually — so it comes from `from` and is validated. Anywhere
/// else it is the screen being stood on, because linking an identity from the
/// account screen should return to the account screen.
String returnDestination(Uri current) => current.path == '/welcome'
    ? safeReturnLocation(current.queryParameters['from'])
    : safeReturnLocation(current.toString());

/// Goes back one screen, or to [fallback] when there is no back to go to.
///
/// Both halves are needed because either one alone is wrong somewhere.
///
/// A plain pop is wrong for a link opened from outside the app. An invite or an
/// App Link drops someone straight onto a group with a single page in the
/// stack, and a back button that can only pop is a dead control on exactly the
/// screen a new user arrives at.
///
/// A plain `go` is wrong everywhere else, and is what this app used to do. `go`
/// replaces the whole route stack and reports the result to the engine as a
/// forward navigation, so tapping back pushed a *new* browser history entry
/// rather than returning to the previous one. The browser's own back button
/// then went forward again, into the screen the user had just left.
void goBack(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

import 'package:flutter/widgets.dart';

/// Google's own sign-in button, on the platform that requires one.
///
/// Null everywhere but the web. Android starts the flow from an ordinary
/// button through `GoogleSignIn.authenticate`, so it needs nothing from here —
/// see [GoogleSignInGateway.obtainIdToken].
///
/// The web has no such call. Google Identity Services will only begin a
/// sign-in from a button it has rendered itself, which is both a security
/// boundary and a branding rule, so the widget below is not a styled
/// substitute: it is Google's iframe. Tapping it produces an authentication
/// event rather than returning anything, which is why the web path listens
/// instead of awaiting.
Widget? googleSignInButton() => null;

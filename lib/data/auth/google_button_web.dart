import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// The real thing on the web: an iframe Google renders and owns.
///
/// Sized and shaped to sit beside this app's own buttons as closely as the
/// configuration allows. It cannot be themed further, and should not be — the
/// point of it is that a user recognises it as Google's rather than ours.
Widget? googleSignInButton() => web.renderButton(
  configuration: web.GSIButtonConfiguration(
    type: web.GSIButtonType.standard,
    theme: web.GSIButtonTheme.outline,
    size: web.GSIButtonSize.large,
    text: web.GSIButtonText.continueWith,
    shape: web.GSIButtonShape.rectangular,
    logoAlignment: web.GSIButtonLogoAlignment.left,
  ),
);

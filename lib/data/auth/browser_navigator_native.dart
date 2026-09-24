/// Leaving the page, on a platform that never does.
///
/// Reached only through the conditional export in `browser_navigator.dart`, and
/// only by the Google redirect flow — which runs when this build has no way to
/// mint an ID token in-process, which is the web alone. Getting here on Android
/// means the platform switch in [BetterAuthService] is wrong, and a thrown
/// error names that rather than a navigation quietly doing nothing.
void navigateBrowser(String url) => throw UnsupportedError(
  'Only the web signs in by leaving the page. This platform mints a Google ID '
  'token in-process.',
);

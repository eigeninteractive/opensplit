/// Leaving the page, on a platform that never does.
void navigateBrowser(String url) => throw UnsupportedError(
  'Only the web signs in by leaving the page. This platform mints a Google ID '
  'token in-process.',
);

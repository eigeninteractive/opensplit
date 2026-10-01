import 'package:web/web.dart' as web;

/// The key `web/index.html` reads to decide whether to draw group cards.
const _groupsKey = 'opensplit.hasGroups';

/// The key `web/index.html` reads to decide whether to draw the app at all.
const _sessionKey = 'opensplit.signedIn';

/// Tells the next cold start whether this browser has any groups to show.
void recordHasGroups(bool hasGroups) {
  _write(_groupsKey, hasGroups);
}

/// Tells the next cold start whether to draw the app or the welcome screen.
void recordSignedIn(bool signedIn) {
  _write(_sessionKey, signedIn);
  if (!signedIn) _write(_groupsKey, false);
}

/// localStorage is the only store readable synchronously on the first frame of
/// the document. Losing it costs nothing: every key here is absent by default
/// and the loader's fallback is the quieter drawing, not the louder one.
void _write(String key, bool value) {
  try {
    if (value) {
      web.window.localStorage.setItem(key, '1');
    } else {
      web.window.localStorage.removeItem(key);
    }
  } catch (_) {
    // Private mode, or site data blocked. The skeleton has a safe default.
  }
}

import 'package:web/web.dart' as web;

/// The key `web/index.html` reads to decide whether to draw group cards.
///
/// Namespaced because this shares an origin with nothing else, but a bare
/// `hasGroups` would still be a poor neighbour if that ever changes.
const _groupsKey = 'opensplit.hasGroups';

/// The key `web/index.html` reads to decide whether to draw the app at all.
const _sessionKey = 'opensplit.signedIn';

/// Tells the next cold start whether this browser has any groups to show.
///
/// The skeleton cannot ask the database — it runs before the engine, and the
/// database is inside it. Without this it has to guess, and it guessed wrong
/// for exactly the people who wait longest: someone arriving for the first time
/// has an empty cache and no groups, so three placeholder cards would dissolve
/// into "No groups yet".
void recordHasGroups(bool hasGroups) {
  _write(_groupsKey, hasGroups);
}

/// Tells the next cold start whether to draw the app or the welcome screen.
///
/// The loader used to draw the app bar, the rail, the button and the
/// navigation bar for everybody, on the grounds that they are on the screen in
/// every state. They are not: `WelcomeScreen` is a bare `Scaffold` with a
/// centred column and none of that chrome, so somebody arriving signed out —
/// the person with the emptiest cache and the longest wait — watched a full
/// app layout paint and then vanish.
///
/// Signing out clears the group hint too. Chrome with cards under it is the
/// most confident thing this loader can draw, and it would be drawn for
/// somebody about to be asked who they are.
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

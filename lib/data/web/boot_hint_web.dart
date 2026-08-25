import 'package:web/web.dart' as web;

/// The key `web/index.html` reads to decide whether to draw group cards.
///
/// Namespaced because this shares an origin with nothing else, but a bare
/// `hasGroups` would still be a poor neighbour if that ever changes.
const _key = 'opensplit.hasGroups';

/// Tells the next cold start whether this browser has any groups to show.
///
/// The skeleton cannot ask the database — it runs before the engine, and the
/// database is inside it. Without this it has to guess, and it guessed wrong
/// for exactly the people who wait longest: someone arriving for the first time
/// has an empty cache and no groups, so three placeholder cards would dissolve
/// into "No groups yet".
///
/// localStorage is the only store readable synchronously on the first frame of
/// the document. Losing it costs nothing: the skeleton falls back to drawing
/// the chrome alone, which is true for everybody.
void recordHasGroups(bool hasGroups) {
  try {
    if (hasGroups) {
      web.window.localStorage.setItem(_key, '1');
    } else {
      web.window.localStorage.removeItem(_key);
    }
  } catch (_) {
    // Private mode, or site data blocked. The skeleton has a safe default.
  }
}

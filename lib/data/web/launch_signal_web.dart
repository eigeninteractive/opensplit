import 'package:web/web.dart' as web;

/// The event `web/index.html` waits for before fading out its splash.
const _launchShown = 'opensplit-launch-shown';

/// Tells `web/index.html` that the first real frame is on screen.
///
/// Flutter's own `flutter-first-frame` event fires after the first frame is
/// built even while that frame is deferred, so it would take the splash down
/// onto a blank page while the app is still reading saved data.
void announceLaunchShown() {
  web.window.dispatchEvent(web.Event(_launchShown));
}

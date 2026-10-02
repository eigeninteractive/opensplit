import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The message `service_worker/src/messages.ts` calls `SKIP_WAITING`.
const _skipWaiting = 'SKIP_WAITING';

/// How often a tab that is never reloaded asks whether a release has shipped.
///
/// Browsers only look on navigation, and an installed web app can go days
/// without one.
const _checkEvery = Duration(hours: 1);

web.ServiceWorkerRegistration? _registration;

/// Set once the person has asked to restart, so the switch of worker it causes
/// reloads this tab rather than offering the same restart again.
bool _restarting = false;

/// Calls [onReady] when a newer release has installed and is waiting for this
/// tab, or once another tab has already switched to it.
///
/// The worker never takes over a tab by itself (see `service_worker/src/sw.ts`),
/// so the release this tab loaded stays whole until the person restarts. May
/// call [onReady] more than once for the same release.
void watchForNewRelease(void Function() onReady) {
  // Absent outside a secure context, such as a LAN address during development.
  if (!web.window.navigator.has('serviceWorker')) return;
  final container = web.window.navigator.serviceWorker;

  // The first worker claiming a tab that had none is an install, not an update.
  var controlled = container.controller != null;
  container.addEventListener(
    'controllerchange',
    (web.Event _) {
      if (_restarting) {
        web.window.location.reload();
      } else if (controlled) {
        onReady();
      }
      controlled = true;
    }.toJS,
  );

  unawaited(_watchRegistration(container, onReady));
}

/// Moves every tab to the waiting release, and reloads this one into it.
void restartIntoNewRelease() {
  _restarting = true;
  final waiting = _registration?.waiting;
  if (waiting == null) {
    // Another tab already switched; this one only has to load what it serves.
    web.window.location.reload();
    return;
  }
  // The worker activates and claims every tab, and `controllerchange` above
  // reloads this one.
  waiting.postMessage({'type': _skipWaiting}.jsify());
}

Future<void> _watchRegistration(
  web.ServiceWorkerContainer container,
  void Function() onReady,
) async {
  final registration = await container.ready.toDart;
  _registration = registration;

  void offerIfWaiting() {
    if (registration.waiting != null && container.controller != null) {
      onReady();
    }
  }

  // Installed during an earlier visit, while another tab held it back.
  offerIfWaiting();
  registration.addEventListener(
    'updatefound',
    (web.Event _) {
      final installing = registration.installing;
      installing?.addEventListener(
        'statechange',
        (web.Event _) {
          if (installing.state == 'installed') offerIfWaiting();
        }.toJS,
      );
    }.toJS,
  );

  Timer.periodic(_checkEvery, (_) {
    // Offline, or the server is down: the next tick asks again.
    registration.update().toDart.ignore();
  });
}

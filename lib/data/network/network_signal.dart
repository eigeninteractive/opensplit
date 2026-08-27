import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether this device has a network at all, as it changes.
///
/// A thin wrapper over `connectivity_plus`, and thin on purpose: it exists so
/// that [SyncScheduler] can be handed a `Stream<bool>` and tested without a
/// platform channel anywhere near it.
///
/// What this reports is whether an interface is up, NOT whether the server can
/// be reached -- a captive portal at an airport looks online here and is not.
/// That is the right signal anyway: this only ever decides whether to *attempt*
/// a sync, and a sync that cannot reach the server is already a no-op that
/// changes nothing on screen. Probing for real reachability would mean a
/// request on every network flap to save a request on some of them.
class NetworkSignal {
  const NetworkSignal();

  Stream<bool> get changes {
    try {
      return Connectivity().onConnectivityChanged
          .map(
            (results) =>
                results.any((result) => result != ConnectivityResult.none),
          )
          // A platform that cannot answer must not take the app down with it.
          // On a build with no plugin registered -- a widget test, a platform
          // the package does not cover -- this simply never emits, and the
          // other sync triggers carry on unaffected.
          .handleError((Object _) {});
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }
}

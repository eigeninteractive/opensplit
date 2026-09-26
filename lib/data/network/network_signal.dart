import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether this device has a network at all, as it changes.
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
          .handleError((Object _) {});
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }
}

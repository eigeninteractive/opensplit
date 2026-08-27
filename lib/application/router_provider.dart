import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../presentation/router.dart';
import 'session_providers.dart';

part 'router_provider.g.dart';

/// The one router instance.
///
/// A provider rather than a field on the app widget's state so that things
/// outside the widget tree can navigate — specifically a notification tap,
/// which arrives from the OS with no `BuildContext` anywhere in sight.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  // A Listenable, not a watched value. `ref.watch(signedInProvider)` here would
  // rebuild this provider on every sign-in and hand MaterialApp.router a
  // brand new GoRouter — which discards the navigation stack and, because the
  // new router immediately re-evaluates its redirect, spins the tree. That is
  // exactly what GoRouter's refreshListenable exists to avoid: one router for
  // the life of the app, told when to reconsider.
  final signedIn = ValueNotifier(ref.read(signedInProvider));
  ref.onDispose(signedIn.dispose);
  ref.listen(signedInProvider, (_, next) => signedIn.value = next);

  final router = buildRouter(
    // Read through a callback rather than captured once: the router outlives
    // every session, and a bool frozen at construction would send a signed-in
    // user to the welcome screen forever.
    isSignedIn: () => ref.read(signedInProvider),
    refresh: signedIn,
  );
  ref.onDispose(router.dispose);
  return router;
}

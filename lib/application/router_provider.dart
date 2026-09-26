import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../presentation/router.dart';
import 'session_providers.dart';

part 'router_provider.g.dart';

/// The one router instance.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  // A Listenable, not a watched value.
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

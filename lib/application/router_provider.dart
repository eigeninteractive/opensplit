import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../presentation/navigation.dart';
import '../presentation/router.dart';
import 'app_startup.dart';
import 'session_providers.dart';

part 'router_provider.g.dart';

final _routingSessionProvider = Provider<bool?>((ref) {
  if (!ref.watch(appStartupProvider).hasValue) return null;
  return ref.watch(signedInProvider);
});

/// The one router instance.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final sessionChanges = ValueNotifier<bool?>(null);
  ref.onDispose(sessionChanges.dispose);
  ref.listen(_routingSessionProvider, (previous, next) {
    // The first route is already waiting on startup. Later sign-ins and
    // sign-outs refresh the mounted router without replacing it.
    if (previous != null && next != null) sessionChanges.value = next;
  });

  final router = buildRouter(
    redirect: (context, state) {
      final signedIn = ref.read(_routingSessionProvider);
      if (signedIn != null) {
        return redirectAppRoute(state.uri, signedIn: signedIn);
      }
      return ref.read(appStartupProvider.future).then((_) {
        if (!ref.mounted || !context.mounted) return null;
        return redirectAppRoute(
          state.uri,
          signedIn: ref.read(signedInProvider),
        );
      });
    },
    refresh: sessionChanges,
  );
  ref.onDispose(router.dispose);
  return router;
}

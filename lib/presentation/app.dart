import 'dart:async';
import 'dart:developer' as developer;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../application/local_providers.dart';
import '../application/preferences_providers.dart';
import '../application/push_providers.dart';
import '../application/router_provider.dart';
import '../application/session_providers.dart';
import '../application/sync_providers.dart';
import '../data/platform/app_update_service.dart';
import '../data/web/release_updates.dart';
import '../domain/auth_service.dart';
import '../l10n/app_localizations.dart';
import 'dynamic_colors.dart';
import 'theme.dart';
import 'theme_mode.dart';

class OpenSplitApp extends ConsumerStatefulWidget {
  const OpenSplitApp({super.key});

  @override
  ConsumerState<OpenSplitApp> createState() => _OpenSplitAppState();
}

class _OpenSplitAppState extends ConsumerState<OpenSplitApp> {
  /// A messenger above the router, because the update offer outlives whichever
  /// screen happened to be open when Play answered.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  late final AppLifecycleListener _lifecycle;

  /// Long enough that coming back from a five-second background does not ask
  /// Play anything, short enough that a phone left open all day still notices.
  static const _recheckAfter = Duration(hours: 4);

  DateTime? _lastChecked;
  bool _busy = false;
  bool _listeningForSession = false;
  bool _offeredRestart = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);

    // Not in initState directly: Riverpod's scope is inherited state, which is
    // first safe to depend on from didChangeDependencies.
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerUpdate());

    // The web's equivalent of Play's flexible update: the service worker has
    // already downloaded the release, and it only needs a restart.
    watchForNewRelease(() => _offerRestart(restartIntoNewRelease));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listeningForSession) return;
    _listeningForSession = true;

    // Built for each account, which starts its automatic sync.
    ref.listenManual(syncControllerProvider, (_, _) {}, fireImmediately: true);

    // A Google flow that left the page finishes here, on the one launch that is
    // a return from it.
    unawaited(_finishIdentityRedirect());
  }

  /// Completes a redirect sign-in, and parks its refusal if it was refused.
  Future<void> _finishIdentityRedirect() async {
    try {
      await ref.read(accountControllerProvider.notifier).resumeGoogleRedirect();
    } on IdentityAlreadyInUse catch (refusal) {
      ref.read(googleRefusalProvider.notifier).park(refusal);
    } catch (error, stackTrace) {
      // A failed return must not take the launch down with it: the session is
      // simply unchanged, and every other route into the app still works.
      developer.log(
        'Could not finish a Google redirect',
        name: 'opensplit.auth',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Coming back to the foreground asks both questions worth asking: what has
  /// the group been doing, and is there a new version of the app.
  void _onResume() {
    if (ref.read(signedInProvider)) {
      unawaited(ref.read(appDatabaseProvider).noticeWritesElsewhere());
    }
    ref.read(syncControllerProvider.notifier).resumed();
    _offerUpdate();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Takes a waiting update, in whichever of the two ways the release asked
  /// for.
  Future<void> _offerUpdate() async {
    final service = ref.read(appUpdateServiceProvider);
    if (!service.isSupported || _busy) return;

    final last = _lastChecked;
    if (last != null && DateTime.now().difference(last) < _recheckAfter) return;
    _lastChecked = DateTime.now();

    _busy = true;
    try {
      switch (await service.check()) {
        case UpdateUrgency.none:
          return;
        case UpdateUrgency.immediate:
          // Hands the screen to Play, which restarts the app itself once the
          // update lands.
          await service.installNow();
          return;
        case UpdateUrgency.flexible:
          break;
      }

      if (await service.download() != AppUpdateResult.success) return;
      _offerRestart(service.install);
    } catch (_) {
      // Every failure mode here is Play's, and none of them is something the
      // person holding the phone can do anything about.
    } finally {
      _busy = false;
    }
  }

  /// Offers to restart into an update that is downloaded and ready. Once per
  /// launch: the offer stays up until it is taken or dismissed.
  void _offerRestart(VoidCallback restart) {
    final messenger = _messengerKey.currentState;
    if (!mounted || _offeredRestart || messenger == null) return;
    _offeredRestart = true;
    final l10n = AppLocalizations.of(messenger.context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.updateReady),
        // Until it is acted on or dismissed. A four-second toast for
        // something that needs a decision is a toast nobody reads.
        duration: const Duration(days: 1),
        action: SnackBarAction(label: l10n.restart, onPressed: restart),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Establishes a session and registers for push, both silently and both
    // optional.
    ref.watch(pushRegistrationProvider);

    // Material You on Android 12+, when the user has not turned it off.
    // Everywhere else this is null and the seeded scheme is used unchanged.
    final wallpaper = ref.watch(activeWallpaperSchemesProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      // Not the generated `AppLocalizations.localizationsDelegates`: that
      // names flutter_localizations' Material delegates, which material_ui's
      // widgets never read, so they would fall back to hard-coded defaults.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      scaffoldMessengerKey: _messengerKey,
      theme: buildTheme(Brightness.light, wallpaper?.light),
      darkTheme: buildTheme(Brightness.dark, wallpaper?.dark),
      // Both themes are always supplied, and this decides between them.
      // Defaults to following the platform — see [ThemeModeController].
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

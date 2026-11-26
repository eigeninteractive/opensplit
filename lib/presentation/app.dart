import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:material_ui/material_ui.dart';

import '../application/app_startup.dart';
import '../application/backend_providers.dart';
import '../application/ledger_providers.dart';
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
import 'launch_hold.dart';
import 'theme.dart';
import 'theme_mode.dart';
import 'widgets/app_viewport.dart';
import 'widgets/update_required_notice.dart';

class OpenSplitApp extends ConsumerStatefulWidget {
  const OpenSplitApp({super.key});

  @override
  ConsumerState<OpenSplitApp> createState() => _OpenSplitAppState();
}

class _OpenSplitAppState extends ConsumerState<OpenSplitApp>
    with WidgetsBindingObserver {
  /// A messenger above the router, because the update offer outlives whichever
  /// screen happened to be open when Play answered.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  AppLifecycleListener? _lifecycle;

  /// Long enough that coming back from a five-second background does not ask
  /// Play anything, short enough that a phone left open all day still notices.
  static const _recheckAfter = Duration(hours: 4);

  DateTime? _lastChecked;
  bool _busy = false;
  bool _offeredRestart = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(appStartupProvider, (_, startup) {
      if (startup.hasValue && _lifecycle == null) _startSession();
    }, fireImmediately: true);
  }

  void _startSession() {
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(onResume: _onResume);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_offerUpdate());
    });

    // The web's equivalent of Play's flexible update: the service worker has
    // already downloaded the release, and it only needs a restart.
    watchForNewRelease(() => _offerRestart(restartIntoNewRelease));
    // Built for each account, which starts its automatic sync.
    ref.listenManual(syncControllerProvider, (_, _) {}, fireImmediately: true);

    // Your own profile is app state, so it is read at launch and kept current:
    // the Account destination then has it on the frame it is first built,
    // instead of drawing "no name yet" until it arrives. Building that branch
    // early would not do it, because Riverpod pauses providers that only
    // offstage widgets listen to.
    ref.listenManual(myProfileProvider, (_, _) {});

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
    // One UI can change its palette while the app is in the background.
    // Re-read the plugin; brightness and the palette are separate settings.
    ref.invalidate(wallpaperSchemesProvider);
    if (ref.read(signedInProvider)) {
      unawaited(ref.read(appDatabaseProvider).noticeWritesElsewhere());
    }
    ref.read(syncControllerProvider.notifier).resumed();
    _offerUpdate();
  }

  @override
  void didChangePlatformBrightness() {
    ref.invalidate(wallpaperSchemesProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Takes a waiting update, in whichever of the two ways the release asked
  /// for.
  Future<void> _offerUpdate() async {
    final service = ref.read(appUpdateServiceProvider);
    if (!service.isSupported || _busy || ref.read(requiresAppUpdateProvider)) {
      return;
    }

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
    final startup = ref.watch(appStartupProvider);
    final ready = startup.hasValue;
    // Establishes a session and registers for push, both silently and both
    // optional.
    if (ready) ref.watch(pushRegistrationProvider);

    // Material You on Android 12+, when the user has not turned it off.
    // Everywhere else this is null and the seeded scheme is used unchanged.
    final wallpaper = ready ? ref.watch(activeWallpaperSchemesProvider) : null;
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      // The standalone Material widgets read the delegates from material_ui.
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
      themeMode: ready ? ref.watch(themeModeProvider) : ThemeMode.system,
      themeAnimationStyle: kIsWeb || LaunchHold.isHolding
          ? AnimationStyle.noAnimation
          : null,
      routerConfig: router,
      // Order route scopes without measuring their transitional geometry.
      // Each screen retains standard visual reading order within its scope.
      builder: (context, child) => AppViewport(
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Keep listening to platform links beneath the startup screen.
              UpdateRequiredNotice(enabled: ready, child: child!),
              if (startup.hasError)
                BlockSemantics(
                  child: _StartupScreen(
                    onRetry: () {
                      ref.invalidate(appStartupProvider);
                      router.refresh();
                    },
                  ),
                )
              else if (!ready)
                const LaunchPlaceholder(
                  child: BlockSemantics(child: _StartupScreen()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: onRetry == null
            ? CircularProgressIndicator(semanticsLabel: l10n.openingApp)
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.startupFailed, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
                  ],
                ),
              ),
      ),
    );
  }
}

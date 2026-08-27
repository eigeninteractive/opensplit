import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../application/providers.dart';
import '../data/web/boot_hint.dart';
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

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);

    // Not in initState directly: Riverpod's scope is inherited state, which is
    // first safe to depend on from didChangeDependencies.
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerUpdate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listeningForSession) return;
    _listeningForSession = true;

    // The ledger and everything that observes it belong to a session. Starting
    // the scheduler before a restored or newly-created session would construct
    // repositories before there is an account-scoped database to open. Tying
    // its lifetime to this provider also guarantees that signing out cancels
    // every timer and subscription before another account can arrive.
    ref.listenManual(signedInProvider, (_, signedIn) {
      if (signedIn) {
        ref.read(syncSchedulerProvider).start();
      } else {
        ref.invalidate(syncSchedulerProvider);
      }

      // Leaves a note for the next cold start, so the web loader draws the
      // layout this session will actually land on. See [recordSignedIn] — it
      // does nothing on Android, which has a platform splash instead.
      recordSignedIn(signedIn);
    }, fireImmediately: true);
  }

  /// Coming back to the foreground asks both questions worth asking: what has
  /// the group been doing, and is there a new version of the app.
  void _onResume() {
    if (ref.read(signedInProvider)) {
      ref.read(syncSchedulerProvider).resumed();
    }
    _offerUpdate();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Downloads a waiting update in the background and offers to restart.
  ///
  /// Nothing here blocks and nothing here is a wall — the download runs while
  /// the app stays usable, and declining costs nothing. See [AppUpdateService]
  /// for why flexible rather than immediate, and for why this reports nothing
  /// at all on a build Play did not install.
  Future<void> _offerUpdate() async {
    final service = ref.read(appUpdateServiceProvider);
    if (!service.isSupported || _busy) return;

    final last = _lastChecked;
    if (last != null && DateTime.now().difference(last) < _recheckAfter) return;
    _lastChecked = DateTime.now();

    _busy = true;
    try {
      if (!await service.isUpdateAvailable()) return;
      if (await service.download() != AppUpdateResult.success) return;
      if (!mounted) return;

      final messenger = _messengerKey.currentState;
      if (messenger == null) return;
      final l10n = AppLocalizations.of(messenger.context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.updateReady),
          // Until it is acted on or dismissed. A four-second toast for
          // something that needs a decision is a toast nobody reads.
          duration: const Duration(days: 1),
          action: SnackBarAction(
            label: l10n.restart,
            onPressed: service.install,
          ),
        ),
      );
    } catch (_) {
      // Every failure mode here is Play's, and none of them is something the
      // person holding the phone can do anything about. See the logging in
      // AppUpdateService.
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Establishes a session and registers for push, both silently and both
    // optional. Neither blocks a single frame: every screen renders from the
    // local database regardless of how these turn out.
    ref.watch(pushRegistrationProvider);

    // Material You on Android 12+, when the user has not turned it off.
    // Everywhere else this is null and the seeded scheme is used unchanged.
    final wallpaper = ref.watch(activeWallpaperSchemesProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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

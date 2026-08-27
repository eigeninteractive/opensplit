import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/platform/app_update_service.dart';
import '../data/platform/review_prompt.dart';

part 'preferences_providers.g.dart';

/// Overridden in `main` once the platform store has loaded.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) =>
    throw UnimplementedError('sharedPreferencesProvider must be overridden');

/// Play's own update flow, and nothing anywhere else.
@Riverpod(keepAlive: true)
AppUpdateService appUpdateService(Ref ref) => const AppUpdateService();

/// Asking for a store review, rarely and unconditionally.
@Riverpod(keepAlive: true)
ReviewPrompt reviewPrompt(Ref ref) =>
    ReviewPrompt(ref.watch(sharedPreferencesProvider));

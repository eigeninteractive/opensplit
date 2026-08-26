import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Offers the Play Store update a person already has waiting for them.
///
/// Flexible rather than immediate, deliberately. An immediate update is a
/// full-screen blocking flow, and blocking is only honest when a stale client
/// is actively harmful — which for this app would mean a sync change the server
/// no longer accepts, where the symptom is an expense that looks saved and
/// silently is not. Everything short of that, a person should be able to
/// dismiss and keep splitting the bill they opened the app to split.
///
/// The whole thing is Android-and-Play-only, and quietly does nothing anywhere
/// else. Worth knowing before trying to test it: Play answers
/// `updateNotAvailable` for any build it did not install, so this reports
/// nothing under `flutter run`, nothing for a sideloaded APK, and nothing for
/// an AAB you built and installed by hand. It needs a build from a track, with
/// a lower versionCode than the one published.
///
/// The web build needs none of this: `index.html` and `flutter_bootstrap.js`
/// are served no-cache, so a reload is the update.
class AppUpdateService {
  const AppUpdateService();

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether Play is holding an update for this app.
  Future<bool> isUpdateAvailable() async {
    if (!isSupported) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      return info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.flexibleUpdateAllowed;
    } catch (error) {
      // Every reason this fails is a reason not to bother the user: no Play
      // Store, no network, a build Play did not install. None of them is
      // something they can act on, and none of them stops the app working.
      developer.log(
        'Could not ask Play about updates',
        name: 'opensplit.update',
        level: 700,
        error: error,
      );
      return false;
    }
  }

  /// Downloads in the background. Resolves when the download finishes, is
  /// declined, or fails.
  Future<AppUpdateResult> download() => InAppUpdate.startFlexibleUpdate();

  /// Restarts into the downloaded update. Only valid after [download] returned
  /// [AppUpdateResult.success].
  Future<void> install() => InAppUpdate.completeFlexibleUpdate();
}

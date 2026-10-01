import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// How badly a waiting update wants to be installed.
enum UpdateUrgency {
  /// Play is holding nothing, or nothing this build can install.
  none,

  /// Downloads in the background while the app stays usable, and declining
  /// costs nothing. The ordinary case.
  flexible,

  /// A full-screen, blocking flow that the person cannot dismiss.
  immediate,
}

/// Offers the Play Store update a person already has waiting for them.
class AppUpdateService {
  const AppUpdateService();

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The priority at which an update stops being optional.
  static const int _blockingFrom = 4;

  /// What Play is holding for this app, and how much it matters.
  Future<UpdateUrgency> check() async {
    if (!isSupported) return UpdateUrgency.none;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return UpdateUrgency.none;
      }

      // Both halves are required.
      if ((info.updatePriority) >= _blockingFrom &&
          info.immediateUpdateAllowed) {
        return UpdateUrgency.immediate;
      }
      if (info.flexibleUpdateAllowed) return UpdateUrgency.flexible;

      // Available, but neither flow is permitted. Nothing useful to offer.
      return UpdateUrgency.none;
    } catch (error) {
      // Every reason this fails is a reason not to bother the user: no Play
      // Store, no network, a build Play did not install.
      developer.log(
        'Could not ask Play about updates',
        name: 'opensplit.update',
        level: 700,
        error: error,
      );
      return UpdateUrgency.none;
    }
  }

  /// Downloads in the background. Resolves when the download finishes, is
  /// declined, or fails.
  Future<AppUpdateResult> download() => InAppUpdate.startFlexibleUpdate();

  /// Hands the screen to Play until the update is installed.
  Future<AppUpdateResult> installNow() => InAppUpdate.performImmediateUpdate();

  /// Restarts into the downloaded update. Only valid after [download] returned
  /// [AppUpdateResult.success].
  Future<void> install() => InAppUpdate.completeFlexibleUpdate();
}

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:in_app_review/in_app_review.dart';

import 'update_urgency.dart';

export 'update_urgency.dart';

/// Offers the Play Store update a person already has waiting for them.
class AppUpdateService {
  const AppUpdateService();

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The priority at which an ordinary update offer uses the immediate flow.
  static const int _immediateFrom = 4;

  /// What Play is holding for this app, and how much it matters.
  Future<UpdateUrgency> check() async {
    if (!isSupported) return UpdateUrgency.none;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return UpdateUrgency.none;
      }

      // Both halves are required.
      if ((info.updatePriority) >= _immediateFrom &&
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

  /// Updates a build whose API has been retired, regardless of Play priority.
  ///
  /// Canceling keeps saved data readable. If Play cannot run the immediate
  /// flow, its listing lets the user install once the release is available.
  Future<void> updateRequired() async {
    if (isSupported) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability ==
                UpdateAvailability.developerTriggeredUpdateInProgress ||
            (info.updateAvailability == UpdateAvailability.updateAvailable &&
                info.immediateUpdateAllowed)) {
          if (await installNow()) return;
        }
      } catch (error) {
        developer.log(
          'Could not start the Play update',
          name: 'opensplit.update',
          error: error,
        );
      }
    }
    await openStoreListing();
  }

  /// Opens the platform store if an in-app update cannot run.
  Future<void> openStoreListing() => InAppReview.instance.openStoreListing();

  /// Downloads in the background. Resolves when the download finishes, is
  /// declined, or fails.
  Future<bool> download() async =>
      await InAppUpdate.startFlexibleUpdate() == AppUpdateResult.success;

  /// Hands the screen to Play until the update is installed.
  Future<bool> installNow() async =>
      await InAppUpdate.performImmediateUpdate() !=
      AppUpdateResult.inAppUpdateFailed;

  /// Restarts into the downloaded update. Only valid after [download] returned
  /// true.
  Future<void> install() => InAppUpdate.completeFlexibleUpdate();
}

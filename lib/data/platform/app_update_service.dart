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
///
/// Flexible unless the release says otherwise. An immediate update is a
/// full-screen blocking flow, and blocking is only honest when a stale client
/// is actively harmful — which for this app means a sync change the server no
/// longer accepts, where the symptom is an expense that looks saved and
/// silently is not. Everything short of that, a person should be able to
/// dismiss and keep splitting the bill they opened the app to split.
///
/// Which of the two a release gets is decided at upload time rather than here,
/// because it is a property of the release and not of the app: the same build
/// is the urgent one for somebody on an incompatible client and an ordinary one
/// for somebody already current. Play carries it as `inAppUpdatePriority`,
/// 0 to 5, settable only through the Publishing API — see `fastlane/Fastfile`,
/// which is the only place this project sets it.
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

  /// The priority at which an update stops being optional.
  ///
  /// Google's own guidance for the 0-5 scale, and the reason the scale has
  /// numbers rather than a boolean: 4 and 5 are the ones documented as
  /// warranting a blocking flow. Anything below is a release people should be
  /// able to take when it suits them.
  static const int _blockingFrom = 4;

  /// What Play is holding for this app, and how much it matters.
  Future<UpdateUrgency> check() async {
    if (!isSupported) return UpdateUrgency.none;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return UpdateUrgency.none;
      }

      // Both halves are required. A release can be marked urgent and still not
      // be installable that way — Play refuses an immediate flow for an update
      // that is too many versions ahead, among other reasons — and offering a
      // flow that cannot start would leave somebody stuck on a screen with
      // nothing to press.
      if ((info.updatePriority) >= _blockingFrom &&
          info.immediateUpdateAllowed) {
        return UpdateUrgency.immediate;
      }
      if (info.flexibleUpdateAllowed) return UpdateUrgency.flexible;

      // Available, but neither flow is permitted. Nothing useful to offer.
      return UpdateUrgency.none;
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
      return UpdateUrgency.none;
    }
  }

  /// Downloads in the background. Resolves when the download finishes, is
  /// declined, or fails.
  Future<AppUpdateResult> download() => InAppUpdate.startFlexibleUpdate();

  /// Hands the screen to Play until the update is installed.
  ///
  /// Play restarts the app itself on success, so there is usually nothing
  /// after this. It returns if the person backs out, which Play permits even
  /// for an immediate update.
  Future<AppUpdateResult> installNow() => InAppUpdate.performImmediateUpdate();

  /// Restarts into the downloaded update. Only valid after [download] returned
  /// [AppUpdateResult.success].
  Future<void> install() => InAppUpdate.completeFlexibleUpdate();
}

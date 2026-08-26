import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The one notification channel, and the icon that goes with it.
///
/// Shared between the app and the push background isolate, which have no memory
/// in common and would otherwise each declare their own. Two declarations of one
/// channel is not a compile error — it is a channel whose name and importance
/// depend on which isolate happened to create it first, and on Android a
/// channel's settings are fixed at creation and cannot be changed afterwards.
const String activityChannelId = 'opensplit_activity';
const String activityChannelName = 'Group activity';
const String activityChannelDescription =
    'New expenses and settlements in your groups.';

const AndroidNotificationChannel activityChannel = AndroidNotificationChannel(
  activityChannelId,
  activityChannelName,
  description: activityChannelDescription,
  importance: Importance.defaultImportance,
);

/// A dedicated status bar icon, not the launcher icon.
///
/// Android draws these as a silhouette — it reads the alpha channel and paints
/// its own colour through it — so a full-colour launcher icon arrives as a
/// white blob. This one is generated from the brand mark's monochrome layer by
/// tool/brand_icons.dart.
///
/// Named rather than referenced, which means resource shrinking cannot see it:
/// android/app/src/main/res/raw/keep.xml is what stops the release build
/// dropping it and failing to post silently.
const String statusBarIcon = '@drawable/ic_stat_opensplit';

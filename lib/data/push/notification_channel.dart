import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The one notification channel, and the icon that goes with it.
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
const String statusBarIcon = '@drawable/ic_stat_opensplit';

/// Build-time configuration.
library;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

/// Where the OpenSplit backend lives.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8787',
);

/// The one host this app is served from and generates links for.
const String linkHost = String.fromEnvironment(
  'LINK_HOST',
  defaultValue: 'opensplit.eigeninteractive.com',
);

/// The public policy pages, served from the same host as the web app.
String get privacyPolicyUrl => 'https://$linkHost/privacy';
String get termsUrl => 'https://$linkHost/terms';
String get deleteAccountUrl => 'https://$linkHost/delete-account';

/// Where the source lives, and the pages that hang off it.
const String repositoryUrl = String.fromEnvironment(
  'REPOSITORY_URL',
  defaultValue: 'https://github.com/eigeninteractive/opensplit',
);

String get issuesUrl => '$repositoryUrl/issues';
String get licenseUrl => '$repositoryUrl/blob/main/LICENSE';

/// Whether a backend is configured at all.
bool get hasBackend => apiBaseUrl.isNotEmpty;

/// Whether this build points at a developer's own machine.
bool get isLocalBackend =>
    apiBaseUrl.contains('127.0.0.1') ||
    apiBaseUrl.contains('localhost') ||
    apiBaseUrl.contains('10.0.2.2');

/// What is wrong with this build's configuration, if anything.
String? get configurationProblem {
  if (kDebugMode || !isLocalBackend) return null;
  return 'This build points at $apiBaseUrl, which is a developer machine and '
      'is not reachable from a phone or a browser. It was almost certainly '
      'built without --dart-define-from-file=env/app.json.';
}

/// The **web** OAuth client id, from the Google Cloud project.
const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// Firebase Cloud Messaging, for push.
const String fcmApiKey = kIsWeb
    ? String.fromEnvironment('WEB_FCM_API_KEY')
    : String.fromEnvironment('ANDROID_FCM_API_KEY');

const String fcmAppId = kIsWeb
    ? String.fromEnvironment('WEB_FCM_APP_ID')
    : String.fromEnvironment('ANDROID_FCM_APP_ID');

const String fcmSenderId = String.fromEnvironment('FCM_SENDER_ID');
const String fcmProjectId = String.fromEnvironment('FCM_PROJECT_ID');

/// Web push needs a VAPID key in addition to the above.
const String fcmVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

bool get hasPush =>
    fcmApiKey.isNotEmpty &&
    fcmAppId.isNotEmpty &&
    fcmSenderId.isNotEmpty &&
    fcmProjectId.isNotEmpty;

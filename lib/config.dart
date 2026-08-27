/// Build-time configuration.
///
/// Defaults point at a local `supabase start`, so a fresh clone runs against a
/// local stack with no setup. Production values are injected at build time:
///
///   flutter build web --wasm \
///     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///     --dart-define=SUPABASE_PUBLISHABLE_KEY=...
///
/// The publishable key is a public identifier, not a secret — it authorises
/// nothing on its own. Every table is protected by row-level security, which is
/// what actually decides who can read what.
library;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);

const String supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
);

/// The one host this app is served from and generates links for.
///
/// `opensplit.web.app` is the official domain, and the only one. It is where
/// the web app is hosted, the host written into every invite link, and the sole
/// host in the App Links intent filter in AndroidManifest.xml.
///
/// Committing to one is not tidiness. An invite link pasted into a chat outlives
/// the app that made it — someone opens it a year later — so every host the app
/// has ever generated has to keep serving, keep resolving, and keep an
/// assetlinks.json that matches the signing key, forever. A second domain
/// doubles that obligation and buys nothing, because both serve the same build.
///
/// A vanity domain may point here later. If one does, it redirects to this host
/// rather than serving alongside it: a redirect leaves exactly one URL that
/// links are minted with and one origin that owns the stored data, which is what
/// matters when the site is a local-first app whose database is keyed to its
/// origin.
const String linkHost = String.fromEnvironment(
  'LINK_HOST',
  defaultValue: 'opensplit.web.app',
);

/// The public policy pages, served from the same host as the web app.
///
/// Static HTML in `site/privacy/`, `site/terms/` and `site/delete-account/`,
/// deliberately not Flutter routes: Google Play needs the privacy policy and
/// the data-deletion page to be readable by a reviewer, a crawler and somebody
/// who has already uninstalled the app, and a Flutter route is none of those.
///
/// At the host root rather than under `/app/`, which is the whole point of the
/// split: `site/` is plain HTML that needs no engine and no session, and the
/// single-page-app rewrite reaches only `/app/**`, so nothing here can be
/// swallowed by it.
///
/// These are the exact URLs submitted to Play Console under *App content*, so
/// the app and the store listing point at one page rather than two copies.
String get privacyPolicyUrl => 'https://$linkHost/privacy';
String get termsUrl => 'https://$linkHost/terms';
String get deleteAccountUrl => 'https://$linkHost/delete-account';

/// Whether a backend is configured at all.
///
/// The app is fully usable without one — everything is computed locally — so
/// this only gates sync and account features rather than the product.
bool get hasBackend =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

/// Whether this build points at a developer's own machine.
///
/// `127.0.0.1` is the default above, and on a phone it means the phone: a build
/// that keeps it reaches nothing, ever. `10.0.2.2` is the Android emulator's
/// alias for its host, which is right in an emulator and wrong on hardware.
bool get isLocalBackend =>
    supabaseUrl.contains('127.0.0.1') ||
    supabaseUrl.contains('localhost') ||
    supabaseUrl.contains('10.0.2.2');

/// What is wrong with this build's configuration, if anything.
///
/// Exists because of the one mistake this file makes easy. The defaults above
/// are a local `supabase start`, so a fresh clone works with no setup — but
/// they are also what a release build gets when somebody forgets
/// `--dart-define-from-file=env/app.json`, and nothing about the result looks
/// wrong. The app launches, the welcome screen appears, and every request goes
/// to a host that is not there. That shipped once and cost an afternoon of
/// wondering why no accounts were appearing in the dashboard.
///
/// Null when the build is fine, which is every debug build and every release
/// build that was given its defines.
String? get configurationProblem {
  if (kDebugMode || !isLocalBackend) return null;
  return 'This build points at $supabaseUrl, which is a developer machine and '
      'is not reachable from a phone or a browser. It was almost certainly '
      'built without --dart-define-from-file=env/app.json.';
}

/// The **web** OAuth client id, from the Google Cloud project.
///
/// One value for both platforms, and that is not a shortcut: Supabase verifies
/// the ID token's audience against the web client even when the token was
/// minted on Android, so Android passes this same id as `serverClientId`. The
/// Android OAuth client still has to exist in Google Cloud — it is what binds
/// the package name and signing certificate — but its id is never needed here.
///
/// iOS, when it arrives, will need its own; that is the point at which this
/// stops being one constant.
///
/// Empty by default, which hides the Google button entirely rather than
/// offering a sign-in that cannot work.
const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// Firebase Cloud Messaging, for push.
///
/// Empty by default, which disables push entirely rather than crashing at
/// startup. Supplied at build time so no credentials file has to be committed
/// and so a fork can point at its own project:
///
///   --dart-define=FCM_API_KEY=... --dart-define=FCM_APP_ID=... etc.
/// Firebase issues a different API key and a different App ID per platform: a
/// browser key restricted to your domains, an Android key restricted to your
/// package name and signing certificate. Both live in one config file under
/// distinct names and the right pair is chosen here, so there is no build
/// command that can be run with the wrong one.
///
/// `kIsWeb` is a compile-time constant, so this is folded away at build time
/// and the unused branch never reaches the bundle.
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

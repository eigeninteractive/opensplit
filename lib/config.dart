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

import 'package:flutter/foundation.dart' show kIsWeb;

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

/// Whether a backend is configured at all.
///
/// The app is fully usable without one — everything is computed locally — so
/// this only gates sync and account features rather than the product.
bool get hasBackend =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

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

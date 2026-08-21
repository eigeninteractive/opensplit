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

const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321',
);

const String supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
);

/// Host used for invite and group links.
const String linkHost = String.fromEnvironment(
  'LINK_HOST',
  defaultValue: 'opensplit.alturing.dev',
);

/// Whether a backend is configured at all.
///
/// The app is fully usable without one — everything is computed locally — so
/// this only gates sync and account features rather than the product.
bool get hasBackend =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

/// Google OAuth client ids, from a Google Cloud project.
///
/// Empty by default, which hides the Google button entirely rather than
/// offering a sign-in that cannot work. Supply them at build time:
///
///   --dart-define=GOOGLE_SERVER_CLIENT_ID=....apps.googleusercontent.com
///   --dart-define=GOOGLE_WEB_CLIENT_ID=....apps.googleusercontent.com
const String googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
);

const String googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

/// Firebase Cloud Messaging, for push.
///
/// Empty by default, which disables push entirely rather than crashing at
/// startup. Supplied at build time so no credentials file has to be committed
/// and so a fork can point at its own project:
///
///   --dart-define=FCM_API_KEY=... --dart-define=FCM_APP_ID=... etc.
const String fcmApiKey = String.fromEnvironment('FCM_API_KEY');
const String fcmAppId = String.fromEnvironment('FCM_APP_ID');
const String fcmSenderId = String.fromEnvironment('FCM_SENDER_ID');
const String fcmProjectId = String.fromEnvironment('FCM_PROJECT_ID');

/// Web push needs a VAPID key in addition to the above.
const String fcmVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

bool get hasPush =>
    fcmApiKey.isNotEmpty &&
    fcmAppId.isNotEmpty &&
    fcmSenderId.isNotEmpty &&
    fcmProjectId.isNotEmpty;

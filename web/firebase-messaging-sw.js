// Service worker for web push.
//
// Only needed when FCM is configured; without the values below, web push is
// simply off and everything else works. tool/build_web.dart injects these public
// identifiers into the built copy. Never deploy this source file directly.
//
// Chrome, Firefox and Edge deliver push to a normal tab. Safari requires the
// PWA to be installed to the home screen first. iOS is v2.

importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

const config = {
  apiKey: '__WEB_FCM_API_KEY__',
  appId: '__WEB_FCM_APP_ID__',
  messagingSenderId: '__FCM_SENDER_ID__',
  projectId: '__FCM_PROJECT_ID__',
};

firebase.initializeApp(config);
const messaging = firebase.messaging();

// Deliberately empty. Messages are data-only, and the notification text is
// produced by the app in Dart after it has pulled the delta — a banner drawn
// here would be a second implementation of currency formatting and each
// recipient's share, drifting from the app with nobody noticing.
messaging.onBackgroundMessage(function () {});

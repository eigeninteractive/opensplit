// Service worker for web push.
//
// Only needed when FCM is configured; without the values below, web push is
// simply off and everything else works. Fill these in from the Firebase console
// (they are public identifiers, not secrets) or delete this file.
//
// Chrome, Firefox and Edge deliver push to a normal tab. Safari requires the
// PWA to be installed to the home screen first. iOS is v2.

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

const config = {
  apiKey: '',
  appId: '',
  messagingSenderId: '',
  projectId: '',
};

if (config.projectId) {
  firebase.initializeApp(config);
  const messaging = firebase.messaging();

  // Deliberately empty. Messages are data-only, and the notification text is
  // produced by the app in Dart after it has pulled the delta — a banner drawn
  // here would be a second implementation of currency formatting and each
  // recipient's share, drifting from the app with nobody noticing.
  messaging.onBackgroundMessage(function () {});
}

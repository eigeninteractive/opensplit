import 'package:web/web.dart' as web;

/// Sends the browser to Google, and does not come back.
void navigateBrowser(String url) => web.window.location.assign(url);

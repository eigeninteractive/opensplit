import 'package:web/web.dart' as web;

/// Sends the browser to Google, and does not come back.
///
/// `assign` rather than `replace`: the page the person left is worth having in
/// the back stack, because backing out of Google's account picker should return
/// them to the invite they tapped rather than to whatever preceded it.
void navigateBrowser(String url) => web.window.location.assign(url);

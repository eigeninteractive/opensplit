/// Offering a newer release of the web app than the one this tab is running.
library;

export 'release_updates_stub.dart'
    if (dart.library.js_interop) 'release_updates_web.dart';

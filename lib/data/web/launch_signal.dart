/// Telling the page outside Flutter that the app is on screen.
library;

export 'launch_signal_stub.dart'
    if (dart.library.js_interop) 'launch_signal_web.dart';

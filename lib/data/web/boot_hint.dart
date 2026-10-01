/// What the web loader is allowed to assume before any Dart has run.
library;

export 'boot_hint_stub.dart' if (dart.library.js_interop) 'boot_hint_web.dart';

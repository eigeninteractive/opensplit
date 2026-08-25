/// What the web loader is allowed to assume before any Dart has run.
///
/// The loading skeleton in `web/index.html` paints long before the engine
/// exists, so anything it wants to know has to already be in the browser. This
/// records the one fact that changes what it should draw.
///
/// A no-op everywhere but the web, where the conditional import swaps in the
/// real implementation.
library;

export 'boot_hint_stub.dart' if (dart.library.js_interop) 'boot_hint_web.dart';

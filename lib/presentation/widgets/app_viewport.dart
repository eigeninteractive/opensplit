import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

import '../../data/web/browser_theme.dart';

/// Keeps the browser safe area and system bars in sync with the app theme.
class AppViewport extends StatefulWidget {
  /// Wraps the app's navigator and the overlays it presents.
  const AppViewport({super.key, required this.child});

  /// The navigator and its app-level wrappers.
  final Widget child;

  @override
  State<AppViewport> createState() => _AppViewportState();
}

class _AppViewportState extends State<AppViewport> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb) {
      final scheme = Theme.of(context).colorScheme;
      updateBrowserTheme(scheme.surface, scheme.primary, scheme.brightness);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (kIsWeb) {
      // Give routes, dialogs and sheets one shared safe viewport.
      return ColoredBox(
        color: scheme.surface,
        child: SafeArea(child: widget.child),
      );
    }

    // App bars set their own style. This covers screens without an app bar.
    final statusBarBrightness = ThemeData.estimateBrightnessForColor(
      scheme.surface,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: scheme.surface,
        statusBarBrightness: statusBarBrightness,
        statusBarIconBrightness: statusBarBrightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: widget.child,
    );
  }
}

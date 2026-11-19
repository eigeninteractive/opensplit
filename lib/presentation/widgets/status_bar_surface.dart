import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';

/// Chooses system status bar icons for a surface that extends behind them.
///
/// Use for surfaces without a Material app bar, which sets its own style.
class StatusBarSurface extends StatelessWidget {
  const StatusBarSurface({
    super.key,
    this.backgroundColor,
    required this.child,
  });

  /// The painted color behind the icons. Defaults to the scaffold background.
  final Color? backgroundColor;

  /// The content that paints behind the status bar.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;
    final color = backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    final brightness = ThemeData.estimateBrightnessForColor(color);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: color,
        statusBarBrightness: brightness,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: child,
    );
  }
}

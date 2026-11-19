import 'dart:ui';

import 'package:web/web.dart' as web;

/// Gives browser chrome and the page background the active theme's colours.
void updateBrowserTheme(Color surface, Color primary, Brightness brightness) {
  final surfaceHex = _hex(surface);
  final themeColor =
      web.document.getElementById('app-theme-color') as web.HTMLMetaElement?;
  // The first matching tag wins. Once Flutter knows the user's theme, it
  // takes precedence over the browser's colour-scheme hint used at launch.
  themeColor
    ?..content = surfaceHex
    ..removeAttribute('media');

  final root = web.document.documentElement as web.HTMLElement?;
  root?.style
    ?..setProperty('--surface', surfaceHex)
    ..setProperty('--primary', _hex(primary))
    ..setProperty('color-scheme', brightness.name);
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

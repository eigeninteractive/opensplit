// Generates the two brand icons flutter_launcher_icons cannot produce.
//
// Run after `dart run flutter_launcher_icons`, which overwrites the favicon:
//
//     dart run tool/brand_icons.dart
//
// flutter_launcher_icons builds every output from one `image_path`, and that
// file — assets/icon/icon.png — is deliberately opaque, because iOS and legacy
// Android launcher icons cannot carry an alpha channel. That is right for a
// home screen and wrong for both of the icons here, so each is built from the
// transparent artwork beside it instead.
//
// Both are pinned by tests, so regenerating the launcher icons and forgetting
// this step fails rather than quietly shipping the wrong thing.
import 'dart:io';

import 'package:image/image.dart';

void main() {
  _favicon();
  _notificationIcon();
}

/// The browser tab icon.
///
/// The generator's favicon step is a plain resize of the opaque master, which
/// puts a pale lilac tile in the tab strip rather than letting the mark sit on
/// the browser's own colour — and in a dark theme that tile is the brightest
/// thing on the row.
///
/// Written at 32px rather than the 16 the generator uses: every browser
/// downsamples, none upsamples, and a tab on a HiDPI display asks for more
/// than 16.
void _favicon() {
  // 0.88 of the box, which is more than an app icon gets. Nothing crops a
  // favicon, so padding would only make a mark that is already a few pixels
  // across smaller still.
  final icon = _fill(_read('assets/icon/icon-foreground.png'), 0.88, 32);
  File('web/favicon.png').writeAsBytesSync(encodePng(icon));
  stdout.writeln('brand_icons: web/favicon.png at 32px');
}

/// The status bar icon for a notification.
///
/// Android draws these as a silhouette: it reads the alpha channel and paints
/// its own colour through it, so the artwork has to be one shape on
/// transparency and nothing else. A launcher icon in this slot comes out as a
/// white blob, which is why Android's guidance is not to use one.
///
/// Built from the monochrome layer, which is already that shape. It is trimmed
/// first because that layer is drawn for an adaptive icon, where the mark fills
/// less than half the canvas so the launcher has room to crop — dropped into a
/// 24dp status bar unchanged, it would be a dot.
///
/// Written white. Recent Android tints the silhouette itself and the colour is
/// then irrelevant, but on older releases it is used as-is, and white is the
/// only value that reads on the notification shade.
void _notificationIcon() {
  final source = _read('assets/icon/icon-monochrome.png');

  // The generated densities, in the buckets Android resolves between.
  const densities = <String, int>{
    'mdpi': 24,
    'hdpi': 36,
    'xhdpi': 48,
    'xxhdpi': 72,
    'xxxhdpi': 96,
  };

  for (final density in densities.entries) {
    // Slightly tighter than the favicon: Android already insets the icon
    // within the status bar slot, so the glyph should reach its own edges.
    final icon = _fill(source, 0.92, density.value);

    for (final pixel in icon) {
      // Alpha carries the shape; the colour underneath is replaced outright,
      // since the monochrome layer ships black and black is invisible here.
      pixel
        ..r = 255
        ..g = 255
        ..b = 255;
    }

    final path =
        'android/app/src/main/res/drawable-${density.key}/$notificationIcon.png';
    File(path).writeAsBytesSync(encodePng(icon));
  }

  stdout.writeln(
    'brand_icons: $notificationIcon at ${densities.values.join('/')}px',
  );
}

/// The drawable name the app asks for at runtime.
///
/// `ic_stat_` is Android's own convention for a status bar icon. It is also a
/// string looked up by name, which no static analysis can follow — hence the
/// keep rule in `android/app/src/main/res/raw/keep.xml`, without which resource
/// shrinking drops it and notifications silently stop appearing.
const notificationIcon = 'ic_stat_opensplit';

Image _read(String path) {
  final decoded = decodePng(File(path).readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('brand_icons: could not decode $path');
    exit(1);
  }
  return decoded;
}

/// [source] trimmed to its ink, centred in a square, and resized to [size].
///
/// [coverage] is the share of the result the ink should span.
Image _fill(Image source, double coverage, int size) {
  final trimmed = trim(source, mode: TrimMode.transparent);
  final longest = trimmed.width > trimmed.height
      ? trimmed.width
      : trimmed.height;
  final box = (longest / coverage).round();

  final canvas = Image(width: box, height: box, numChannels: 4);
  compositeImage(
    canvas,
    trimmed,
    dstX: (box - trimmed.width) ~/ 2,
    dstY: (box - trimmed.height) ~/ 2,
  );

  return copyResize(
    canvas,
    width: size,
    height: size,
    interpolation: Interpolation.cubic,
  );
}

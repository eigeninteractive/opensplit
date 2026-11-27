// Packages listing text, artwork and Cider notes in Fastlane supply's layout.
// Run from the repository root; the output must be a new or empty directory:
//
//     dart run tool/play_metadata.dart --output=build/play-metadata

import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:image/image.dart' as image;

import 'release_notes.dart';

/// Packages listing assets locally, without contacting Google Play.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('output', help: 'New or empty Fastlane metadata directory.')
    ..addFlag(
      'listing-only',
      help: 'Package the listing without app release notes.',
      negatable: false,
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(arguments);
    if (options.flag('help')) {
      stdout.writeln('Package the Play listing and optional release notes.');
      stdout.writeln(parser.usage);
      return;
    }
    final output = options.option('output');
    if (output == null || output.trim().isEmpty || options.rest.isNotEmpty) {
      throw const FormatException(
        'Supply --output and no positional arguments.',
      );
    }
    writePlayMetadata(
      source: Directory.current,
      output: Directory(output),
      notes: options.flag('listing-only')
          ? null
          : await currentPlayReleaseNotes(),
    );
    stdout.writeln('Play metadata ready: ${Directory(output).absolute.path}');
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
  } catch (error) {
    stderr.writeln('Play metadata failed: $error');
    exitCode = 1;
  }
}

const _screenshots = [
  'screenshot-1-groups.png',
  'screenshot-2-expenses.png',
  'screenshot-3-balances.png',
  'screenshot-4-add-expense.png',
  'screenshot-5-insights.png',
];

/// Writes the en-US listing and, when supplied, app release [notes].
///
/// Validates all sources before writing. A nonempty [output] is refused so
/// stale screenshots cannot be uploaded alongside the current set. Images
/// keep the source bytes shared with F-Droid.
///
/// Throws if any source is missing, unreadable, incorrectly sized or contains
/// transparency, or if listing text or [notes] exceeds Play's limits.
void writePlayMetadata({
  required Directory source,
  required Directory output,
  String? notes,
}) {
  if (notes != null && (notes.trim().isEmpty || notes.length > playLimit)) {
    throw const FormatException('Play notes must contain 1–500 characters.');
  }
  if (output.existsSync() && output.listSync().isNotEmpty) {
    throw FileSystemException(
      'Play metadata output must be empty',
      output.path,
    );
  }
  final listing = '${source.path}/fastlane/metadata/android/en-US';
  final text = <String, String>{
    for (final (name, limit) in [
      ('title', 30),
      ('short_description', 80),
      ('full_description', 4000),
    ])
      '$name.txt': _readText(
        File('$listing/$name.txt'),
        limit: limit,
        singleLine: name != 'full_description',
      ),
  };
  final assets = <String, List<int>>{
    for (final (path, size) in [
      ('images/icon.png', (512, 512)),
      ('images/featureGraphic.jpg', (1024, 500)),
      for (final name in _screenshots)
        ('images/phoneScreenshots/$name', (1080, 1920)),
    ])
      path: _readImage(File('$listing/$path'), size: size),
  };
  for (final MapEntry(:key, :value) in assets.entries) {
    final target = File('${output.path}/en-US/$key');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(value);
  }
  if (notes != null) text['changelogs/default.txt'] = notes;
  for (final MapEntry(:key, :value) in text.entries) {
    final target = File('${output.path}/en-US/$key');
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(value);
  }
}

String _readText(File file, {required int limit, required bool singleLine}) {
  final value = file.readAsStringSync().trim();
  if (value.isEmpty || value.runes.length > limit) {
    throw FormatException('${file.path} must contain 1–$limit characters.');
  }
  if (singleLine && (value.contains('\n') || value.contains('\r'))) {
    throw FormatException('${file.path} must be a single line.');
  }
  return value;
}

Uint8List _readImage(File file, {required (int, int) size}) {
  final bytes = file.readAsBytesSync();
  final decoded = file.path.endsWith('.png')
      ? image.decodePng(bytes)
      : image.decodeJpg(bytes);
  if (decoded == null) {
    throw FormatException('Unreadable Play image: ${file.path}');
  }
  final (width, height) = size;
  if (decoded.width != width || decoded.height != height) {
    throw FormatException('Expected $width × $height image: ${file.path}');
  }
  if (decoded.hasAlpha &&
      decoded.any((pixel) => pixel.a != decoded.maxChannelValue)) {
    throw FormatException('Play artwork must be opaque: ${file.path}');
  }
  return bytes;
}

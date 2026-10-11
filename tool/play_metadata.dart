// Packages the committed artwork and Cider notes in Fastlane supply's layout.
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
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(arguments);
    if (options.flag('help')) {
      stdout.writeln('Package the Play artwork and release notes.');
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
      notes: await currentPlayReleaseNotes(),
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

/// Writes the complete en-US listing artwork and notes for one release.
///
/// Validates all sources before writing. A nonempty [output] is refused so
/// stale screenshots cannot be uploaded alongside the current set. Only the
/// icon is resized; feature art and screenshots keep their exact source bytes.
///
/// Throws if any source is missing, unreadable, incorrectly sized or contains
/// transparency, or if [notes] is empty or exceeds Play's limit.
void writePlayMetadata({
  required Directory source,
  required Directory output,
  required String notes,
}) {
  if (notes.trim().isEmpty || notes.length > playLimit) {
    throw const FormatException('Play notes must contain 1–500 characters.');
  }
  if (output.existsSync() && output.listSync().isNotEmpty) {
    throw FileSystemException(
      'Play metadata output must be empty',
      output.path,
    );
  }
  final icon = _readImage(File('${source.path}/assets/icon/icon.png'));
  if (icon.decoded.width != icon.decoded.height) {
    throw const FormatException('The source Play icon must be square.');
  }
  final assets = <String, List<int>>{
    'images/icon.png': image.encodePng(
      image
          .copyResize(
            icon.decoded,
            width: 512,
            height: 512,
            interpolation: image.Interpolation.average,
          )
          .convert(numChannels: 3),
    ),
    'images/featureGraphic.jpg': _readImage(
      File('${source.path}/site/store/feature-graphic.jpg'),
      size: (1024, 500),
    ).bytes,
    for (final name in _screenshots)
      'images/phoneScreenshots/$name': _readImage(
        File('${source.path}/site/store/$name'),
        size: (1080, 1920),
      ).bytes,
  };
  for (final MapEntry(:key, :value) in assets.entries) {
    final target = File('${output.path}/en-US/$key');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(value);
  }
  final changelog = File('${output.path}/en-US/changelogs/default.txt');
  changelog.parent.createSync(recursive: true);
  changelog.writeAsStringSync(notes);
}

({Uint8List bytes, image.Image decoded}) _readImage(
  File file, {
  (int, int)? size,
}) {
  final bytes = file.readAsBytesSync();
  final decoded = file.path.endsWith('.png')
      ? image.decodePng(bytes)
      : image.decodeJpg(bytes);
  if (decoded == null) {
    throw FormatException('Unreadable Play image: ${file.path}');
  }
  if (size case (final width, final height)) {
    if (decoded.width != width || decoded.height != height) {
      throw FormatException('Expected $width × $height image: ${file.path}');
    }
  }
  if (decoded.hasAlpha &&
      decoded.any((pixel) => pixel.a != decoded.maxChannelValue)) {
    throw FormatException('Play artwork must be opaque: ${file.path}');
  }
  return (bytes: bytes, decoded: decoded);
}

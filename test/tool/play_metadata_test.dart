import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:test/test.dart';

import '../../tool/play_metadata.dart';

void main() {
  late Directory temporary;
  late Directory source;
  late Directory output;
  const notes = '• A refreshed design and easier custom splits.';
  final artwork = [
    'assets/icon/icon.png',
    'site/store/feature-graphic.jpg',
    'site/store/screenshot-1-groups.png',
    'site/store/screenshot-2-expenses.png',
    'site/store/screenshot-3-balances.png',
    'site/store/screenshot-4-add-expense.png',
    'site/store/screenshot-5-insights.png',
  ];

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('opensplit-play-metadata-');
    source = Directory('${temporary.path}/source');
    output = Directory('${temporary.path}/metadata');
    for (final path in artwork) {
      final target = File('${source.path}/$path');
      target.parent.createSync(recursive: true);
      File(path).copySync(target.path);
    }
  });

  tearDown(() {
    temporary.deleteSync(recursive: true);
    expect(temporary.existsSync(), isFalse);
  });

  test('packages current artwork in supply order without changing sources', () {
    writePlayMetadata(source: source, output: output, notes: notes);

    final locale = '${output.path}/en-US';
    expect(File('$locale/changelogs/default.txt').readAsStringSync(), notes);
    final icon = image.decodePng(
      File('$locale/images/icon.png').readAsBytesSync(),
    )!;
    expect((icon.width, icon.height, icon.hasAlpha), (512, 512, false));
    expect(
      File('$locale/images/featureGraphic.jpg').readAsBytesSync(),
      File('site/store/feature-graphic.jpg').readAsBytesSync(),
    );
    final screenshots =
        Directory(
            '$locale/images/phoneScreenshots',
          ).listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(screenshots.length, 5);
    for (final (index, screenshot) in screenshots.indexed) {
      expect(
        screenshot.readAsBytesSync(),
        File(artwork[index + 2]).readAsBytesSync(),
      );
    }
    for (final path in artwork) {
      expect(
        File('${source.path}/$path').readAsBytesSync(),
        File(path).readAsBytesSync(),
      );
    }
    expect(output.listSync(recursive: true).whereType<File>().length, 8);
  });

  test('a missing screenshot fails before any output is written', () {
    File('${source.path}/${artwork.last}').deleteSync();

    expect(
      () => writePlayMetadata(source: source, output: output, notes: notes),
      throwsA(isA<FileSystemException>()),
    );
    expect(output.existsSync(), isFalse);
  });

  test('refuses a feature graphic with incorrect dimensions', () {
    File(
      '${source.path}/site/store/feature-graphic.jpg',
    ).writeAsBytesSync(image.encodeJpg(image.Image(width: 100, height: 50)));

    expect(
      () => writePlayMetadata(source: source, output: output, notes: notes),
      throwsA(isA<FormatException>()),
    );
    expect(output.existsSync(), isFalse);
  });

  test('refuses a transparent source icon', () {
    File('${source.path}/assets/icon/icon.png').writeAsBytesSync(
      image.encodePng(image.Image(width: 64, height: 64, numChannels: 4)),
    );

    expect(
      () => writePlayMetadata(source: source, output: output, notes: notes),
      throwsA(isA<FormatException>()),
    );
    expect(output.existsSync(), isFalse);
  });

  test('refuses stale output without deleting it', () {
    final stale = File('${output.path}/en-US/images/phoneScreenshots/old.png');
    stale.parent.createSync(recursive: true);
    stale.writeAsStringSync('old artwork');

    expect(
      () => writePlayMetadata(source: source, output: output, notes: notes),
      throwsA(isA<FileSystemException>()),
    );
    expect(stale.readAsStringSync(), 'old artwork');
  });

  for (final invalid in ['', ' ' * 10, 'x' * 501]) {
    test('refuses invalid notes of length ${invalid.length}', () {
      expect(
        () => writePlayMetadata(source: source, output: output, notes: invalid),
        throwsA(isA<FormatException>()),
      );
      expect(output.existsSync(), isFalse);
    });
  }

  test('CLI packages this checkout with Cider release notes', () async {
    final result = await Process.run('dart', [
      'run',
      'tool/play_metadata.dart',
      '--output=${output.path}',
    ]);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    final generated = File(
      '${output.path}/en-US/changelogs/default.txt',
    ).readAsStringSync();
    expect(generated, startsWith('• '));
    expect(generated.length, lessThanOrEqualTo(500));
    expect('${result.stdout}', contains('Play metadata ready:'));
  });

  test('CLI explains required arguments and fails without an output', () async {
    final result = await Process.run('dart', [
      'run',
      'tool/play_metadata.dart',
    ]);

    expect(result.exitCode, 64);
    expect('${result.stderr}', contains('--output'));
    expect(output.existsSync(), isFalse);
  });
}

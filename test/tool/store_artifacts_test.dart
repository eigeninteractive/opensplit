@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory fixture;
  final script = File('tool/store_artifacts.dart').absolute.path;
  final packageConfig = File('.dart_tool/package_config.json').absolute.path;

  setUpAll(() {
    fixture = Directory.systemTemp.createTempSync('opensplit-store-check-');
    final manifest =
        jsonDecode(File('site/store/artifacts.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final path in [
      'site/store/artifacts.json',
      ...Map<String, dynamic>.from(manifest['inputs'] as Map).keys,
      ...Map<String, dynamic>.from(manifest['outputs'] as Map).keys,
    ]) {
      final target = File('${fixture.path}/$path');
      target.parent.createSync(recursive: true);
      File(path).copySync(target.path);
    }
  });

  tearDownAll(() {
    fixture.deleteSync(recursive: true);
    expect(fixture.existsSync(), isFalse);
  });

  Future<ProcessResult> check() => Process.run('dart', [
    '--packages=$packageConfig',
    script,
    '--check',
  ], workingDirectory: fixture.path);

  test('the complete capture passes without a renderer or a network', () async {
    final result = await check();
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('changing a screen invalidates the capture', () async {
    final source = File('${fixture.path}/lib/main.dart');
    final original = source.readAsBytesSync();
    addTearDown(() => source.writeAsBytesSync(original));
    source.writeAsStringSync('// changed screen\n', mode: FileMode.append);
    final result = await check();
    expect(result.exitCode, 1);
    expect(result.stderr, contains('lib/main.dart'));
  });

  test(
    'missing or replaced feature graphics cannot pass on screenshots alone',
    () async {
      final graphic = File('${fixture.path}/site/store/feature-graphic.jpg');
      final original = graphic.readAsBytesSync();
      addTearDown(() => graphic.writeAsBytesSync(original));
      graphic.deleteSync();
      expect((await check()).exitCode, 1);
      graphic.writeAsStringSync('old or independently replaced graphic');
      final result = await check();
      expect(result.exitCode, 1);
      expect(result.stderr, contains('site/store/feature-graphic.jpg'));
    },
  );
}

/// Rebuilds every screenshot and its derivatives, or verifies their provenance.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _manifestPath = 'site/store/artifacts.json';
const _outputs = [
  'site/store/screenshot-1-groups.png',
  'site/store/screenshot-2-expenses.png',
  'site/store/screenshot-3-balances.png',
  'site/store/screenshot-4-add-expense.png',
  'site/store/screenshot-5-insights.png',
  'site/store/web-app.png',
  'site/store/og-card.png',
  'site/store/feature-graphic.jpg',
  'site/email/wordmark.png',
];

Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--check')) {
    stderr.writeln('Usage: dart run tool/store_artifacts.dart [--check]');
    exitCode = 64;
    return;
  }
  final inputs = await _inputs();
  if (args.contains('--check')) {
    final manifest = File(_manifestPath);
    if (!manifest.existsSync()) return _stale(['missing $_manifestPath']);
    final saved =
        jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
    final differences = <String>[];
    for (final (key, current) in [
      ('inputs', inputs),
      ('outputs', await _hashes(_outputs)),
    ]) {
      final old = Map<String, String>.from(saved[key] as Map);
      for (final path in {...old.keys, ...current.keys}) {
        if (old[path] != current[path]) differences.add(path);
      }
    }
    if (differences.isNotEmpty) return _stale(differences);
    stdout.writeln(
      'Store screenshots, feature graphic and previews match their sources.',
    );
    return;
  }

  // The manifest is written only after every producer succeeds. A partial
  // capture or an independently replaced image therefore fails --check.
  if (!await _run('flutter', ['test', 'tool/screenshots_test.dart'])) return;
  if (!await _run('python3', ['tool/store_graphics.py'])) return;
  final outputs = await _hashes(_outputs);
  if (outputs.values.any((value) => value == 'missing')) {
    return _stale(['missing output']);
  }
  final after = await _inputs();
  if (jsonEncode(inputs) != jsonEncode(after)) {
    return _stale(['sources changed during rendering']);
  }
  await File(_manifestPath).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'version': 1, 'inputs': inputs, 'outputs': outputs})}\n',
  );
  stdout.writeln('Updated all store artwork and $_manifestPath.');
}

void _stale(List<String> paths) {
  stderr.writeln(
    'Store artwork is stale or incomplete:\n${paths.map((path) => '  $path').join('\n')}',
  );
  stderr.writeln('Run: dart run tool/store_artifacts.dart');
  exitCode = 1;
}

Future<bool> _run(String executable, List<String> args) async {
  final process = await Process.start(
    executable,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  final status = await process.exitCode;
  if (status != 0) exitCode = status;
  return status == 0;
}

Future<Map<String, String>> _inputs() async {
  // Conservative by design: renderer dependencies can move between layers.
  // Hash source content rather than platform-dependent raster comparisons.
  final paths = [
    'build.yaml',
    'pubspec.yaml',
    'pubspec.lock',
    'tool/screenshots_test.dart',
    'tool/store_graphics.py',
    'tool/store_artifacts.dart',
    'test/harness.dart',
    'test/fixtures/android_wallpaper.dart',
    'test/data/server_reference_data.dart',
    '.github/workflows/ci.yml',
    for (final directory in ['lib', 'assets', 'packages/opensplit_api/lib'])
      await for (final entity in Directory(directory).list(recursive: true))
        if (entity is File && !entity.path.split('/').last.startsWith('.'))
          entity.path,
  ]..sort();
  return _hashes(paths);
}

Future<Map<String, String>> _hashes(List<String> paths) async => {
  for (final path in paths)
    path: await File(path).exists()
        ? (await sha256.bind(File(path).openRead()).first).toString()
        : 'missing',
};

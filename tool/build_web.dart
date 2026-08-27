// Builds the production web bundle and injects public deployment identifiers
// into the two service workers.
//
// The bundle is two things in one tree. `site/` is plain static HTML — the
// landing page, the privacy policy, the terms — and it is served from the host
// root, where it needs no engine, no session and no JavaScript to be readable
// by a person, a crawler or an OAuth reviewer. The Flutter client is built
// underneath it at `/app/`.
//
// --base-href is what keeps the Dart side unaware of the split: Flutter's path
// URL strategy resolves routes after the base, so go_router still sees
// `/g/123` while the browser shows `/app/g/123`, and no route constant moves.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('config', defaultsTo: 'env/app.json')
    ..addOption('build-id')
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(args);
    if (options.rest.isNotEmpty) {
      throw FormatException('Unexpected arguments: ${options.rest.join(' ')}');
    }
    if (options.flag('help')) {
      stdout.writeln('Build the static site and Flutter /app bundle.');
      stdout.writeln(parser.usage);
      return;
    }
    await _build(options.option('config')!, options.option('build-id'));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 64;
  } catch (error) {
    stderr.writeln('Web build failed: $error');
    exitCode = 1;
  }
}

Future<void> _build(String configPath, String? requestedBuildId) async {
  final buildId = await _buildId(requestedBuildId);

  await _run('dart', [
    'run',
    'tool/verify_config.dart',
    '--config=$configPath',
  ]);
  // Cleared wholesale rather than letting the Flutter build clear its own
  // output: it only owns build/web/app, so a file left at the root by an
  // earlier layout would survive and outrank the page meant to be there.
  final output = Directory('build/web');
  if (output.existsSync()) output.deleteSync(recursive: true);

  await _run('flutter', [
    'build',
    'web',
    '--wasm',
    '--no-web-resources-cdn',
    '--release',
    '--base-href=/app/',
    // Absolute, which is what --output requires.
    '--output=${Directory.current.path}/build/web/app',
    '--dart-define-from-file=$configPath',
  ]);

  final config =
      jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
  _copyInto(Directory('site'), output);
  final cacheId = finalizeWebBundle(output, config, buildId: buildId);

  stdout.writeln('Production web bundle ready (build $cacheId).');
  stdout.writeln('  /      static site from site/');
  stdout.writeln('  /app/  Flutter client');
}

/// Injects public push configuration and a complete, content-addressed cache.
///
/// Run only after Flutter and the static site have been copied to [output].
/// A dirty rebuild at the same commit must still get a new offline cache.
String finalizeWebBundle(
  Directory output,
  Map<String, dynamic> config, {
  required String buildId,
}) {
  _validateId(buildId);
  final app = Directory('${output.path}/app');
  _replace('${app.path}/firebase-messaging-sw.js', {
    '__WEB_FCM_API_KEY__': '${config['WEB_FCM_API_KEY']}',
    '__WEB_FCM_APP_ID__': '${config['WEB_FCM_APP_ID']}',
    '__FCM_SENDER_ID__': '${config['FCM_SENDER_ID']}',
    '__FCM_PROJECT_ID__': '${config['FCM_PROJECT_ID']}',
  });
  final resources = <String, File>{};
  for (final file in app.listSync(recursive: true).whereType<File>()) {
    final path = file.path.substring(app.path.length + 1);
    if (path == 'sw.js' ||
        path == 'flutter_service_worker.js' ||
        path.endsWith('.map') ||
        path.split('/').any((part) => part.startsWith('.'))) {
      continue;
    }
    resources[path] = file;
  }
  for (final name in ['favicon.png', 'favicon.svg']) {
    final file = File('${output.path}/$name');
    if (file.existsSync()) resources['/$name'] = file;
  }
  final icons = Directory('${output.path}/icons');
  if (icons.existsSync()) {
    for (final file in icons.listSync(recursive: true).whereType<File>()) {
      resources[file.path.substring(output.path.length)] = file;
    }
  }
  for (final required in [
    'index.html',
    'flutter_bootstrap.js',
    'main.dart.js',
    'sqlite3.wasm',
    'drift_worker.js',
  ]) {
    if (!resources.containsKey(required)) {
      throw StateError('Incomplete Flutter bundle: missing $required');
    }
  }
  final paths = resources.keys.toList()..sort();
  final hashes = paths.map(
    (path) => '$path:${sha256.convert(resources[path]!.readAsBytesSync())}',
  );
  final workerSource = File('${app.path}/sw.js').readAsStringSync();
  final digest = sha256
      .convert(utf8.encode('${hashes.join('\n')}\n$workerSource'))
      .toString();
  final cacheId = '$buildId-${digest.substring(0, 16)}';
  _replace('${app.path}/sw.js', {
    '__OPEN_SPLIT_BUILD_ID__': cacheId,
    '__OPEN_SPLIT_RESOURCES__': jsonEncode(paths),
  });

  for (final path in [
    '${app.path}/firebase-messaging-sw.js',
    '${app.path}/sw.js',
  ]) {
    final contents = File(path).readAsStringSync();
    if (RegExp(r'__[A-Z0-9_]+__').hasMatch(contents)) {
      throw StateError('$path contains an unresolved build placeholder.');
    }
  }
  return cacheId;
}

/// Copies [from] over [to], including dotfiles.
///
/// `.well-known/assetlinks.json` is a dotfile directory and is what makes
/// Android App Links verify, so a copy that quietly skips it fails in the way
/// that is hardest to notice: links keep working, they just open a browser.
void _copyInto(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    final relative = entity.path.substring(from.path.length + 1);
    final target = '${to.path}/$relative';
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      Directory(File(target).parent.path).createSync(recursive: true);
      entity.copySync(target);
    }
  }
}

Future<String> _buildId(String? requested) async {
  final candidate = requested ?? Platform.environment['GITHUB_SHA'];
  if (candidate != null && candidate.isNotEmpty) return _validateId(candidate);

  final result = await Process.run('git', ['rev-parse', '--short=12', 'HEAD']);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    exit(result.exitCode);
  }
  return _validateId('${result.stdout}'.trim());
}

String _validateId(String value) {
  if (!RegExp(r'^[A-Za-z0-9._-]{7,64}$').hasMatch(value)) {
    throw FormatException('Invalid build id: $value');
  }
  return value;
}

Future<void> _run(String executable, List<String> arguments) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) exit(code);
}

void _replace(String path, Map<String, String> replacements) {
  final file = File(path);
  var contents = file.readAsStringSync();
  for (final MapEntry(:key, :value) in replacements.entries) {
    contents = contents.replaceAll(key, value);
  }
  file.writeAsStringSync(contents);
}

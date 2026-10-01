// Refreshes web/drift_worker.js and web/sqlite3.wasm from the drift release
// that pubspec.lock resolves.
//
//     dart run tool/update_drift_web_assets.dart
//     dart run tool/update_drift_web_assets.dart --check
//
// Drift opens the web database by loading both files at runtime, so they are
// committed rather than built. They have to match the Dart side: the worker is
// drift compiled to JavaScript, and it speaks a protocol to the page that
// changes between releases. Drift publishes the pair with each release, built
// together, which is why both come from there and nowhere else.
//
// `--check` is what CI runs, so a `pub upgrade` that moved drift without this
// step fails in the same pull request rather than in a browser.

import 'dart:io';

const _assets = ['drift_worker.js', 'sqlite3.wasm'];

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final version = _lockedDriftVersion();
  final stale = <String>[];

  for (final name in _assets) {
    final released = await _download(
      'https://github.com/simolus3/drift/releases/download/drift-$version/$name',
    );
    final committed = File('web/$name');
    if (committed.existsSync() &&
        _same(committed.readAsBytesSync(), released)) {
      continue;
    }
    stale.add(name);
    if (!check) committed.writeAsBytesSync(released);
  }

  if (stale.isEmpty) {
    stdout.writeln('web/ has drift $version\'s ${_assets.join(' and ')}.');
  } else if (check) {
    _fail(
      '${stale.map((name) => 'web/$name').join(' and ')} differ from drift '
      '$version\'s release. Run: dart run tool/update_drift_web_assets.dart',
    );
  } else {
    stdout.writeln('Replaced ${stale.join(' and ')} with drift $version\'s.');
  }
}

/// The drift version pubspec.lock resolves, which is what the app compiles.
String _lockedDriftVersion() {
  final lock = File('pubspec.lock').readAsStringSync();
  final match = RegExp(
    r'^  drift:\n(?:    .*\n)*?    version: "([^"]+)"',
    multiLine: true,
  ).firstMatch(lock);
  return match?.group(1) ?? _fail('pubspec.lock does not resolve drift.');
}

Future<List<int>> _download(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != HttpStatus.ok) {
      _fail('GET $url answered ${response.statusCode}.');
    }
    return [for (final chunk in await response.toList()) ...chunk];
  } finally {
    client.close();
  }
}

bool _same(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Never _fail(String message) {
  stderr.writeln('error: $message');
  exit(1);
}

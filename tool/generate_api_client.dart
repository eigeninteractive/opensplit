// Regenerates packages/opensplit_api from the server's Zod schemas.
//
//     dart run tool/generate_api_client.dart
//     dart run tool/generate_api_client.dart --check
//
// There are three artefacts in a row and this command owns the whole chain:
// the Zod schemas in server/src/schemas/ are the source, docs/openapi.json is
// derived from them, and this package is derived from that. Regenerating the
// contract first is not a convenience — it is what stops a fresh-looking
// client being built from a stale checked-in spec, which would look right in
// review and be wrong on a device.
//
// The generated sources are committed, and `--check` is what CI runs, so a
// wire change that skipped this step shows up as a reviewable Dart diff in the
// same pull request that changed the schema rather than days later.
//
// Generation happens off to the side and is only installed once every fallible
// step has succeeded. The committed client is never left half-written by a
// generator that failed in the middle.
//
// Toolchain: Node (the generator ships as a Java program with an npm launcher),
// a JDK on PATH, and Dart. The JDK comes from the environment — CI's
// setup-java, or a local install; nothing here installs one.

import 'dart:io';

const _config = 'tool/openapi_dart.yaml';
const _output = 'packages/opensplit_api';
const _spec = 'docs/openapi.json';

/// Files this repository owns inside a directory the generator otherwise
/// rewrites wholesale. They are listed in `.openapi-generator-ignore`, and
/// staged before generation so the generator sees that list and honours it.
const _ours = [
  '.openapi-generator-ignore',
  'analysis_options.yaml',
  'pubspec.yaml',
];

/// Build artefacts that appear once anything resolves the package, plus the
/// generator's own bookkeeping. None is derived from the spec, so none belongs
/// in a drift comparison — and the generator version, which is the only part of
/// that bookkeeping worth recording, is pinned in `openapitools.json` where it
/// can be reviewed and bumped deliberately. Without that pin a new generator
/// release would rewrite this package on somebody's machine and fail CI with a
/// diff nobody asked for.
const _notOutput = ['.dart_tool', 'pubspec.lock', '.openapi-generator'];

Future<void> main(List<String> args) async {
  final check = args.contains('--check');

  await _requireJava();
  await _emitSpec();

  final stage = Directory.systemTemp.createTempSync('opensplit_api').path;
  for (final name in _ours) {
    final source = File('$_output/$name');
    if (!source.existsSync()) {
      _fail(
        '$_output/$name is missing. It is hand-owned and the generator will not recreate it.',
      );
    }
    source.copySync('$stage/$name');
  }

  await _run('npx', [
    '--yes',
    '@openapitools/openapi-generator-cli',
    'generate',
    '-c',
    _config,
    '-o',
    stage,
  ], what: 'OpenAPI Generator');

  // The json_serializable output is committed alongside the models it belongs
  // to. A consumer never runs build_runner on a dependency, so a package whose
  // `part 'x.g.dart'` directives point at nothing does not compile.
  await _run('dart', ['pub', 'get'], workingDirectory: stage, what: 'pub get');
  await _run(
    'dart',
    ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
    workingDirectory: stage,
    what: 'build_runner',
  );

  // The generator's output is not `dart format` clean, and these sources are
  // committed. Formatting here rather than excluding the package from the
  // repository's format check also normalises the generator's own line
  // breaking, so a generator upgrade diffs as real changes instead of reflow.
  await _run('dart', ['format', '$stage/lib'], what: 'dart format');

  if (check) {
    final diff = await Process.run('diff', [
      '-r',
      '-q',
      ..._notOutput.expand((name) => ['-x', name]),
      _output,
      stage,
    ]);
    if (diff.exitCode != 0) {
      stderr.writeln('The committed API client is out of date:\n');
      stderr.writeln(diff.stdout);
      stderr.writeln(
        'Run `dart run tool/generate_api_client.dart` and commit the result.',
      );
      exit(1);
    }
    stdout.writeln('The committed API client matches $_spec.');
    return;
  }

  // Installed only now, with every fallible step behind us.
  final installed = Directory('$_output/lib');
  if (installed.existsSync()) installed.deleteSync(recursive: true);
  Directory('$stage/lib').renameSync('$_output/lib');

  // build.yaml tells build_runner which builders to run over this package. It
  // is generated, not ours, but it has to travel with the sources so anybody
  // regenerating from a clean checkout gets the same serializers.
  File('$stage/build.yaml').copySync('$_output/build.yaml');
  stdout.writeln('Generated $_output from $_spec.');
}

/// Regenerates the contract from the Zod schemas that define it.
Future<void> _emitSpec() async {
  if (!Directory('server/node_modules').existsSync()) {
    _fail(
      'server/node_modules is missing. Run `npm ci` in server/ first — the contract is generated from the Zod schemas there.',
    );
  }
  await _run(
    'npm',
    ['run', '--silent', 'openapi'],
    workingDirectory: 'server',
    what: 'OpenAPI emission',
  );
}

Future<void> _requireJava() async {
  final result = await Process.run('java', ['-version'], runInShell: true);
  if (result.exitCode != 0) {
    _fail(
      'Java is required by OpenAPI Generator. Install a JDK, or set JAVA_HOME.',
    );
  }
}

Future<void> _run(
  String command,
  List<String> arguments, {
  String? workingDirectory,
  required String what,
}) async {
  final result = await Process.run(
    command,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    stderr.writeln('$what failed:\n');
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    exit(result.exitCode);
  }
}

Never _fail(String message) {
  stderr.writeln('error: $message');
  exit(1);
}

// Regenerates packages/opensplit_api from docs/openapi.json.
//
// Run from the repository root:
//
//     dart run tool/generate_api_client.dart
//     dart run tool/generate_api_client.dart --check
//
// `--check` regenerates into a scratch directory and compares, which is what
// CI runs. The generated client is committed, so a wire change that skips this
// step shows up in review as a change to the client rather than as a runtime
// surprise on a device — the same discipline drift_schemas/ already gets.
//
// The generator is OpenAPI Generator's `dart` target, run through npx because
// it is a Java tool with a Node launcher and this repo already has Node for
// the Worker. It needs a JDK on PATH; the Android toolchain in `release`
// already pulls one in.

import 'dart:io';

const _config = 'tool/openapi_dart.yaml';
const _output = 'packages/opensplit_api';
const _spec = 'docs/openapi.json';

/// Files this repository owns inside a directory the generator otherwise
/// rewrites wholesale. Listed in `.openapi-generator-ignore` so the generator
/// leaves them alone, and restored here after a `--check` run builds the tree
/// from scratch.
const _ours = ['.openapi-generator-ignore', 'analysis_options.yaml'];

Future<void> main(List<String> args) async {
  final check = args.contains('--check');

  if (!File(_spec).existsSync()) {
    stderr.writeln(
      'No $_spec. Run `npm run openapi` in server/ first — the client is '
      'generated from the contract, and the contract is generated from the '
      'Zod schemas.',
    );
    exit(1);
  }

  final target = check ? Directory.systemTemp.createTempSync('opensplit_api').path : _output;

  for (final name in _ours) {
    final source = File('$_output/$name');
    if (source.existsSync()) {
      Directory(target).createSync(recursive: true);
      source.copySync('$target/$name');
    }
  }

  final result = await Process.run('npx', [
    '--yes',
    '@openapitools/openapi-generator-cli',
    'generate',
    '-c',
    _config,
    '-o',
    target,
  ], runInShell: true);

  if (result.exitCode != 0) {
    stderr.writeln(result.stdout);
    stderr.writeln(result.stderr);
    exit(result.exitCode);
  }

  if (!check) {
    stdout.writeln('Generated $_output from $_spec.');
    return;
  }

  // Build artefacts, not output: `.dart_tool` and a lockfile appear once
  // anything has resolved the package, and neither is generated from the spec.
  final diff = await Process.run('diff', ['-r', '-q', '-x', '.dart_tool', '-x', 'pubspec.lock', _output, target]);
  if (diff.exitCode != 0) {
    stderr.writeln('The committed API client is out of date:\n');
    stderr.writeln(diff.stdout);
    stderr.writeln('Run `dart run tool/generate_api_client.dart` and commit the result.');
    exit(1);
  }

  stdout.writeln('The committed API client matches $_spec.');
}

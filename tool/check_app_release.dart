// Checks committed app changes against the PR base or previous main commit.
// Cider owns the version and changelog; this only enforces when to release.

import 'dart:io';

import 'package:cider/cider.dart';

import 'release_notes.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/check_app_release.dart <base-ref>');
    exitCode = 64;
    return;
  }
  try {
    stdout.writeln(await checkAppRelease(args.single));
  } catch (error) {
    stderr.writeln('App release check failed: $error');
    exitCode = 1;
  }
}

/// Requires a newer, finalized Cider release when app inputs differ from [base].
///
/// Compares [base] with HEAD in [workingDirectory], or the current repository.
/// Website, backend, documentation, tests and release tooling are exempt.
Future<String> checkAppRelease(String base, {String? workingDirectory}) async {
  Future<String> git(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'git',
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    return '${result.stdout}';
  }

  // Without rename detection, moving an app file out of the app still counts
  // as deleting an app input. NUL delimiters preserve spaces in filenames.
  final paths = (await git([
    'diff',
    '--no-renames',
    '--name-only',
    '-z',
    base,
    'HEAD',
    '--',
  ])).split('\u0000').where(_isAppInput);
  if (paths.isEmpty) return 'No app changes; no Android release required.';

  final temporary = await Directory.systemTemp.createTemp('opensplit-release-');
  try {
    await File(
      '${temporary.path}/pubspec.yaml',
    ).writeAsString(await git(['show', '$base:pubspec.yaml']));
    final previous = await _cider(temporary.path, ['version']);
    final root = workingDirectory ?? Directory.current.path;
    final current = await _cider(root, ['version']);
    if (!_isNewerStableVersion(previous, current)) {
      throw FormatException(
        'App changes require a stable version newer than $previous; '
        'found $current. Run dart run cider bump patch (or minor/major), '
        'then dart run cider release.',
      );
    }
    playReleaseNotes(await _cider(root, ['describe', current, '--only-body']));
    if ((await _cider(root, ['describe', '--only-body'])).isNotEmpty) {
      throw const FormatException(
        'Finalize Unreleased with dart run cider release before merging.',
      );
    }
    return 'App release: $previous -> $current.';
  } finally {
    await temporary.delete(recursive: true);
  }
}

bool _isAppInput(String path) =>
    const [
      'lib/',
      'assets/',
      'android/',
      'web/',
      'packages/opensplit_api/lib/',
      'service_worker/src/',
    ].any(path.startsWith) ||
    const {
      'pubspec.yaml',
      'pubspec.lock',
      'build.yaml',
      'l10n.yaml',
      'flutter_launcher_icons.yaml',
      'flutter_native_splash.yaml',
      'packages/opensplit_api/pubspec.yaml',
      'packages/opensplit_api/pubspec.lock',
      'packages/opensplit_api/build.yaml',
      'service_worker/build.ts',
      'service_worker/package.json',
      'service_worker/pnpm-lock.yaml',
      'service_worker/pnpm-workspace.yaml',
      'service_worker/tsconfig.json',
      'service_worker/tsconfig.node.json',
    }.contains(path);

bool _isNewerStableVersion(String previous, String current) {
  final stable = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$');
  if (!stable.hasMatch(previous) || !stable.hasMatch(current)) return false;
  final before = previous.split('.').map(int.parse).toList();
  final after = current.split('.').map(int.parse).toList();
  for (var index = 0; index < 3; index++) {
    if (after[index] != before[index]) return after[index] > before[index];
  }
  return false;
}

Future<String> _cider(String root, List<String> arguments) async {
  final output = BufferChannel();
  final errors = BufferChannel();
  final status = await CiderCli(
    console: Console(out: output, err: errors),
  ).run(['--project-root', root, ...arguments]);
  if (status != 0) throw FormatException(errors.buffer.toString().trim());
  return output.buffer.toString().trim();
}

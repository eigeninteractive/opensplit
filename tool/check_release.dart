/// Validates a production release against its PR or pre-push base using Cider.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:cider/cider.dart';

import 'release_notes.dart';

/// Checks release metadata without modifying files or contacting Play.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('base-ref', help: 'Git revision before this PR or main push.')
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(arguments);
    if (options.flag('help')) {
      stdout.writeln(
        'Validate a new stable version and finalized Cider notes.',
      );
      stdout.writeln(parser.usage);
      return;
    }
    final base = options.option('base-ref');
    if (base == null || base.isEmpty || options.rest.isNotEmpty) {
      throw const FormatException(
        'Supply --base-ref and no positional arguments.',
      );
    }
    await checkRelease(baseRef: base, directory: Directory.current);
    stdout.writeln(
      'Release version and Cider changelog are ready for production.',
    );
  } on FormatException catch (error) {
    stderr.writeln('Release check failed: ${error.message}');
    stderr.writeln(
      'Update from main, then run dart run cider log, dart run cider bump '
      'patch (or minor/major), and dart run cider release.',
    );
    stderr.writeln(parser.usage);
    exitCode = 1;
  } catch (error) {
    stderr.writeln('Release check failed: $error');
    exitCode = 1;
  }
}

/// Requires a stable version newer than [baseRef] with finalized Play notes.
///
/// Published changelog sections must remain unchanged. Git reads the base
/// metadata into a disposable directory; Cider parses both projects through
/// its public CLI API. Missing history or malformed metadata fails closed.
Future<void> checkRelease({
  required String baseRef,
  required Directory directory,
}) async {
  final base = await _git(directory, [
    'rev-parse',
    '--verify',
    '--end-of-options',
    '$baseRef^{commit}',
  ]);
  final previous = await Directory.systemTemp.createTemp('opensplit-release-');
  try {
    for (final path in ['pubspec.yaml', 'CHANGELOG.md']) {
      await File(
        '${previous.path}/$path',
      ).writeAsString(await _git(directory, ['show', '$base:$path']));
    }
    await _checkProjects(directory, previous);
  } finally {
    await previous.delete(recursive: true);
  }
}

Future<void> _checkProjects(Directory current, Directory previous) async {
  final version = await _cider(current, ['version']);
  final oldVersion = await _cider(previous, ['version']);
  if (!_isNewer(version, oldVersion)) {
    throw FormatException('Version $version must be newer than $oldVersion.');
  }
  final versions = await _cider(current, ['list', '--include-unreleased']);
  if (versions.split('\n').first != version) {
    throw FormatException(
      'Finalize $version as the latest non-yanked changelog release; '
      'leave no Unreleased entries.',
    );
  }
  playReleaseNotes(await _cider(current, ['describe', version, '--only-body']));
  await _checkHistory(current, previous);
}

bool _isNewer(String version, String oldVersion) {
  final current = _stableVersion(version);
  final previous = _stableVersion(oldVersion);
  for (var index = 0; index < current.length; index++) {
    if (current[index] != previous[index]) {
      return current[index] > previous[index];
    }
  }
  return false;
}

List<int> _stableVersion(String version) {
  if (!RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  ).hasMatch(version)) {
    throw FormatException(
      'Use a stable major.minor.patch version without prerelease or +build: '
      '$version. CI owns the build number.',
    );
  }
  return version.split('.').map(int.parse).toList();
}

Future<void> _checkHistory(Directory current, Directory previous) async {
  final history = await _cider(previous, ['list', '--include-yanked']);
  for (final version in history.split('\n').where((line) => line.isNotEmpty)) {
    final original = await _cider(previous, ['describe', version]);
    if (await _cider(current, ['describe', version]) != original) {
      throw FormatException('Keep the published $version changelog unchanged.');
    }
  }
}

Future<String> _cider(Directory directory, List<String> arguments) async {
  final output = BufferChannel();
  final errors = BufferChannel();
  final status = await CiderCli(
    console: Console(out: output, err: errors),
  ).run(['--project-root', directory.absolute.path, ...arguments]);
  if (status != 0) {
    throw FormatException('Cider ${arguments.join(' ')}: ${errors.buffer}');
  }
  return output.buffer.toString().trim();
}

Future<String> _git(Directory directory, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  if (result.exitCode != 0) {
    throw FormatException('Git ${arguments.join(' ')}: ${result.stderr}');
  }
  return '${result.stdout}'.trim();
}

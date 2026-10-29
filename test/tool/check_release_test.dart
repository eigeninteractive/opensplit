import 'dart:io';

import 'package:cider/cider.dart';
import 'package:test/test.dart';

import '../../tool/check_release.dart';

void main() {
  final script = File('tool/check_release.dart').absolute.path;
  final packages = File('.dart_tool/package_config.json').absolute.path;
  late Directory repository;
  late String base;
  const history = '''
## 4.1.0 - 2026-10-16
### Fixed
- Existing release notes.
''';

  Future<ProcessResult> git(List<String> arguments) =>
      Process.run('git', arguments, workingDirectory: repository.path);

  Future<ProcessResult> cli(List<String> arguments) => Process.run('dart', [
    '--packages=$packages',
    script,
    ...arguments,
  ], workingDirectory: repository.path);

  void writeVersion(String version) => File(
    '${repository.path}/pubspec.yaml',
  ).writeAsStringSync('name: release_fixture\nversion: $version\n');

  void writeChangelog(String section) => File(
    '${repository.path}/CHANGELOG.md',
  ).writeAsStringSync('# Changelog\n\n$section\n$history');

  Future<void> validate() => checkRelease(baseRef: base, directory: repository);

  setUp(() async {
    repository = Directory.systemTemp.createTempSync('opensplit-release-test-');
    await git(['init', '--quiet']);
    await git(['config', 'user.email', 'release@example.test']);
    await git(['config', 'user.name', 'Release Test']);
    writeVersion('4.1.0');
    File('${repository.path}/CHANGELOG.md').writeAsStringSync(history);
    await git(['add', '.']);
    final commit = await git(['commit', '--quiet', '-m', 'Previous release']);
    expect(commit.exitCode, 0, reason: '${commit.stderr}');
    base = '${(await git(['rev-parse', 'HEAD'])).stdout}'.trim();
    writeVersion('4.1.1');
    writeChangelog('''
## 4.1.1 - 2026-10-29
### Fixed
- The next release fixes a bug.
''');
  });

  tearDown(() => repository.deleteSync(recursive: true));

  test(
    'accepts a real Cider log, bump and release without changing files',
    () async {
      writeVersion('4.1.0');
      File('${repository.path}/CHANGELOG.md').writeAsStringSync(history);
      for (final arguments in [
        ['log', 'fixed', 'The next release fixes a bug.'],
        ['bump', 'patch'],
        ['release'],
      ]) {
        final status = await CiderCli(
          console: Console(out: BufferChannel(), err: BufferChannel()),
        ).run(['--project-root', repository.path, ...arguments]);
        expect(status, 0);
      }
      final before = '${(await git(['diff'])).stdout}';

      await validate();

      expect('${(await git(['diff'])).stdout}', before);
    },
  );

  for (final version in ['4.1.0', '4.0.9', '3.9.9']) {
    test('rejects unchanged or lower version $version', () async {
      writeVersion(version);

      await expectLater(validate(), throwsA(isA<FormatException>()));
    });
  }

  for (final version in ['4.1.1-beta.1', '4.1.1+12']) {
    test('rejects production prerelease or build suffix $version', () async {
      writeVersion(version);

      await expectLater(validate(), throwsA(isA<FormatException>()));
    });
  }

  for (final version in ['4.2.0', '5.0.0', '4.10.0']) {
    test('accepts numeric minor and major bumps: $version', () async {
      writeVersion(version);
      writeChangelog('''
## $version - 2026-10-29
### Added
- A new feature.
''');

      await validate();
    });
  }

  test('rejects a bump without cider release', () async {
    writeChangelog('## Unreleased\n### Fixed\n- A fix.\n');

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test(
    'rejects leftover Unreleased notes beside a finalized version',
    () async {
      final file = File('${repository.path}/CHANGELOG.md');
      file.writeAsStringSync(
        '## Unreleased\n### Fixed\n- Another fix.\n${file.readAsStringSync()}',
      );

      await expectLater(validate(), throwsA(isA<FormatException>()));
    },
  );

  test('rejects an empty finalized section', () async {
    writeChangelog('## 4.1.1 - 2026-10-29\n');

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test('rejects a mismatched changelog version', () async {
    writeChangelog('## 4.2.0 - 2026-10-29\n### Added\n- A feature.\n');

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test('rejects a yanked release', () async {
    writeChangelog('''
## 4.1.1 - 2026-10-29 [YANKED]
### Fixed
- A fix.
''');

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test('rejects duplicate version sections', () async {
    final file = File('${repository.path}/CHANGELOG.md');
    file.writeAsStringSync('${file.readAsStringSync()}\n$history');

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test('rejects a version already represented in base history', () async {
    await git(['add', 'CHANGELOG.md']);
    await git(['commit', '--quiet', '-m', 'Existing release section']);
    base = '${(await git(['rev-parse', 'HEAD'])).stdout}'.trim();
    await expectLater(
      validate(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('already in the base history'),
        ),
      ),
    );
  });

  test('rejects changing published history', () async {
    final file = File('${repository.path}/CHANGELOG.md');
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst('Existing release', 'Rewritten'),
    );

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test('rejects missing published history', () async {
    writeChangelog('');
    File('${repository.path}/CHANGELOG.md').writeAsStringSync('''
## 4.1.1 - 2026-10-29
### Fixed
- A fix.
''');

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test('rejects a release note that Play cannot accept', () async {
    writeChangelog('## 4.1.1 - 2026-10-29\n### Fixed\n- ${'x' * 501}\n');

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test('fails closed when the comparison revision is unavailable', () async {
    base = 'missing-main-history';

    await expectLater(validate(), throwsA(isA<FormatException>()));
  });

  test(
    'CLI succeeds for a finalized release and fails for a missing bump',
    () async {
      final valid = await cli(['--base-ref=$base']);
      expect(valid.exitCode, 0, reason: '${valid.stderr}');
      expect('${valid.stdout}', contains('ready for production'));

      writeVersion('4.1.0');
      final invalid = await cli(['--base-ref=$base']);
      expect(invalid.exitCode, isNot(0));
      expect('${invalid.stderr}', contains('must be newer'));
    },
  );

  test('CLI documents the base argument and refuses to omit it', () async {
    final help = await cli(['--help']);
    expect(help.exitCode, 0);
    expect('${help.stdout}', contains('--base-ref'));

    final missing = await cli([]);
    expect(missing.exitCode, isNot(0));
    expect('${missing.stderr}', contains('Supply --base-ref'));
  });

  test(
    'compares with the supplied pre-push revision across multiple commits',
    () async {
      await git(['add', '.']);
      await git(['commit', '--quiet', '-m', 'New version']);
      File('${repository.path}/extra.txt').writeAsStringSync('More code');
      await git(['add', '.']);
      await git(['commit', '--quiet', '-m', 'Another commit in this push']);

      await validate();
      await expectLater(
        checkRelease(baseRef: 'HEAD^', directory: repository),
        throwsA(isA<FormatException>()),
      );
    },
  );
}

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/check_app_release.dart';

void main() {
  late Directory repository;
  late String base;

  Future<String> git(List<String> arguments) async {
    final result = await Process.run('git', [
      '-c',
      'user.name=Release check test',
      '-c',
      'user.email=release-check@example.invalid',
      '-c',
      'commit.gpgsign=false',
      ...arguments,
    ], workingDirectory: repository.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  Future<void> write(String path, String contents) async {
    final file = File('${repository.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<void> commit() async {
    await git(['add', '--all']);
    await git(['commit', '--quiet', '-m', 'Fixture change']);
  }

  Future<void> version(String value, {String? changelog}) async {
    await write('pubspec.yaml', 'name: fixture\nversion: $value\n');
    if (changelog != null) await write('CHANGELOG.md', changelog);
    await commit();
  }

  Future<String> check() =>
      checkAppRelease(base, workingDirectory: repository.path);

  String notes(String value) =>
      '# Changelog\n\n## $value - 2026-10-30\n'
      '### Fixed\n- Clearer group names.\n';

  setUp(() async {
    repository = await Directory.systemTemp.createTemp('app-release-test-');
    await git(['init', '--quiet', '--initial-branch=main']);
    await write('lib/app with spaces.dart', '// Original app.\n');
    await version('1.2.3', changelog: notes('1.2.3'));
    base = await git(['rev-parse', 'HEAD']);
  });

  tearDown(() async => repository.delete(recursive: true));

  test('backend, website, docs, tests and tooling need no app bump', () async {
    for (final path in [
      'server/src/index.ts',
      'server/package.json',
      'site/index.html',
      'site/store/artifacts.json',
      'README.md',
      'docs/openapi.json',
      'test/app_test.dart',
      'tool/build_web.dart',
      '.github/workflows/release.yml',
      'fastlane/Fastfile',
      'packages/opensplit_api/README.md',
      'service_worker/test/push.test.ts',
    ]) {
      await write(path, 'Updated.\n');
    }
    await commit();

    expect(await check(), contains('No app changes'));
  });

  for (final path in [
    'lib/presentation/theme.dart',
    'assets/brand/mark-mono.svg',
    'android/app/src/main/AndroidManifest.xml',
    'web/index.html',
    'packages/opensplit_api/lib/api.dart',
    'packages/opensplit_api/pubspec.yaml',
    'service_worker/src/sw.ts',
    'service_worker/pnpm-lock.yaml',
    'pubspec.lock',
    'flutter_native_splash.yaml',
  ]) {
    test('$path requires an app bump', () async {
      await write(path, 'Updated.\n');
      await commit();

      await expectLater(check(), throwsA(isA<FormatException>()));
    });
  }

  test('patch, minor and major bumps pass with finalized notes', () async {
    for (final next in ['1.2.4', '1.10.0', '2.0.0']) {
      await git(['reset', '--hard', base]);
      await version(next, changelog: notes(next));

      expect(await check(), 'App release: 1.2.3 -> $next.');
      expect(await git(['status', '--porcelain']), isEmpty);
    }
  });

  test('unchanged, lower, prerelease and build-only versions fail', () async {
    for (final next in ['1.2.3', '1.2.2', '1.2.4-beta.1', '1.2.3+2']) {
      await git(['reset', '--hard', base]);
      await write('lib/new.dart', '// Changed app.\n');
      await version(next, changelog: notes(next));

      await expectLater(check(), throwsA(isA<FormatException>()));
    }
  });

  test('a bump without cider release fails', () async {
    await version('1.2.4');

    await expectLater(
      check(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('1.2.4 not found'),
        ),
      ),
    );
  });

  test('a released section with no notes fails', () async {
    await version('1.2.4', changelog: '# Changelog\n## 1.2.4 - 2026-10-30\n');

    await expectLater(
      check(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('no entries'),
        ),
      ),
    );
  });

  test('unfinalized notes fail even if the version has older notes', () async {
    await version(
      '1.2.4',
      changelog:
          '# Changelog\n## Unreleased\n### Fixed\n- Pending app change.\n\n'
          '${notes('1.2.4').replaceFirst('# Changelog\n', '')}',
    );

    await expectLater(
      check(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Finalize Unreleased'),
        ),
      ),
    );
  });

  test('moving an app file into docs still requires a release', () async {
    await Directory('${repository.path}/docs').create();
    await File(
      '${repository.path}/lib/app with spaces.dart',
    ).rename('${repository.path}/docs/app with spaces.dart');
    await commit();

    await expectLater(check(), throwsA(isA<FormatException>()));
  });

  test('a bump already merged into main cannot cover another PR', () async {
    await version('1.2.4', changelog: notes('1.2.4'));
    base = await git(['rev-parse', 'HEAD']);
    await write('lib/another.dart', '// Another app change.\n');
    await commit();

    await expectLater(check(), throwsA(isA<FormatException>()));
  });

  test('an unavailable base fails instead of skipping validation', () async {
    await expectLater(
      checkAppRelease('missing-ref', workingDirectory: repository.path),
      throwsA(isA<ProcessException>()),
    );
  });
}

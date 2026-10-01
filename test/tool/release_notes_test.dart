import 'dart:io';

import 'package:test/test.dart';

import '../../tool/release_notes.dart';

void main() {
  group('playReleaseNotes', () {
    test('drops the headings and turns each entry into a bullet line', () {
      const markdown = '''
### Added
- Groups can be archived.
### Fixed
- Totals no longer round twice.''';

      expect(
        playReleaseNotes(markdown),
        '• Groups can be archived.\n• Totals no longer round twice.',
      );
    });

    test('removes inline Markdown, which Play would show literally', () {
      const markdown =
          '- **Faster** sync for `large` groups, see [the issue](https://x.test/1) '
          'and _snake_case_ stays.';

      expect(
        playReleaseNotes(markdown),
        '• Faster sync for large groups, see the issue and snake_case stays.',
      );
    });

    test('keeps whole entries within the limit and counts the rest', () {
      final markdown = [
        for (var i = 0; i < 40; i++) '- Entry number $i, a sentence.',
      ].join('\n');

      final notes = playReleaseNotes(markdown);

      expect(notes.length, lessThanOrEqualTo(playLimit));
      expect(notes, startsWith('• Entry number 0, a sentence.\n'));
      final kept = '•'.allMatches(notes).length;
      expect(notes, endsWith('…and ${40 - kept} more.'));
    });

    test('fills the limit exactly when the entries fit', () {
      final entry = '- ${'x' * 98}';
      final markdown = List.filled(5, entry).join('\n');

      // Five lines of "• " plus 98 characters, and four newlines: 504.
      expect(playReleaseNotes(markdown, limit: 504), isNot(contains('more')));
      expect(playReleaseNotes(markdown, limit: 503), endsWith('…and 1 more.'));
    });

    test('refuses a section with no entries', () {
      expect(
        () => playReleaseNotes('### Added\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses an entry that cannot fit on its own', () {
      expect(
        () => playReleaseNotes('- ${'x' * playLimit}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('the repository', () {
    // `cider bump` without `cider release` leaves pubspec.yaml naming a version
    // the changelog does not have. Every build would then ship as a version
    // nobody wrote down, so this fails the pull request instead.
    test(
      'CHANGELOG.md has a section for the version in pubspec.yaml',
      () async {
        final version = await Process.run('dart', ['run', 'cider', 'version']);
        expect(version.exitCode, 0, reason: '${version.stderr}');

        final section = await Process.run('dart', [
          'run',
          'cider',
          'describe',
          '${version.stdout}'.trim(),
        ]);
        expect(
          section.exitCode,
          0,
          reason:
              'Version ${'${version.stdout}'.trim()} has no section in '
              'CHANGELOG.md. Run `dart run cider release` after a bump.',
        );
      },
    );

    test('this tree has release notes Play would accept', () async {
      final result = await Process.run('dart', [
        'run',
        'tool/release_notes.dart',
      ]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final notes = '${result.stdout}';
      expect(notes, startsWith('• '));
      expect(notes.length, lessThanOrEqualTo(playLimit));
    });
  });
}

// Prints the "What's new" text Play shows testers for this build, from
// CHANGELOG.md:
//
//     dart run tool/release_notes.dart
//
// A build carries what is under Unreleased, since that is what it has that
// the last version did not. Right after a version is cut there is nothing
// there, and the build is that version's, so it carries that section instead.
//
// cider reads the changelog, so this agrees with `cider describe` by
// construction rather than by a second parser. What is left is turning its
// Markdown into the plain text Play displays, within Play's limit.

import 'dart:io';

/// The longest release note Play accepts, per language.
const playLimit = 500;

Future<void> main() async {
  try {
    final unreleased = await _describe();
    final body = unreleased.trim().isNotEmpty
        ? unreleased
        : await _describe(await _cider(['version']));
    stdout.write(playReleaseNotes(body));
  } catch (error) {
    stderr.writeln('Release notes failed: $error');
    exitCode = 1;
  }
}

/// One changelog section's entries as plain text, at most [limit] characters.
///
/// [markdown] is a section body as `cider describe --only-body` prints it:
/// `### Added`-style headings over `- ` bullets. The headings go, since the
/// entries read as sentences without them and Play's limit is short, and each
/// bullet becomes a `•` line with its inline Markdown removed.
///
/// When the entries do not fit, whole ones are kept from the top and the rest
/// are counted on a last line rather than cut mid-sentence.
///
/// Throws a [FormatException] if the section has no entries, because Play
/// would otherwise show testers an empty note without anyone noticing.
String playReleaseNotes(String markdown, {int limit = playLimit}) {
  final entries = [
    for (final line in markdown.split('\n'))
      if (line.trimLeft().startsWith('- '))
        '• ${_plain(line.trimLeft().substring(2).trim())}',
  ];
  if (entries.isEmpty) {
    throw const FormatException('The changelog section has no entries.');
  }

  final kept = <String>[];
  for (final (index, entry) in entries.indexed) {
    final remaining = entries.length - index - 1;
    final tail = remaining == 0 ? '' : '\n…and $remaining more.';
    final candidate = [...kept, entry].join('\n');
    if (candidate.length + tail.length > limit) break;
    kept.add(entry);
  }

  if (kept.isEmpty) {
    throw FormatException(
      'The first entry alone is longer than Play allows ($limit characters).',
    );
  }
  final omitted = entries.length - kept.length;
  return [...kept, if (omitted > 0) '…and $omitted more.'].join('\n');
}

/// [text] without its inline Markdown: links keep their text, and code,
/// emphasis and strong markers are dropped.
String _plain(String text) => text
    .replaceAllMapped(
      RegExp(r'\[([^\]]+)\](?:\([^)]*\)|\[[^\]]*\])'),
      (match) => match[1]!,
    )
    .replaceAll(RegExp(r'[`*]'), '')
    .replaceAllMapped(RegExp(r'\b_(.+?)_\b'), (match) => match[1]!);

/// A changelog section's body: Unreleased when [version] is null.
Future<String> _describe([String? version]) =>
    _cider(['describe', ?version, '--only-body']);

Future<String> _cider(List<String> arguments) async {
  final result = await Process.run('dart', ['run', 'cider', ...arguments]);
  if (result.exitCode != 0) {
    throw ProcessException(
      'cider',
      arguments,
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
  return '${result.stdout}'.trim();
}

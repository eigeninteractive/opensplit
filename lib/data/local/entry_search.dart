/// Quotes user terms for SQLite FTS5, matching each term as a word prefix.
///
/// Shared by group search and Insights so both interpret typed text the same
/// way. The returned expression must still be passed as a bound SQL variable.
String? entrySearchMatch(String query) {
  final terms = query
      .replaceAll('"', ' ')
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  return terms.isEmpty ? null : terms.map((term) => '"$term"*').join(' ');
}

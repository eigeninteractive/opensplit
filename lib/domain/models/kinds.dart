/// The ledger's closed vocabularies, as the wire contract defines them.
///
/// Each has an `unknownDefaultOpenApi` member: what a value from a newer
/// server decodes to, rather than an exception.
library;

export 'package:opensplit_api/opensplit_api.dart'
    show EntryKind, EventKind, SplitKind;

/// The member of [values] whose wire value is [wire], or null.
///
/// The generated enums' `toString()` is their wire value.
T? fromWire<T extends Enum>(List<T> values, String? wire) {
  for (final value in values) {
    if ('$value' == wire) return value;
  }
  return null;
}

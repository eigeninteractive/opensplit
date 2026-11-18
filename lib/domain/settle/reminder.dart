/// The message somebody who is owed money sends to whoever owes it.
library;

/// A short, friendly nudge naming the amount and the group, with where to
/// pay when that is known.
///
/// [amount] is already formatted, symbol included. [upiVpa] is the sender's
/// own handle, if they have saved one.
String reminderText({
  required String debtorName,
  required String amount,
  required String groupName,
  String? upiVpa,
}) {
  final handle = upiVpa?.trim() ?? '';
  return [
    'Hi $debtorName, a reminder from OpenSplit: you owe me $amount in '
        '“$groupName”.',
    if (handle.isNotEmpty) 'You can pay me by UPI at $handle.',
  ].join(' ');
}

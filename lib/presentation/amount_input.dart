import 'package:flutter/services.dart';

import '../data/local/database.dart';
import '../domain/money_format.dart';

/// Keeps a number field to something its parser reads: digits, one decimal
/// point, and no more digits either side than the value allows.
///
/// The point may be typed as `.` or `,`, because a phone's number keyboard
/// shows whichever the device's region uses. A keystroke that would make the
/// text unreadable is refused, so the field never holds something that
/// silently means another number.
class DecimalInputFormatter extends TextInputFormatter {
  DecimalInputFormatter(this._shape);

  /// An amount in [currency], as [CurrencyAmounts.parseToMinor] reads it.
  DecimalInputFormatter.amount(Currency? currency)
    : _shape = amountInputPattern(currency?.exponent ?? 2);

  final RegExp _shape;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _shape.hasMatch(newValue.text) ? newValue : oldValue;
}

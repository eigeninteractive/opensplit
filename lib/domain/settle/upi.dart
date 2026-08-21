import '../models/currency.dart';

/// Matches the `upi_vpa_format` check constraint on `profiles`. Kept identical
/// on purpose: a handle the client accepts must be one the server will store.
final RegExp upiVpaPattern = RegExp(r'^[a-zA-Z0-9._-]{2,64}@[a-zA-Z]{2,64}$');

bool isValidUpiVpa(String? vpa) =>
    vpa != null && upiVpaPattern.hasMatch(vpa.trim());

/// Builds a UPI payment intent for a settlement.
///
/// Returns null when a handoff is not offerable — a non-INR settlement, a payee
/// with no registered handle, or a non-positive amount. Callers show the manual
/// "record settlement" path in that case.
///
/// OpenSplit never sees the money. This produces a link that hands the user to
/// their own payment app, and the app has no way to learn what happens next:
/// the UPI intent returns no reliable confirmation. Whether the settlement gets
/// recorded is therefore always an explicit answer from the user afterwards,
/// and no copy anywhere may imply that OpenSplit verified or processed a
/// payment.
Uri? buildUpiPaymentUri({
  required String? payeeVpa,
  required String payeeName,
  required int amountMinor,
  required Currency currency,
  String note = 'OpenSplit settlement',
}) {
  if (currency.code != 'INR') return null;
  if (!isValidUpiVpa(payeeVpa)) return null;
  if (amountMinor <= 0) return null;

  return Uri(
    scheme: 'upi',
    host: 'pay',
    queryParameters: {
      'pa': payeeVpa!.trim(),
      'pn': payeeName,
      // UPI expects major units. formatPlain is exact integer arithmetic and
      // emits exactly the currency's number of decimal places.
      'am': currency.formatPlain(amountMinor),
      'cu': currency.code,
      'tn': note,
    },
  );
}

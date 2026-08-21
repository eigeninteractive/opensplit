import '../models/currency.dart';

/// Access to currency reference data.
///
/// Exists so that no caller is ever tempted to hardcode an exponent. Every
/// conversion between a typed amount and stored minor units goes through a
/// [Currency] fetched here.
abstract interface class CurrencyRepository {
  Future<List<Currency>> all();

  /// The currency for [code], or null if it is not one this build knows.
  Future<Currency?> byCode(String code);

  Stream<List<Currency>> watchAll();
}

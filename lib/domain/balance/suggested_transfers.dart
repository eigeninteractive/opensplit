import '../models/entry.dart';
import 'balance_fold.dart';
import 'pairwise.dart';
import 'simplify.dart';

/// The payments that would settle a group, the way that group asks for them:
/// the fewest that do it when it simplifies its debts, otherwise each pair
/// repaying only what they owe each other.
List<Transfer> suggestedTransfers(
  Iterable<Entry> entries, {
  required bool simplified,
}) =>
    simplified ? simplifyDebts(foldBalances(entries)) : pairwiseDebts(entries);

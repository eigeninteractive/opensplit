import 'package:material_ui/material_ui.dart';

import '../../application/ledger_providers.dart';
import '../../data/local/database.dart';
import '../../domain/money_format.dart';
import '../theme.dart';
import 'balance_arrow.dart';

/// Where you stand in a group: what it owes you and what you owe it.
///
/// Figures stay per currency, because collapsing them would require inventing
/// an exchange rate the user never agreed to. They are grouped by direction,
/// since one group can owe you euros while you owe it pounds, and a single
/// "You are owed" over both would be wrong about one of them.
///
/// [style] sets the size; the figures are drawn in it, coloured and weighted,
/// and the words around them recede.
class GroupStanding extends StatelessWidget {
  const GroupStanding({
    super.key,
    required this.ledger,
    required this.currencies,
    this.style,
  });

  final GroupLedger ledger;
  final Map<String, Currency> currencies;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final quiet = base.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final me = ledger.me;
    if (me == null) {
      final count = ledger.members.length;
      return Text('$count ${count == 1 ? 'member' : 'members'}', style: quiet);
    }

    final owed = <String>[];
    final owing = <String>[];
    for (final code in ledger.activeCurrencies) {
      final balance = ledger.balanceOf(me.id, code);
      if (balance == 0) continue;
      (balance > 0 ? owed : owing).add(
        formatMoneyAbs(currencies[code], balance),
      );
    }

    if (owed.isEmpty && owing.isEmpty) return Text('Settled up', style: quiet);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (owed.isNotEmpty)
          _Direction(
            lead: 'You are owed',
            figures: owed,
            direction: 1,
            style: base,
          ),
        if (owing.isNotEmpty)
          _Direction(
            lead: 'You owe',
            figures: owing,
            direction: -1,
            style: base,
          ),
      ],
    );
  }
}

/// One direction of a group's balance: an arrow, the words, and every
/// currency that goes that way.
class _Direction extends StatelessWidget {
  const _Direction({
    required this.lead,
    required this.figures,
    required this.direction,
    required this.style,
  });

  final String lead;

  /// Formatted, unsigned amounts, one per currency.
  final List<String> figures;

  /// Positive when these are owed to you, negative when you owe them.
  final int direction;

  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final joined = figures.join(' + ');
    final figureStyle = moneyStyle(
      style.copyWith(
        color: balanceColor(scheme, direction),
        fontWeight: FontWeight.w600,
      ),
    );

    return Semantics(
      label: '$lead $joined',
      child: ExcludeSemantics(
        child: Row(
          children: [
            BalanceArrow(
              balanceMinor: direction,
              size: (style.fontSize ?? 14) * 1.1,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$lead '),
                    TextSpan(text: joined, style: figureStyle),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

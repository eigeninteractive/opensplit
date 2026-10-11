import 'package:material_ui/material_ui.dart';

import '../../data/local/database.dart';
import '../../domain/money_format.dart';
import '../amount_input.dart';
import '../theme.dart';
import 'currency_picker.dart';
import 'shared_element.dart';

/// A transaction headline pairing its amount with a searchable currency.
class AmountCard extends StatelessWidget {
  const AmountCard({
    super.key,
    required this.currency,
    required this.amount,
    required this.currencyCode,
    required this.onAmountChanged,
    required this.onCurrencyChanged,
    this.autofocus = false,
    this.label = 'Amount',
    this.error,
    this.heroTag,
  });

  final Currency? currency;
  final String amount;
  final String currencyCode;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onCurrencyChanged;
  final bool autofocus;
  final String label;
  final String? error;

  /// The expense or suggested payment whose amount opens into this field.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSecondaryContainer;
    final valueStyle = moneyStyle(
      theme.textTheme.displaySmall!,
    ).copyWith(color: foreground);
    final amountField = TextFormField(
      initialValue: amount,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [DecimalInputFormatter.amount(currency)],
      textInputAction: TextInputAction.next,
      style: valueStyle,
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixStyle: valueStyle,
        hintText: currency?.formatPlain(0) ?? '0',
        prefixText: currency?.symbol == null ? null : '${currency!.symbol} ',
        labelStyle: TextStyle(color: foreground),
        floatingLabelStyle: TextStyle(color: foreground),
        hintStyle: valueStyle,
        filled: false,
        border: const UnderlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      onChanged: onAmountChanged,
    );
    final field = heroTag == null
        ? amountField
        : SharedText(
            tag: heroTag!,
            text: '${currency?.symbol ?? currencyCode} $amount',
            style: valueStyle,
            child: amountField,
          );
    final currencyButton = CurrencyButton(
      code: currencyCode,
      onChanged: onCurrencyChanged,
    );

    return Card.filled(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(16) > 24) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [currencyButton, const SizedBox(height: 12), field],
              );
            }
            return Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 12),
                currencyButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

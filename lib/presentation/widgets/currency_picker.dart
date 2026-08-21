import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';

/// Picks a currency from the local reference table.
///
/// Always reads the list from the database rather than a hardcoded array, so
/// the exponent that governs every amount comes from one place.
class CurrencyPicker extends ConsumerWidget {
  const CurrencyPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Currency',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final codes = currencies.keys.toList()..sort();

    return DropdownButtonFormField<String>(
      initialValue: codes.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: [
        for (final code in codes)
          DropdownMenuItem(
            value: code,
            child: Text(
              '$code — ${currencies[code]!.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (code) {
        if (code != null) onChanged(code);
      },
    );
  }
}

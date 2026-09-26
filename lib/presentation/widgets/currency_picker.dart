import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';

/// Picks a currency from the local reference table.
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

    // DropdownMenu, not DropdownButtonFormField.
    return DropdownMenu<String>(
      initialSelection: codes.contains(value) ? value : null,
      label: label.isEmpty ? null : Text(label),
      enableFilter: true,
      requestFocusOnTap: true,
      menuHeight: 320,
      // Fills whatever width the parent gives it.
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: [
        for (final code in codes)
          DropdownMenuEntry(
            value: code,
            label: '$code — ${currencies[code]!.name}',
          ),
      ],
      onSelected: (code) {
        if (code != null) onChanged(code);
      },
    );
  }
}

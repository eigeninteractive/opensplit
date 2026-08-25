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

    // DropdownMenu, not DropdownButtonFormField. The latter is Material 2 —
    // its own source points at m2.material.io — and it opens a modal list with
    // no way to narrow it. This list is every currency in the table, so being
    // able to type "rup" and have it filter is the difference between a picker
    // and a scroll.
    return DropdownMenu<String>(
      initialSelection: codes.contains(value) ? value : null,
      label: label.isEmpty ? null : Text(label),
      enableFilter: true,
      requestFocusOnTap: true,
      menuHeight: 320,
      // Fills whatever the parent gives it, the way the old form field did.
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

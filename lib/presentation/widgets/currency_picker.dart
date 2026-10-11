import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ledger_providers.dart';

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

/// Opens Material's search view over locally available currencies.
class CurrencyButton extends ConsumerWidget {
  const CurrencyButton({
    super.key,
    required this.code,
    required this.onChanged,
  });

  final String code;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final codes = currencies.keys.toList()..sort();

    return SearchAnchor(
      viewHintText: 'Search currencies',
      builder: (context, controller) => OutlinedButton.icon(
        onPressed: controller.openView,
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_drop_down),
        label: Text(code),
      ),
      suggestionsBuilder: (context, controller) {
        final query = controller.text.trim().toLowerCase();
        return [
          for (final option in codes)
            if (query.isEmpty ||
                option.toLowerCase().contains(query) ||
                currencies[option]!.name.toLowerCase().contains(query))
              ListTile(
                title: Text(currencies[option]!.name),
                leading: SizedBox(width: 48, child: Text(option)),
                selected: option == code,
                onTap: () {
                  controller.closeView(option);
                  onChanged(option);
                },
              ),
        ];
      },
    );
  }
}

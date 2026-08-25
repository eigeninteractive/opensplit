import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers.dart';
import '../../domain/export/csv_export.dart';

/// Exports whatever the current filter selects, as CSV.
///
/// Exports the filtered view rather than only "everything", because the useful
/// export is usually a slice — one trip, one category, one person. The file
/// keeps every payer and every share, so it reconstructs the ledger rather than
/// just its outcome.
class ExportButton extends ConsumerStatefulWidget {
  const ExportButton({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<ExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final ledger = ref.read(groupLedgerProvider(widget.groupId));
      final filter = ref.read(
        analyticsFilterControllerProvider(widget.groupId),
      );
      final entries = await ref
          .read(analyticsRepositoryProvider)
          .search(filter);
      final categories = await ref.read(categoryRepositoryProvider).all();
      final currencies = ref.read(currenciesProvider).value ?? const {};

      final csv = entriesToCsv(
        entries.isEmpty && !filter.isNarrowed
            ? (ledger?.entries ?? const [])
            : entries,
        memberNames: {
          for (final member in ledger?.members ?? const [])
            member.id: member.displayName,
        },
        currencies: currencies,
        categoryNames: {for (final c in categories) c.id: c.name},
      );

      final slug = (ledger?.group.name ?? 'opensplit')
          .replaceAll(RegExp(r'[^\w]+'), '-')
          .toLowerCase();
      final day = DateTime.now().toIso8601String().split('T').first;
      final name = '$slug-$day.csv';

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: name),
          ],
          fileNameOverrides: [name],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export. $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Export CSV',
    onPressed: _busy ? null : _export,
    icon: _busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.ios_share),
  );
}

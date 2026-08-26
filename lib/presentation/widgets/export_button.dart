import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers.dart';
import '../../domain/export/csv_export.dart';
import '../../domain/export/json_export.dart';

/// Exports the group, in whichever of the two formats is wanted.
///
/// They are not the same file in different clothes. **CSV** is the filtered
/// view for a person with a spreadsheet: flat, one row per expense, honouring
/// whatever the analytics filter currently selects, because the useful export
/// is usually a slice — one trip, one category, one person. **JSON** ignores
/// the filter and takes everything: members who never claimed an account, the
/// weights behind each split, the fx snapshot each entry was recorded against,
/// and the activity log. It is the copy you keep.
class ExportButton extends ConsumerStatefulWidget {
  const ExportButton({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<ExportButton> createState() => _ExportButtonState();
}

enum _Format { csv, json }

class _ExportButtonState extends ConsumerState<ExportButton> {
  bool _busy = false;

  Future<void> _pick() async {
    final format = await showModalBottomSheet<_Format>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Spreadsheet (CSV)'),
              subtitle: const Text(
                'One row per expense, matching what is on screen now. Opens '
                'in Excel, Numbers or Sheets.',
              ),
              isThreeLine: true,
              onTap: () => Navigator.of(context).pop(_Format.csv),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Full backup (JSON)'),
              subtitle: const Text(
                'The whole group, ignoring any filter: everyone, every split, '
                'the exchange rates used, and the activity log.',
              ),
              isThreeLine: true,
              onTap: () => Navigator.of(context).pop(_Format.json),
            ),
          ],
        ),
      ),
    );
    if (format == null || !mounted) return;
    await (format == _Format.csv ? _exportCsv() : _exportJson());
  }

  /// The whole group, unfiltered, in a form that could rebuild it.
  Future<void> _exportJson() async {
    setState(() => _busy = true);
    try {
      final ledger = ref.read(groupLedgerProvider(widget.groupId));
      if (ledger == null) return;

      final categories = await ref.read(categoryRepositoryProvider).all();
      final activity =
          ref.read(groupActivityProvider(widget.groupId)).value ?? const [];

      final json = groupToJson(
        group: ledger.group,
        members: ledger.members,
        entries: ledger.entries,
        profiles: ledger.profiles,
        nameOf: ledger.nameOfMember,
        activity: activity,
        categoryNames: {for (final c in categories) c.id: c.name},
      );

      await _share(json, 'json', 'application/json');
    } catch (error) {
      _complain(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final ledger = ref.read(groupLedgerProvider(widget.groupId));
      final filter = ref.read(
        analyticsFilterControllerProvider(widget.groupId),
      );
      final entries = await ref
          .read(analyticsRepositoryProvider)
          .search(filter)
          .first;
      final categories = await ref.read(categoryRepositoryProvider).all();
      final currencies = ref.read(currenciesProvider).value ?? const {};

      final csv = entriesToCsv(
        entries.isEmpty && !filter.isNarrowed
            ? (ledger?.entries ?? const [])
            : entries,
        memberNames: {
          for (final member in ledger?.members ?? const [])
            // The resolved name, so somebody who has claimed an account appears
            // in the file under the name everybody actually calls them.
            member.id: ledger?.nameOfMember(member) ?? member.displayName,
        },
        currencies: currencies,
        categoryNames: {for (final c in categories) c.id: c.name},
      );

      await _share(csv, 'csv', 'text/csv');
    } catch (error) {
      _complain(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String body, String extension, String mimeType) async {
    final ledger = ref.read(groupLedgerProvider(widget.groupId));
    final slug = (ledger?.group.name ?? 'opensplit')
        .replaceAll(RegExp(r'[^\w]+'), '-')
        .toLowerCase();
    final day = DateTime.now().toIso8601String().split('T').first;
    final name = '$slug-$day.$extension';

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(utf8.encode(body), mimeType: mimeType, name: name),
        ],
        fileNameOverrides: [name],
      ),
    );
  }

  void _complain(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not export. $error')));
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Export',
    onPressed: _busy ? null : _pick,
    icon: _busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.ios_share),
  );
}

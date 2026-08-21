import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/entry_draft.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/entry.dart';
import '../../domain/split/allocation.dart';
import '../../domain/split/splitter.dart';
import '../format.dart';
import '../widgets/currency_picker.dart';

/// Creates or edits an expense.
///
/// The default path is deliberately the shortest one: type what it was, type
/// how much, save. Everything else — several payers, unequal splits, another
/// currency, another date — is available but never in the way, because the
/// thing that kills an expense app is the expense you did not bother to log.
class EntryEditorScreen extends ConsumerStatefulWidget {
  const EntryEditorScreen({super.key, required this.groupId, this.entryId});

  final String groupId;
  final String? entryId;

  bool get isEditing => entryId != null;

  @override
  ConsumerState<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends ConsumerState<EntryEditorScreen> {
  final _description = TextEditingController();
  final _amount = TextEditingController();

  /// Per-member text input for exact amounts, percentages and payer amounts.
  final _exact = <String, TextEditingController>{};
  final _percent = <String, TextEditingController>{};
  final _payerAmounts = <String, TextEditingController>{};

  String? _currencyCode;
  DateTime _date = DateTime.now();
  SplitKind _splitKind = SplitKind.equal;
  final _participants = <String>{};
  final _shares = <String, int>{};
  final _payers = <String>{};
  bool _multiplePayers = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    for (final c in _exact.values) {
      c.dispose();
    }
    for (final c in _percent.values) {
      c.dispose();
    }
    for (final c in _payerAmounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(
    Map<String, TextEditingController> map,
    String id,
  ) => map.putIfAbsent(id, TextEditingController.new);

  /// Seeds the form once the ledger — and, when editing, the entry — is known.
  void _loadOnce(
    GroupLedger ledger,
    Entry? existing,
    Map<String, Currency> cx,
  ) {
    if (_loaded) return;
    if (widget.isEditing && existing == null) return;
    _loaded = true;

    _currencyCode = existing?.currency ?? ledger.group.defaultCurrency;

    if (existing == null) {
      // Everyone splits, the person adding it paid. The overwhelmingly common
      // case, pre-filled so the fast path is two fields and a button.
      _participants.addAll(ledger.members.map((m) => m.id));
      final me = ledger.me?.id ?? ledger.members.firstOrNull?.id;
      if (me != null) _payers.add(me);
      return;
    }

    _description.text = existing.description;
    _date = existing.entryDate;
    _splitKind = existing.splitKind;
    final currency = cx[existing.currency];
    if (currency != null) {
      _amount.text = currency.formatPlain(existing.amountMinor);
    }

    _participants.addAll(existing.shares.map((s) => s.memberId));
    _payers.addAll(existing.payers.map((p) => p.memberId));
    _multiplePayers = existing.payers.length > 1;

    for (final share in existing.shares) {
      if (currency != null) {
        _controllerFor(_exact, share.memberId).text = currency.formatPlain(
          share.amountMinor,
        );
      }
      final weight = share.weightMicros;
      if (weight != null) {
        _shares[share.memberId] = (weight / weightScale).round();
        _controllerFor(_percent, share.memberId).text = _microsToText(weight);
      }
    }
    for (final payer in existing.payers) {
      if (currency != null) {
        _controllerFor(_payerAmounts, payer.memberId).text = currency
            .formatPlain(payer.amountMinor);
      }
    }
  }

  static String _microsToText(int micros) {
    final whole = micros ~/ weightScale;
    final frac = micros % weightScale;
    if (frac == 0) return '$whole';
    return '$whole.${frac.toString().padLeft(6, '0').replaceAll(RegExp(r'0+$'), '')}';
  }

  /// Parses a decimal string into units of 10^-6, the precision the weight
  /// column stores.
  static int? _textToMicros(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'^(\d*)(?:\.(\d{0,6}))?$').firstMatch(trimmed);
    if (match == null) return null;
    final whole = match.group(1) ?? '';
    final frac = match.group(2) ?? '';
    if (whole.isEmpty && frac.isEmpty) return null;
    final wholeValue = whole.isEmpty ? 0 : int.parse(whole);
    final fracValue = frac.isEmpty ? 0 : int.parse(frac.padRight(6, '0'));
    return wholeValue * weightScale + fracValue;
  }

  SplitSpec? _buildSplit(Currency currency, int totalMinor) {
    final ids = _participants.toList();
    if (ids.isEmpty) return null;

    switch (_splitKind) {
      case SplitKind.equal:
        return EqualSplit(ids);

      case SplitKind.exact:
        final amounts = <String, int>{};
        for (final id in ids) {
          final parsed = currency.parseToMinor(_exact[id]?.text ?? '');
          if (parsed == null) return null;
          amounts[id] = parsed;
        }
        return ExactSplit(amounts);

      case SplitKind.shares:
        return SharesSplit({for (final id in ids) id: _shares[id] ?? 1});

      case SplitKind.percent:
        final percents = <String, int>{};
        for (final id in ids) {
          final parsed = _textToMicros(_percent[id]?.text ?? '');
          if (parsed == null) return null;
          percents[id] = parsed;
        }
        return PercentSplit(percents);
    }
  }

  Map<String, int>? _buildPayers(Currency currency, int totalMinor) {
    if (!_multiplePayers) {
      final only = _payers.firstOrNull;
      return only == null ? null : {only: totalMinor};
    }
    final amounts = <String, int>{};
    for (final id in _payers) {
      final parsed = currency.parseToMinor(_payerAmounts[id]?.text ?? '');
      if (parsed == null || parsed <= 0) return null;
      amounts[id] = parsed;
    }
    return amounts.isEmpty ? null : amounts;
  }

  Future<void> _save(GroupLedger ledger, Currency currency) async {
    setState(() => _error = null);

    final totalMinor = currency.parseToMinor(_amount.text);
    if (totalMinor == null || totalMinor <= 0) {
      setState(
        () => _error = currency.exponent == 0
            ? 'Enter a whole amount.'
            : 'Enter an amount with at most ${currency.exponent} decimal '
                  'places.',
      );
      return;
    }

    final split = _buildSplit(currency, totalMinor);
    final payers = _buildPayers(currency, totalMinor);
    if (split == null) {
      setState(() => _error = 'Check the split — some amounts are missing.');
      return;
    }
    if (payers == null) {
      setState(() => _error = 'Check who paid — some amounts are missing.');
      return;
    }

    final draft = EntryDraft(
      groupId: widget.groupId,
      currency: currency.code,
      amountMinor: totalMinor,
      description: _description.text.trim(),
      split: split,
      payerAmounts: payers,
      entryDate: DateTime.utc(_date.year, _date.month, _date.day),
    );

    setState(() => _saving = true);
    try {
      final repository = ref.read(entryRepositoryProvider);
      if (widget.isEditing) {
        await repository.update(widget.entryId!, draft);
      } else {
        await repository.create(
          draft,
          createdBy: ledger.me?.id ?? payers.keys.first,
        );
      }
      if (!mounted) return;
      context.go('/g/${widget.groupId}');
    } on SplitException catch (e) {
      // The domain refused it, so nothing was written. Its messages are written
      // for people, so they are shown as-is.
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'Balances update straight away. The entry is kept in history so the '
          'change can always be explained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    await ref.read(entryRepositoryProvider).delete(widget.entryId!);
    if (mounted) context.go('/g/${widget.groupId}');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(groupLedgerProvider(widget.groupId));
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final existing = widget.isEditing
        ? ref
              .watch(entriesProvider(widget.groupId))
              .value
              ?.where((e) => e.id == widget.entryId)
              .firstOrNull
        : null;

    if (ledger == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    _loadOnce(ledger, existing, currencies);

    final currency = currencies[_currencyCode];
    final totalMinor = currency?.parseToMinor(_amount.text);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/g/${widget.groupId}'),
        ),
        title: Text(widget.isEditing ? 'Edit expense' : 'Add expense'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          TextField(
            controller: _description,
            autofocus: !widget.isEditing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What was it?',
              hintText: 'Dinner at Toit',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'How much?',
                    prefixText: currency?.symbol == null
                        ? null
                        : '${currency!.symbol} ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: CurrencyPicker(
                  value: _currencyCode ?? ledger.group.defaultCurrency,
                  label: '',
                  onChanged: (code) => setState(() => _currencyCode = code),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (currency != null && currency.code != ledger.group.defaultCurrency)
            Text(
              'Stored in ${currency.code}. Balances in a group are always kept '
              'per currency, never converted.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(DateFormat.yMMMEd().format(_date)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const Divider(height: 32),
          _PayerSection(
            ledger: ledger,
            currency: currency,
            payers: _payers,
            multiple: _multiplePayers,
            controllerFor: (id) => _controllerFor(_payerAmounts, id),
            onToggleMultiple: (value) => setState(() {
              _multiplePayers = value;
              if (!value && _payers.length > 1) {
                final first = _payers.first;
                _payers
                  ..clear()
                  ..add(first);
              }
            }),
            onChanged: () => setState(() {}),
          ),
          const Divider(height: 32),
          _SplitSection(
            ledger: ledger,
            currency: currency,
            totalMinor: totalMinor,
            splitKind: _splitKind,
            participants: _participants,
            shares: _shares,
            exactControllerFor: (id) => _controllerFor(_exact, id),
            percentControllerFor: (id) => _controllerFor(_percent, id),
            onKindChanged: (kind) => setState(() => _splitKind = kind),
            onChanged: () => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving || currency == null
                ? null
                : () => _save(ledger, currency),
            icon: const Icon(Icons.check),
            label: Text(widget.isEditing ? 'Save changes' : 'Add expense'),
          ),
        ],
      ),
    );
  }
}

class _PayerSection extends StatelessWidget {
  const _PayerSection({
    required this.ledger,
    required this.currency,
    required this.payers,
    required this.multiple,
    required this.controllerFor,
    required this.onToggleMultiple,
    required this.onChanged,
  });

  final GroupLedger ledger;
  final Currency? currency;
  final Set<String> payers;
  final bool multiple;
  final TextEditingController Function(String) controllerFor;
  final ValueChanged<bool> onToggleMultiple;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Paid by', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton(
              onPressed: () => onToggleMultiple(!multiple),
              child: Text(multiple ? 'One person' : 'Several people'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!multiple)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in ledger.members)
                ChoiceChip(
                  label: Text(
                    member.displayName +
                        (member.id == ledger.me?.id ? ' (you)' : ''),
                  ),
                  selected: payers.contains(member.id),
                  onSelected: (_) {
                    payers
                      ..clear()
                      ..add(member.id);
                    onChanged();
                  },
                ),
            ],
          )
        else
          Column(
            children: [
              for (final member in ledger.members)
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: payers.contains(member.id),
                        title: Text(member.displayName),
                        onChanged: (checked) {
                          if (checked ?? false) {
                            payers.add(member.id);
                          } else {
                            payers.remove(member.id);
                          }
                          onChanged();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: controllerFor(member.id),
                        enabled: payers.contains(member.id),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: currency?.symbol,
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'The amounts paid have to add up to the total.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _SplitSection extends StatelessWidget {
  const _SplitSection({
    required this.ledger,
    required this.currency,
    required this.totalMinor,
    required this.splitKind,
    required this.participants,
    required this.shares,
    required this.exactControllerFor,
    required this.percentControllerFor,
    required this.onKindChanged,
    required this.onChanged,
  });

  final GroupLedger ledger;
  final Currency? currency;
  final int? totalMinor;
  final SplitKind splitKind;
  final Set<String> participants;
  final Map<String, int> shares;
  final TextEditingController Function(String) exactControllerFor;
  final TextEditingController Function(String) percentControllerFor;
  final ValueChanged<SplitKind> onKindChanged;
  final VoidCallback onChanged;

  /// A live preview of what each person ends up owing.
  ///
  /// Runs the real allocator, not an approximation, so the rounding shown here
  /// is the rounding that gets stored.
  Map<String, int>? _preview() {
    if (currency == null || totalMinor == null || totalMinor! <= 0) return null;
    if (participants.isEmpty) return null;

    try {
      final spec = switch (splitKind) {
        SplitKind.equal => EqualSplit(participants.toList()),
        SplitKind.shares => SharesSplit({
          for (final id in participants) id: shares[id] ?? 1,
        }),
        _ => null,
      };
      if (spec == null) return null;
      return {
        for (final share in spec.resolve(totalMinor!))
          share.memberId: share.amountMinor,
      };
    } on SplitException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Split', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<SplitKind>(
          segments: const [
            ButtonSegment(value: SplitKind.equal, label: Text('Equally')),
            ButtonSegment(value: SplitKind.exact, label: Text('Amounts')),
            ButtonSegment(value: SplitKind.shares, label: Text('Shares')),
            ButtonSegment(value: SplitKind.percent, label: Text('%')),
          ],
          selected: {splitKind},
          onSelectionChanged: (set) => onKindChanged(set.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 8),
        for (final member in ledger.members)
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: participants.contains(member.id),
                  title: Text(
                    member.displayName +
                        (member.id == ledger.me?.id ? ' (you)' : ''),
                  ),
                  subtitle: preview != null && participants.contains(member.id)
                      ? Text(formatMoney(currency, preview[member.id] ?? 0))
                      : null,
                  onChanged: (checked) {
                    if (checked ?? false) {
                      participants.add(member.id);
                    } else {
                      participants.remove(member.id);
                    }
                    onChanged();
                  },
                ),
              ),
              if (participants.contains(member.id))
                switch (splitKind) {
                  SplitKind.exact => SizedBox(
                    width: 110,
                    child: TextField(
                      controller: exactControllerFor(member.id),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: currency?.symbol,
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  SplitKind.percent => SizedBox(
                    width: 90,
                    child: TextField(
                      controller: percentControllerFor(member.id),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: '%',
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  SplitKind.shares => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          final next = (shares[member.id] ?? 1) - 1;
                          shares[member.id] = next < 0 ? 0 : next;
                          onChanged();
                        },
                      ),
                      Text('${shares[member.id] ?? 1}'),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          shares[member.id] = (shares[member.id] ?? 1) + 1;
                          onChanged();
                        },
                      ),
                    ],
                  ),
                  SplitKind.equal => const SizedBox.shrink(),
                },
            ],
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:opensplit_api/opensplit_api.dart' show SplitKind;

import '../../application/ledger_providers.dart';
import '../../application/local_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../domain/activity/activity_text.dart';
import '../../domain/calendar_date.dart';
import '../../domain/entry_draft.dart';
import '../../domain/fx/fx_quote.dart';
import '../../domain/models/entry.dart';
import '../../domain/models/group_event.dart';
import '../../domain/money_format.dart';
import '../../domain/split/allocation.dart';
import '../../domain/split/splitter.dart';
import '../feedback.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/category_icon.dart';
import '../widgets/avatar_view.dart';
import '../widgets/page_body.dart';

/// Creates or edits an expense.
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
  String? _categoryId;

  /// The day it happened, and when on that day if known, with the zone it
  /// happened in. Times are shown and picked on this device's clock.
  late DateTime _date;
  DateTime? _occurredAt;
  String? _zone;
  SplitKind _splitKind = SplitKind.equal;

  /// Who is in the split, who paid, and the relative weights.
  ///
  /// Replaced rather than mutated, so only this state object changes them.
  Set<String> _participants = {};
  Map<String, int> _shares = {};
  Set<String> _payers = {};

  bool _multiplePayers = false;
  bool _loaded = false;
  Entry? _editingSnapshot;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = now;
    _occurredAt = now.toUtc();
    // Seeding the form is initialisation from asynchronous data, so it listens
    // instead of running inside build.
    ref.listenManual(
      groupLedgerProvider(widget.groupId),
      (_, _) => _seedWhenReady(),
      fireImmediately: true,
    );
    ref.listenManual(currenciesProvider, (_, _) => _seedWhenReady());
  }

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

  /// Seeds the form as soon as everything it needs has arrived.
  void _seedWhenReady() {
    if (_loaded) return;

    final ledger = ref.read(groupLedgerProvider(widget.groupId));
    final currencies = ref.read(currenciesProvider).value;
    if (ledger == null || currencies == null) return;

    final existing = widget.isEditing
        ? ledger.entries.where((e) => e.id == widget.entryId).firstOrNull
        : null;
    if (widget.isEditing && existing == null) return;

    _load(ledger, existing, currencies);
  }

  void _load(GroupLedger ledger, Entry? existing, Map<String, Currency> cx) {
    _loaded = true;
    _editingSnapshot = existing;

    _currencyCode = existing?.row.currency ?? ledger.group.defaultCurrency;

    if (existing == null) {
      // Everyone splits, the person adding it paid. The overwhelmingly common
      // case, pre-filled so the fast path is two fields and a button.
      _participants = {for (final member in ledger.members) member.id};
      final me = ledger.me?.id ?? ledger.members.firstOrNull?.id;
      if (me != null) _payers = {me};
      return;
    }

    _description.text = existing.row.description;
    _categoryId = existing.row.categoryId;
    _date = existing.row.entryDate;
    _occurredAt = existing.row.occurredAt;
    _zone = existing.row.timeZone;
    _splitKind = existing.row.splitKind;
    final currency = cx[existing.row.currency];
    if (currency != null) {
      _amount.text = currency.formatPlain(existing.row.amountMinor);
    }

    _participants = {for (final share in existing.shares) share.memberId};
    _payers = {for (final payer in existing.payers) payer.memberId};
    _multiplePayers = existing.payers.length > 1;

    _shares = {};
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
    final decimals = frac
        .toString()
        .padLeft(6, '0')
        .replaceAll(RegExp(r'0+$'), '');
    return '$whole.$decimals';
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

      // A split rule from a newer server: saving would have to guess it.
      case SplitKind.unknownDefaultOpenApi:
        return null;
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

  Future<void> _save(GroupLedger ledger, Currency currency, FxQuote? fx) async {
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

    final moment = _moment();
    final draft = EntryDraft(
      groupId: widget.groupId,
      currency: currency.code,
      amountMinor: totalMinor,
      description: _description.text.trim(),
      categoryId: _categoryId,
      split: split,
      payerAmounts: payers,
      entryDate: calendarDay(_date),
      occurredAt: moment?.at,
      timeZone: moment?.zone,
      // A fact about the transaction, captured once.
      fxRate: fx?.rate,
      fxSource: fx == null ? null : '${fx.source}@${calendarDate(fx.date)}',
    );

    setState(() => _saving = true);
    try {
      final repository = ref.read(entryRepositoryProvider);
      if (widget.isEditing) {
        // Who is editing, which need not be who created it — that difference is
        // most of what makes a feed line worth reading.
        await repository.update(
          widget.entryId!,
          draft,
          actorId: ledger.me?.id,
          expected: _editingSnapshot,
        );
      } else {
        await repository.create(
          draft,
          createdBy: ledger.me?.id ?? payers.keys.first,
        );
      }
      if (!mounted) return;
      goBack(context, '/g/${widget.groupId}');
    } on SplitException catch (e) {
      // The domain refused it, so nothing was written. Its messages are written
      // for people, so they are shown as-is.
      if (mounted) setState(() => _error = e.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The moment to save. A time with no zone yet (a new expense) is this
  /// device's. Saving never waits to learn which that is: with no zone known
  /// yet, only the day is kept.
  ({DateTime at, String zone})? _moment() {
    final at = _occurredAt;
    final zone = _zone ?? ref.read(deviceZoneProvider).value;
    return at == null || zone == null ? null : (at: at, zone: zone);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || DateUtils.isSameDay(picked, _date)) return;
    setState(() {
      _date = picked;
      _occurredAt = null;
      _zone = null;
    });
  }

  /// A time picked on this device's clock happened in this device's zone.
  Future<void> _pickTime(String device) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _occurredAt?.toLocal() ?? DateTime.now(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _occurredAt = DateTime(
        _date.year,
        _date.month,
        _date.day,
        picked.hour,
        picked.minute,
      ).toUtc();
      _zone = device;
    });
  }

  /// Dates already asked for, so a rebuild does not re-ask.
  final _requestedRates = <String>{};

  void _requestRate(DateTime asOf, String currency) {
    final day = calendarDate(asOf);
    if (!_requestedRates.add('$day|$currency')) return;

    // Not awaited: this must not delay a frame or a save.
    ref
        .read(syncEngineProvider)
        ?.shared
        .requestBackfill(asOf, currency)
        .ignore();
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
            onPressed: () {
              confirmedIrreversibly();
              Navigator.of(context).pop(true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    try {
      await ref
          .read(entryRepositoryProvider)
          .delete(
            widget.entryId!,
            actorId: ref.read(groupLedgerProvider(widget.groupId))?.me?.id,
            expected: _editingSnapshot,
          );
      if (mounted) goBack(context, '/g/${widget.groupId}');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(groupLedgerProvider(widget.groupId));
    final device = ref.watch(deviceZoneProvider).value;
    final currencies = ref.watch(currenciesProvider).value ?? const {};

    if (ledger == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }

    final currency = currencies[_currencyCode];
    final totalMinor = currency?.parseToMinor(_amount.text);

    // The rate as it stood on the ENTRY's date, not today's.
    final target = ledger.group.defaultCurrency;
    FxQuote? fx;
    if (currency != null && currency.code != target) {
      final day = DateTime.utc(_date.year, _date.month, _date.day);
      final quote = fxQuoteProvider(currency.code, target, day);
      fx = ref.watch(quote).value;

      // Nothing local can price this date, so ask the server: the rate lands on
      // a later sync and the entry saves without a snapshot in the meantime,
      // which the schema allows.
      final code = currency.code;
      ref.listen(quote, (_, next) {
        if (next.isLoading || next.value != null) return;
        _requestRate(day, code);
      });
    }

    final textTheme = Theme.of(context).textTheme;
    final ready = !_saving && currency != null;

    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(
          onPressed: () => goBack(context, '/g/${widget.groupId}'),
        ),
        title: Text(widget.isEditing ? 'Edit expense' : 'Add expense'),
        actions: [
          if (widget.isEditing)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: ready ? () => _save(ledger, currency, fx) : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            // The amount is what the whole screen is for, so it is the
            // largest thing on it.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CurrencyButton(
                  code: _currencyCode ?? ledger.group.defaultCurrency,
                  onChanged: (code) => setState(() => _currencyCode = code),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _amount,
                    autofocus: !widget.isEditing,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    style: moneyStyle(textTheme.displaySmall!),
                    decoration: InputDecoration(
                      labelText: 'How much?',
                      hintText: currency == null
                          ? '0'
                          : currency.formatPlain(0),
                      prefixText: currency?.symbol == null
                          ? null
                          : '${currency!.symbol} ',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (currency != null &&
                currency.code != ledger.group.defaultCurrency)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Stored in ${currency.code}. Balances in a group are '
                  'always kept per currency, never converted.',
                  style: textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What was it?',
                hintText: 'Dinner at Toit',
              ),
            ),
            const SizedBox(height: 16),
            // The details most expenses leave as they are, as chips rather
            // than a field each.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CategoryChip(
                  value: _categoryId,
                  onChanged: (id) => setState(() => _categoryId = id),
                ),
                ActionChip(
                  avatar: const Icon(Icons.event_outlined),
                  label: Text(_dayName(_date)),
                  tooltip: 'Change the day',
                  onPressed: _pickDate,
                ),
                _TimeChip(
                  shown: _occurredAt?.toLocal(),
                  onPick: device == null ? null : () => _pickTime(device),
                  onClear: () => setState(() {
                    _occurredAt = null;
                    _zone = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _PayerSection(
              ledger: ledger,
              currency: currency,
              payers: _payers,
              multiple: _multiplePayers,
              controllerFor: (id) => _controllerFor(_payerAmounts, id),
              onToggleMultiple: (value) => setState(() {
                _multiplePayers = value;
                if (!value && _payers.length > 1) {
                  _payers = {_payers.first};
                }
              }),
              onPayersChanged: (next) => setState(() => _payers = next),
              onAmountEdited: () => setState(() {}),
            ),
            const SizedBox(height: 32),
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
              onParticipantsChanged: (next) =>
                  setState(() => _participants = next),
              onSharesChanged: (next) => setState(() => _shares = next),
              onAmountEdited: () => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card.filled(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            if (widget.isEditing) ...[
              const SizedBox(height: 32),
              _History(entryId: widget.entryId!, ledger: ledger),
            ],
          ],
        ),
      ),
    );
  }

  /// "Today", "Yesterday", or the date.
  static String _dayName(DateTime day) {
    final today = DateUtils.dateOnly(DateTime.now());
    final daysAgo = today.difference(DateUtils.dateOnly(day)).inDays;
    return switch (daysAgo) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat.yMMMEd().format(day),
    };
  }
}

/// A section of the editor, named.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          ?action,
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
    required this.onPayersChanged,
    required this.onAmountEdited,
  });

  final GroupLedger ledger;
  final Currency? currency;

  /// Who paid, to render. Read only: a new selection goes back up through
  /// [onPayersChanged] rather than being edited in place.
  final Set<String> payers;

  final bool multiple;
  final TextEditingController Function(String) controllerFor;
  final ValueChanged<bool> onToggleMultiple;
  final ValueChanged<Set<String>> onPayersChanged;

  /// An amount was typed. The controllers belong to the editor, and the field
  /// has already written to one, so this only asks for a rebuild.
  final VoidCallback onAmountEdited;

  Set<String> _with(String memberId, {required bool selected}) {
    final next = {...payers};
    if (selected) {
      next.add(memberId);
    } else {
      next.remove(memberId);
    }
    return next;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Paid by',
          action: TextButton(
            onPressed: () => onToggleMultiple(!multiple),
            child: Text(multiple ? 'One person' : 'Several people'),
          ),
        ),
        if (!multiple)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in ledger.members)
                ChoiceChip(
                  // The person's own picture says which one is chosen better
                  // than a tick would.
                  showCheckmark: false,
                  avatar: MemberAvatar(
                    ledger: ledger,
                    member: member,
                    radius: 12,
                  ),
                  label: Text(
                    ledger.nameOfMember(member) +
                        (member.id == ledger.me?.id ? ' (you)' : ''),
                  ),
                  selected: payers.contains(member.id),
                  onSelected: (_) => onPayersChanged({member.id}),
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
                        controlAffinity: ListTileControlAffinity.leading,
                        value: payers.contains(member.id),
                        title: Text(ledger.nameOfMember(member)),
                        onChanged: (checked) => onPayersChanged(
                          _with(member.id, selected: checked ?? false),
                        ),
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
                        onChanged: (_) => onAmountEdited(),
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
    required this.onParticipantsChanged,
    required this.onSharesChanged,
    required this.onAmountEdited,
  });

  final GroupLedger ledger;
  final Currency? currency;
  final int? totalMinor;
  final SplitKind splitKind;

  /// Who is in the split and their relative weights, to render. Both read only:
  /// a new value goes back up through the callbacks below.
  final Set<String> participants;
  final Map<String, int> shares;

  final TextEditingController Function(String) exactControllerFor;
  final TextEditingController Function(String) percentControllerFor;
  final ValueChanged<SplitKind> onKindChanged;
  final ValueChanged<Set<String>> onParticipantsChanged;
  final ValueChanged<Map<String, int>> onSharesChanged;

  /// An amount or a percentage was typed. The controllers belong to the editor,
  /// so this only asks for a rebuild of the preview.
  final VoidCallback onAmountEdited;

  /// The weight for [memberId], nudged by [by] and never below zero.
  Map<String, int> _nudge(String memberId, int by) {
    final next = {...shares};
    next[memberId] = ((next[memberId] ?? 1) + by).clamp(0, 1 << 30);
    return next;
  }

  /// A live preview of what each person ends up owing.
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
        const _SectionTitle('Split'),
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
                  controlAffinity: ListTileControlAffinity.leading,
                  value: participants.contains(member.id),
                  title: Text(
                    ledger.nameOfMember(member) +
                        (member.id == ledger.me?.id ? ' (you)' : ''),
                  ),
                  subtitle: preview != null && participants.contains(member.id)
                      ? Text(
                          formatMoney(currency, preview[member.id] ?? 0),
                          style: moneyStyle(
                            Theme.of(context).textTheme.bodySmall!,
                          ),
                        )
                      : null,
                  onChanged: (checked) {
                    final next = {...participants};
                    if (checked ?? false) {
                      next.add(member.id);
                    } else {
                      next.remove(member.id);
                    }
                    onParticipantsChanged(next);
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
                      onChanged: (_) => onAmountEdited(),
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
                      onChanged: (_) => onAmountEdited(),
                    ),
                  ),
                  SplitKind.shares => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => onSharesChanged(_nudge(member.id, -1)),
                      ),
                      Text('${shares[member.id] ?? 1}'),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => onSharesChanged(_nudge(member.id, 1)),
                      ),
                    ],
                  ),
                  SplitKind.equal ||
                  SplitKind.unknownDefaultOpenApi => const SizedBox.shrink(),
                },
            ],
          ),
      ],
    );
  }
}

/// The category, as a chip that opens the fixed global list.
class _CategoryChip extends ConsumerWidget {
  const _CategoryChip({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final chosen = categories.where((c) => c.id == value).firstOrNull;

    return ActionChip(
      avatar: Icon(
        chosen == null ? Icons.category_outlined : categoryIcon(chosen.icon),
      ),
      label: Text(chosen?.name ?? 'Uncategorised'),
      tooltip: 'Change the category',
      onPressed: () async {
        final picked = await showModalBottomSheet<({String? id})>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (context) =>
              _CategorySheet(categories: categories, value: value),
        );
        if (picked != null) onChanged(picked.id);
      },
    );
  }
}

/// Every category, the current one marked.
class _CategorySheet extends StatelessWidget {
  const _CategorySheet({required this.categories, required this.value});

  final List<Category> categories;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(String? id, IconData icon, String name) => ListTile(
      leading: Icon(icon),
      title: Text(name),
      selected: id == value,
      trailing: id == value ? Icon(Icons.check, color: scheme.primary) : null,
      onTap: () => Navigator.of(context).pop((id: id)),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          option(null, Icons.remove_rounded, 'Uncategorised'),
          for (final category in categories)
            option(category.id, categoryIcon(category.icon), category.name),
        ],
      ),
    );
  }
}

/// The currency, as a tonal button beside the amount, opening Material's
/// search view over every currency the device knows.
class _CurrencyButton extends ConsumerWidget {
  const _CurrencyButton({required this.code, required this.onChanged});

  final String code;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final codes = currencies.keys.toList()..sort();

    return SearchAnchor(
      viewHintText: 'Search currencies',
      builder: (context, controller) => FilledButton.tonalIcon(
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

/// What has already happened to this expense.
class _History extends ConsumerWidget {
  const _History({required this.entryId, required this.ledger});

  final String entryId;
  final GroupLedger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(entryActivityProvider(entryId)).value;
    if (events == null || events.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final currency = ref
        .watch(currenciesProvider)
        .value?[ledger.group.defaultCurrency];

    // See the note in ActivityScreen: a build with nowhere to sync to must not
    // mark every line as unsynced.
    final syncs = ref.watch(syncEngineProvider) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('History', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        // Narrowed rather than switched: watchEntry asks only for this
        // expense's own snapshots, so anything else here would be a bug in the
        // query rather than a kind to render.
        for (final event in events.whereType<EntryChanged>())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ledger.nameOfActor(event.actorId)} '
                  '${describeKind(event.kind)}'
                  '${syncs && event.isProvisional ? ' — not synced yet' : ''}',
                  style: theme.textTheme.bodyMedium,
                ),
                for (final change in event.changes)
                  Text(
                    '· '
                    '${describeChange(change, currency: currency, memberNames: ledger.memberNames)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// When on the day it happened: optional, and cleared or changed here.
class _TimeChip extends StatelessWidget {
  const _TimeChip({
    required this.shown,
    required this.onPick,
    required this.onClear,
  });

  /// On this device's clock. Null when no time is recorded.
  final DateTime? shown;

  /// Null until this device's zone is known.
  final VoidCallback? onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final shown = this.shown;
    if (shown == null) {
      return ActionChip(
        avatar: const Icon(Icons.schedule_outlined),
        label: const Text('Add a time'),
        onPressed: onPick,
      );
    }
    return InputChip(
      avatar: const Icon(Icons.schedule_outlined),
      label: Text(DateFormat.jm().format(shown)),
      onPressed: onPick,
      onDeleted: onClear,
      deleteButtonTooltipMessage: 'Remove the time',
    );
  }
}

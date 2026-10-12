import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind, SplitKind;

import '../../application/entry_form.dart';
import '../../application/ledger_providers.dart';
import '../../application/local_providers.dart';
import '../../data/local/database.dart';
import '../../domain/decimal_text.dart';
import '../../domain/money_format.dart';
import '../amount_input.dart';
import '../feedback.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/amount_card.dart';
import '../widgets/entry_history.dart';
import '../widgets/avatar_view.dart';
import '../widgets/category_icon.dart';
import '../widgets/shared_element.dart';
import '../widgets/page_body.dart';
import '../widgets/remainder_field.dart';
import 'settle_up_screen.dart';

/// Creates or edits an expense.
///
/// Holds no state of its own: what has been typed lives in [EntryForm], and
/// every field reports a change there rather than keeping a copy here.
class EntryEditorScreen extends ConsumerWidget {
  const EntryEditorScreen({super.key, required this.groupId, this.entryId});

  final String groupId;
  final String? entryId;

  bool get isEditing => entryId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(groupLedgerProvider(groupId));
    final entry = ledger?.entries.where((e) => e.id == entryId).firstOrNull;
    if (entry?.row.kind == EntryKind.settlement) {
      return SettleUpScreen(groupId: groupId, entryId: entryId);
    }
    final provider = entryFormProvider(groupId, entryId: entryId);
    ref.listen(provider, (previous, next) {
      final error = next.value?.error;
      if (error != null && error != previous?.value?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    });
    final form = ref.watch(provider).value;

    if (ledger == null || form == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    return _Editor(
      ledger: ledger,
      form: form,
      controller: ref.read(provider.notifier),
    );
  }
}

class _Editor extends ConsumerWidget {
  const _Editor({
    required this.ledger,
    required this.form,
    required this.controller,
  });

  final GroupLedger ledger;
  final EntryFormState form;
  final EntryForm controller;

  String get _groupPath => '/g/${ledger.group.id}';

  Future<void> _save(BuildContext context) async {
    if (await controller.save() && context.mounted) {
      goBack(context, _groupPath);
    }
  }

  Future<void> _delete(BuildContext context) async {
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
    if (await controller.delete() && context.mounted) {
      goBack(context, _groupPath);
    }
  }

  Future<void> _pickDay(BuildContext context) async {
    final day = form.day;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(day.year, day.month, day.day),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) controller.chooseDay(picked);
  }

  /// A time picked on this device's clock happened in this device's zone.
  Future<void> _pickTime(BuildContext context, String device) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        form.occurredAt?.toLocal() ?? DateTime.now(),
      ),
    );
    if (picked == null) return;
    controller.chooseTime(
      hour: picked.hour,
      minute: picked.minute,
      zone: device,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceZoneProvider).value;
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final currency = currencies[form.currencyCode];
    final textTheme = Theme.of(context).textTheme;
    final ready = !form.saving && currency != null;

    return Scaffold(
      appBar: AppBar(
        leading: CloseButton(onPressed: () => goBack(context, _groupPath)),
        title: Text(form.isEditing ? 'Edit expense' : 'Add expense'),
        actions: [
          if (form.isEditing)
            IconButton(
              tooltip: 'Delete',
              onPressed: ready ? () => _delete(context) : null,
              icon: const Icon(Icons.delete_outline),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: ready ? () => _save(context) : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ExcludeFocus(
        excluding: form.saving,
        child: AbsorbPointer(
          absorbing: form.saving,
          child: PageBody(
            maxWidth: 640,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
              children: [
                AmountCard(
                  heroTag: form.editing == null
                      ? null
                      : ('entry-amount', form.editing!.id),
                  currency: currency,
                  currencyCode: form.currencyCode,
                  amount: form.amount,
                  autofocus: !form.isEditing,
                  onAmountChanged: controller.setAmount,
                  onCurrencyChanged: controller.chooseCurrency,
                ),
                if (currency != null &&
                    currency.code != ledger.group.defaultCurrency)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${currency.code} balances stay separate.',
                      style: textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
                SharedText(
                  tag: (
                    'entry-description',
                    form.editing?.id ?? ('draft', ledger.group.id),
                  ),
                  text: form.description,
                  style: textTheme.bodyLarge!.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: TextFormField(
                    initialValue: form.description,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What was it?',
                      hintText: 'Dinner at Toit',
                    ),
                    onChanged: controller.setDescription,
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
                      heroTag: form.editing == null
                          ? null
                          : ('entry-category', form.editing!.id),
                      value: form.categoryId,
                      onChanged: controller.chooseCategory,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.event_outlined),
                      label: Text(_dayName(form.day)),
                      tooltip: 'Change the day',
                      onPressed: () => _pickDay(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _EditorCard(
                  child: _PayerSection(
                    ledger: ledger,
                    currency: currency,
                    form: form,
                    controller: controller,
                  ),
                ),
                const SizedBox(height: 16),
                _EditorCard(
                  child: _SplitSection(
                    ledger: ledger,
                    currency: currency,
                    form: form,
                    controller: controller,
                  ),
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('Time of expense'),
                  subtitle: Text(
                    form.occurredAt == null
                        ? 'Date only'
                        : DateFormat.jm().format(form.occurredAt!.toLocal()),
                  ),
                  leading: const Icon(Icons.schedule_outlined),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TimeChip(
                      shown: form.occurredAt?.toLocal(),
                      onPick: device == null
                          ? null
                          : () => _pickTime(context, device),
                      onClear: controller.clearTime,
                    ),
                  ],
                ),
                if (form.error case final error?) ...[
                  const SizedBox(height: 16),
                  Card.filled(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                if (form.editing case final editing?) ...[
                  const SizedBox(height: 32),
                  EntryHistory(entryId: editing.id, ledger: ledger),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "Today", "Yesterday", or the date, for a day stored at UTC midnight.
  static String _dayName(DateTime day) {
    final local = DateTime(day.year, day.month, day.day);
    final daysAgo = DateUtils.dateOnly(DateTime.now()).difference(local).inDays;
    return switch (daysAgo) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat.yMMMEd().format(local),
    };
  }
}

/// Separates a money decision from the expense's supporting details.
class _EditorCard extends StatelessWidget {
  const _EditorCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card.filled(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
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
              child: Text(text, style: theme.textTheme.titleMedium),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Original participants remain editable even if they have since left.
List<Member> _membersForEntry(GroupLedger ledger, EntryFormState form) {
  final original = {
    ...?form.editing?.shares.map((share) => share.memberId),
    ...?form.editing?.payers.map((payer) => payer.memberId),
  };
  return [
    ...ledger.members,
    for (final member in ledger.pastMembers)
      if (original.contains(member.id)) member,
  ];
}

class _PayerSection extends StatelessWidget {
  const _PayerSection({
    required this.ledger,
    required this.currency,
    required this.form,
    required this.controller,
  });

  final GroupLedger ledger;
  final Currency? currency;
  final EntryFormState form;
  final EntryForm controller;

  @override
  Widget build(BuildContext context) {
    final currency = this.currency;
    final allocation = currency == null ? null : form.paidAllocation(currency);
    final members = _membersForEntry(ledger, form);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Paid by',
          action: TextButton(
            onPressed: () => controller.setSeveralPayers(!form.severalPayers),
            child: Text(form.severalPayers ? 'One person' : 'Several people'),
          ),
        ),
        if (!form.severalPayers)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final member in members)
                ChoiceChip(
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
                  selected: form.payers.contains(member.id),
                  onSelected: (_) => controller.choosePayer(member.id),
                ),
            ],
          )
        else ...[
          for (final member in members)
            _AllocationRow(
              title: ledger.nameOfMember(member),
              selected: form.payers.contains(member.id),
              onChanged: (checked) =>
                  controller.setPaying(member.id, paying: checked),
              input: !form.payers.contains(member.id)
                  ? null
                  : RemainderField(
                      key: ValueKey(('paid', member.id)),
                      label: 'Paid amount',
                      memberName: ledger.nameOfMember(member),
                      manualText: form.paidAmounts[member.id],
                      automaticText: switch (allocation?.values[member.id]) {
                        final value? => currency?.formatPlain(value),
                        null => null,
                      },
                      prefixText: currency?.symbol,
                      invalid: allocation?.invalid.contains(member.id) ?? false,
                      inputFormatters: [DecimalInputFormatter.amount(currency)],
                      onChanged: (text) =>
                          controller.setPaidAmount(member.id, text),
                    ),
            ),
          _AllocationStatus(
            error: currency == null ? null : form.paidError(currency),
            hasOverrides: form.payers.any(form.paidAmounts.containsKey),
            onReset: controller.resetPaid,
            resetLabel: 'Divide evenly',
          ),
        ],
      ],
    );
  }
}

class _SplitSection extends StatelessWidget {
  const _SplitSection({
    required this.ledger,
    required this.currency,
    required this.form,
    required this.controller,
  });

  final GroupLedger ledger;
  final Currency? currency;
  final EntryFormState form;
  final EntryForm controller;

  @override
  Widget build(BuildContext context) {
    final currency = this.currency;
    final preview = currency == null ? null : form.preview(currency);
    final allocation = switch (form.splitKind) {
      SplitKind.exact =>
        currency == null ? null : form.exactAllocation(currency),
      SplitKind.percent => form.percentAllocation(),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Split'),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(16) > 24) {
              return DropdownMenu<SplitKind>(
                key: ValueKey(form.splitKind),
                label: const Text('Split method'),
                initialSelection: form.splitKind,
                expandedInsets: EdgeInsets.zero,
                requestFocusOnTap: false,
                enableSearch: false,
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: SplitKind.equal, label: 'Equally'),
                  DropdownMenuEntry(value: SplitKind.exact, label: 'Amounts'),
                  DropdownMenuEntry(value: SplitKind.shares, label: 'Shares'),
                  DropdownMenuEntry(value: SplitKind.percent, label: '%'),
                ],
                onSelected: (kind) {
                  if (kind != null) controller.chooseSplitKind(kind);
                },
              );
            }
            return SegmentedButton<SplitKind>(
              segments: const [
                ButtonSegment(value: SplitKind.equal, label: Text('Equally')),
                ButtonSegment(value: SplitKind.exact, label: Text('Amounts')),
                ButtonSegment(value: SplitKind.shares, label: Text('Shares')),
                ButtonSegment(value: SplitKind.percent, label: Text('%')),
              ],
              selected: {form.splitKind},
              onSelectionChanged: (set) =>
                  controller.chooseSplitKind(set.first),
              showSelectedIcon: false,
            );
          },
        ),
        const SizedBox(height: 8),
        for (final member in _membersForEntry(ledger, form))
          _AllocationRow(
            title:
                ledger.nameOfMember(member) +
                (member.id == ledger.me?.id ? ' (you)' : ''),
            selected: form.participants.contains(member.id),
            subtitle: form.splitKind == SplitKind.exact
                ? null
                : switch (preview?[member.id]) {
                    final owed? => formatMoney(currency, owed),
                    null => null,
                  },
            onChanged: (checked) =>
                controller.setInSplit(member.id, included: checked),
            input: !form.participants.contains(member.id)
                ? null
                : switch (form.splitKind) {
                    SplitKind.exact => RemainderField(
                      key: ValueKey(('exact', member.id)),
                      label: 'Amount',
                      memberName: ledger.nameOfMember(member),
                      manualText: form.exactAmounts[member.id],
                      automaticText: switch (allocation?.values[member.id]) {
                        final value? => currency?.formatPlain(value),
                        null => null,
                      },
                      prefixText: currency?.symbol,
                      invalid: allocation?.invalid.contains(member.id) ?? false,
                      inputFormatters: [DecimalInputFormatter.amount(currency)],
                      onChanged: (text) =>
                          controller.setExactAmount(member.id, text),
                    ),
                    SplitKind.percent => RemainderField(
                      key: ValueKey(('percent', member.id)),
                      label: 'Percent',
                      memberName: ledger.nameOfMember(member),
                      manualText: form.percents[member.id],
                      automaticText: switch (allocation?.values[member.id]) {
                        final value? => formatPercentMicros(value),
                        null => null,
                      },
                      suffixText: '%',
                      invalid: allocation?.invalid.contains(member.id) ?? false,
                      inputFormatters: [
                        DecimalInputFormatter(percentInputPattern),
                      ],
                      onChanged: (text) =>
                          controller.setPercent(member.id, text),
                    ),
                    SplitKind.shares => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip:
                              'Fewer shares for ${ledger.nameOfMember(member)}',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () =>
                              controller.nudgeShares(member.id, -1),
                        ),
                        Text('${form.shareCountOf(member.id)}'),
                        IconButton(
                          tooltip:
                              'More shares for ${ledger.nameOfMember(member)}',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => controller.nudgeShares(member.id, 1),
                        ),
                      ],
                    ),
                    _ => null,
                  },
          ),
        if (form.splitKind == SplitKind.exact ||
            form.splitKind == SplitKind.percent)
          _AllocationStatus(
            error: currency == null ? null : form.splitError(currency),
            hasOverrides: form.participants.any(
              (form.splitKind == SplitKind.exact
                      ? form.exactAmounts
                      : form.percents)
                  .containsKey,
            ),
            onReset: controller.resetSplit,
          ),
      ],
    );
  }
}

/// A selection and its field wrap vertically when text needs more room.
class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.title,
    required this.selected,
    required this.onChanged,
    this.subtitle,
    this.input,
  });

  final String title;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final String? subtitle;
  final Widget? input;

  @override
  Widget build(BuildContext context) {
    final selection = CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: selected,
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: moneyStyle(Theme.of(context).textTheme.bodySmall!),
            ),
      onChanged: (checked) => onChanged(checked ?? false),
    );
    final input = this.input;
    if (input == null) return selection;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(16) > 20;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [selection, input],
                )
              : Row(
                  children: [
                    Expanded(child: selection),
                    SizedBox(width: 168, child: input),
                  ],
                ),
        );
      },
    );
  }
}

class _AllocationStatus extends StatelessWidget {
  const _AllocationStatus({
    required this.error,
    required this.hasOverrides,
    required this.onReset,
    this.resetLabel = 'Split evenly',
  });

  final String? error;
  final bool hasOverrides;
  final VoidCallback onReset;
  final String resetLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error case final message?)
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (hasOverrides)
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt),
            label: Text(resetLabel),
          ),
      ],
    );
  }
}

/// The category, as a chip that opens the fixed global list.
class _CategoryChip extends ConsumerWidget {
  const _CategoryChip({
    required this.value,
    required this.onChanged,
    this.heroTag,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final Object? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final chosen = categories.where((c) => c.id == value).firstOrNull;

    final icon = Icon(
      chosen == null ? Icons.category_outlined : categoryIcon(chosen.icon),
      color: Theme.of(context).colorScheme.primary,
    );
    return ActionChip(
      avatar: heroTag == null
          ? icon
          : SharedElement(tag: heroTag!, child: icon),
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

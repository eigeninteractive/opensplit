import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind, SplitKind;

import '../../application/clock_provider.dart';
import '../../application/entry_form.dart';
import '../../application/ledger_providers.dart';
import '../../application/local_providers.dart';
import '../../data/local/database.dart';
import '../../domain/calendar_date.dart';
import '../../domain/decimal_text.dart';
import '../../domain/money_format.dart';
import '../amount_input.dart';
import '../feedback.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/amount_card.dart';
import '../widgets/form_leave_guard.dart';
import '../widgets/avatar_view.dart';
import '../widgets/category_icon.dart';
import '../widgets/page_body.dart';
import '../widgets/remainder_field.dart';
import 'settle_up_screen.dart';

import '../widgets/group_access.dart';

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
    final entry = entryId == null
        ? null
        : ref.watch(entryRecordProvider(entryId!)).value;
    if (ledger != null && ledger.me?.isActive != true) {
      return const GroupUnavailableScreen();
    }
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
    return Actions(
      actions: {
        // Dismiss the active input on touch as well as on mouse clicks.
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
      },
      child: _Editor(
        ledger: ledger,
        form: form,
        controller: ref.read(provider.notifier),
      ),
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
        title: const Text('Delete this expense?'),
        content: const Text(
          'Balances will update. The expense stays in the history.',
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
    if (confirmed != true || !context.mounted) return;
    if (await controller.delete() && context.mounted) {
      goBack(context, _groupPath, result: EntryEditResult.deleted);
    }
  }

  Future<void> _pickDay(BuildContext context, DateTime now) async {
    final day = form.day;
    final initial = DateTime(day.year, day.month, day.day);
    final first = DateTime(2000);
    final last = now.add(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(first) ? initial : first,
      lastDate: initial.isAfter(last) ? initial : last,
      currentDate: now,
    );
    if (picked != null && context.mounted && controller.chooseDay(picked)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a time for the new date if needed.')),
      );
    }
  }

  /// A time picked on this device's clock happened in this device's zone.
  Future<void> _pickTime(
    BuildContext context,
    String device,
    DateTime now,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(form.occurredAt?.toLocal() ?? now),
    );
    if (picked == null || !context.mounted) return;
    controller.chooseTime(
      hour: picked.hour,
      minute: picked.minute,
      zone: device,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(clockProvider);
    final device = ref.watch(deviceZoneProvider).value;
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final currency = currencies[form.currencyCode];
    final textTheme = Theme.of(context).textTheme;
    final ready = ledger.canEdit && !form.saving && currency != null;

    return FormLeaveGuard(
      draft: form.copyWith(saving: false, error: null),
      saving: form.saving,
      fallback: _groupPath,
      builder: (context, leave) => Scaffold(
        appBar: AppBar(
          leading: CloseButton(onPressed: form.saving ? null : leave),
          title: Text(
            !ledger.canEdit
                ? 'Expense'
                : form.isEditing
                ? 'Edit expense'
                : 'Add expense',
          ),
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
                  ExcludeFocus(
                    excluding: !ledger.canEdit,
                    child: AbsorbPointer(
                      absorbing: !ledger.canEdit,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AmountCard(
                            currency: currency,
                            currencyCode: form.currencyCode,
                            amount: form.amount,
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
                          TextFormField(
                            initialValue: form.description,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'What was it?',
                              hintText: 'Dinner at Toit',
                            ),
                            onChanged: controller.setDescription,
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: _CategoryChip(
                              value: form.categoryId,
                              onChanged: controller.chooseCategory,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _WhenField(
                            day: _dayName(form.day, clock()),
                            at: form.occurredAt?.toLocal(),
                            onPickDay: () => _pickDay(context, clock()),
                            onPickTime: device == null
                                ? null
                                : () => _pickTime(context, device, clock()),
                            onClearTime: controller.clearTime,
                          ),
                          const SizedBox(height: 16),
                          _PaymentAndSplit(
                            ledger: ledger,
                            currency: currency,
                            form: form,
                            controller: controller,
                          ),
                          if (form.error case final error?) ...[
                            const SizedBox(height: 16),
                            Card.filled(
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  error,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Today", "Yesterday", or the date, for a day stored at UTC midnight.
  static String _dayName(DateTime day, DateTime now) {
    final daysAgo = calendarDay(now).difference(day).inDays;
    return switch (daysAgo) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat.yMMMEd().format(day),
    };
  }
}

/// Who paid and how it is split, each folded down to a line saying what is
/// chosen.
///
/// Most expenses are one person paying for everyone, split equally, and
/// those two lines say so without the lists behind them. Anything else is a
/// tap away, and an expense that already differs opens unfolded.
class _PaymentAndSplit extends StatelessWidget {
  const _PaymentAndSplit({
    required this.ledger,
    required this.currency,
    required this.form,
    required this.controller,
  });

  final GroupLedger ledger;
  final Currency? currency;
  final EntryFormState form;
  final EntryForm controller;

  String _names(Iterable<String> memberIds) {
    final names = [
      for (final id in memberIds)
        switch (ledger.memberById(id)) {
          final member? => ledger.titleOfMember(member),
          null => ledger.nameOf(id),
        },
    ];
    return switch (names) {
      [] => 'Nobody yet',
      [final one] => one,
      [final one, final two] => '$one and $two',
      [final first, ...final rest] => '$first and ${rest.length} others',
    };
  }

  String get _splitSummary {
    final how = switch (form.splitKind) {
      SplitKind.exact => 'By amounts',
      SplitKind.shares => 'By shares',
      SplitKind.percent => 'By percentage',
      _ => 'Equally',
    };
    final everyone = _membersForEntry(ledger, form);
    final count = form.participants.length;
    return switch (count) {
      0 => '$how, nobody chosen yet',
      1 => '$how, ${_names(form.participants)} only',
      _ when count == everyone.length => '$how between everyone',
      _ => '$how between $count of ${everyone.length} people',
    };
  }

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(16, 0, 16, 16);
    final everyone = _membersForEntry(ledger, form);

    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ExpansionTile(
            initiallyExpanded: form.severalPayers,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Paid by'),
            subtitle: Text(_names(form.payers)),
            childrenPadding: padding,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PayerSection(
                ledger: ledger,
                currency: currency,
                form: form,
                controller: controller,
              ),
            ],
          ),
          const Divider(height: 1),
          ExpansionTile(
            initiallyExpanded:
                form.splitKind != SplitKind.equal ||
                form.participants.length != everyone.length,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.call_split),
            title: const Text('Split'),
            subtitle: Text(_splitSummary),
            childrenPadding: padding,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SplitSection(
                ledger: ledger,
                currency: currency,
                form: form,
                controller: controller,
              ),
            ],
          ),
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
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
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
                  label: Text(ledger.titleOfMember(member)),
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
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(16) > 24) {
              return DropdownMenu<SplitKind>(
                label: const Text('Split method'),
                initialSelection: form.splitKind,
                expandedInsets: EdgeInsets.zero,
                requestFocusOnTap: true,
                enableSearch: false,
                selectOnly: true,
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
            title: ledger.titleOfMember(member),
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
  const _CategoryChip({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

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
      avatar: icon,
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

/// Keeps the date and its optional time together in the form.
class _WhenField extends StatelessWidget {
  const _WhenField({
    required this.day,
    required this.at,
    required this.onPickDay,
    required this.onPickTime,
    required this.onClearTime,
  });

  final String day;
  final DateTime? at;
  final VoidCallback onPickDay;
  final VoidCallback? onPickTime;
  final VoidCallback onClearTime;

  @override
  Widget build(BuildContext context) {
    final at = this.at;
    final time = at == null ? null : DateFormat.jm().format(at);
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.event_outlined),
        title: const Text('When'),
        subtitle: Text(time == null ? day : '$day · $time'),
        children: [
          ListTile(
            title: const Text('Date'),
            subtitle: Text(day),
            trailing: const SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: Icon(Icons.calendar_today_outlined),
            ),
            onTap: onPickDay,
          ),
          ListTile(
            title: const Text('Time'),
            subtitle: Text(time ?? 'Date only'),
            onTap: onPickTime,
            trailing: SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: time == null
                  ? const Icon(Icons.schedule_outlined)
                  : IconButton(
                      tooltip: 'Remove the time',
                      onPressed: onClearTime,
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

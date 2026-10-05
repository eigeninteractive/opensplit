import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:opensplit_api/opensplit_api.dart' show SplitKind;

import '../../application/entry_form.dart';
import '../../application/ledger_providers.dart';
import '../../application/local_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../domain/activity/activity_text.dart';
import '../../domain/decimal_text.dart';
import '../../domain/models/group_event.dart';
import '../../domain/money_format.dart';
import '../amount_input.dart';
import '../feedback.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/avatar_view.dart';
import '../widgets/category_icon.dart';
import '../widgets/page_body.dart';

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
    final form = ref.watch(entryFormProvider(groupId, entryId: entryId)).value;

    if (ledger == null || form == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    return _Editor(
      ledger: ledger,
      form: form,
      controller: ref.read(
        entryFormProvider(groupId, entryId: entryId).notifier,
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
              onPressed: () => _delete(context),
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
                  code: form.currencyCode,
                  onChanged: controller.chooseCurrency,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    initialValue: form.amount,
                    autofocus: !form.isEditing,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [DecimalInputFormatter.amount(currency)],
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
                    onChanged: controller.setAmount,
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
            // The details most expenses leave as they are, as chips rather
            // than a field each.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CategoryChip(
                  value: form.categoryId,
                  onChanged: controller.chooseCategory,
                ),
                ActionChip(
                  avatar: const Icon(Icons.event_outlined),
                  label: Text(_dayName(form.day)),
                  tooltip: 'Change the day',
                  onPressed: () => _pickDay(context),
                ),
                _TimeChip(
                  shown: form.occurredAt?.toLocal(),
                  onPick: device == null
                      ? null
                      : () => _pickTime(context, device),
                  onClear: controller.clearTime,
                ),
              ],
            ),
            const SizedBox(height: 32),
            _PayerSection(
              ledger: ledger,
              currency: currency,
              form: form,
              controller: controller,
            ),
            const SizedBox(height: 32),
            _SplitSection(
              ledger: ledger,
              currency: currency,
              form: form,
              controller: controller,
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
              _History(entryId: editing.id, ledger: ledger),
            ],
          ],
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
    required this.form,
    required this.controller,
  });

  final GroupLedger ledger;
  final Currency? currency;
  final EntryFormState form;
  final EntryForm controller;

  @override
  Widget build(BuildContext context) {
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
                  selected: form.payers.contains(member.id),
                  onSelected: (_) => controller.choosePayer(member.id),
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
                        value: form.payers.contains(member.id),
                        title: Text(ledger.nameOfMember(member)),
                        onChanged: (checked) => controller.setPaying(
                          member.id,
                          paying: checked ?? false,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        key: ValueKey(('paid', member.id)),
                        initialValue: form.paidAmounts[member.id],
                        enabled: form.payers.contains(member.id),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          DecimalInputFormatter.amount(currency),
                        ],
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: currency?.symbol,
                        ),
                        onChanged: (text) =>
                            controller.setPaidAmount(member.id, text),
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
          selected: {form.splitKind},
          onSelectionChanged: (set) => controller.chooseSplitKind(set.first),
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
                  value: form.participants.contains(member.id),
                  title: Text(
                    ledger.nameOfMember(member) +
                        (member.id == ledger.me?.id ? ' (you)' : ''),
                  ),
                  subtitle: switch (preview?[member.id]) {
                    final owed? => Text(
                      formatMoney(currency, owed),
                      style: moneyStyle(Theme.of(context).textTheme.bodySmall!),
                    ),
                    null => null,
                  },
                  onChanged: (checked) => controller.setInSplit(
                    member.id,
                    included: checked ?? false,
                  ),
                ),
              ),
              if (form.participants.contains(member.id))
                // Keyed by kind as well as person: an amount and a percentage
                // sit in the same place, and must not share a field's text.
                switch (form.splitKind) {
                  SplitKind.exact => SizedBox(
                    width: 110,
                    child: TextFormField(
                      key: ValueKey(('exact', member.id)),
                      initialValue: form.exactAmounts[member.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [DecimalInputFormatter.amount(currency)],
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: currency?.symbol,
                      ),
                      onChanged: (text) =>
                          controller.setExactAmount(member.id, text),
                    ),
                  ),
                  SplitKind.percent => SizedBox(
                    width: 90,
                    child: TextFormField(
                      key: ValueKey(('percent', member.id)),
                      initialValue: form.percents[member.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        DecimalInputFormatter(percentInputPattern),
                      ],
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: '%',
                      ),
                      onChanged: (text) =>
                          controller.setPercent(member.id, text),
                    ),
                  ),
                  SplitKind.shares => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => controller.nudgeShares(member.id, -1),
                      ),
                      Text('${form.shareCountOf(member.id)}'),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => controller.nudgeShares(member.id, 1),
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

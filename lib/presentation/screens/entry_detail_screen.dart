import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opensplit_api/opensplit_api.dart' show EntryKind, SplitKind;

import '../../application/ledger_providers.dart';
import '../../data/local/database.dart';
import '../../domain/models/entry.dart';
import '../../domain/money_format.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/avatar_view.dart';
import '../widgets/category_icon.dart';
import '../widgets/entry_history.dart';
import '../widgets/group_access.dart';
import '../widgets/page_body.dart';
import '../widgets/segmented_list.dart';

/// Opens an expense or settlement in a resizable sheet from the journal.
Future<void> showEntryDetailsSheet(
  BuildContext context, {
  required String groupId,
  required String entryId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  clipBehavior: Clip.antiAlias,
  // The list's drag resizes the sheet and scrolls through the record.
  enableDrag: false,
  showDragHandle: false,
  builder: (context) =>
      EntryDetailScreen._sheet(groupId: groupId, entryId: entryId),
);

/// An expense or a payment, to read: what it was, who paid, how it was
/// split and what has happened to it since.
///
/// Opening a row lands here rather than in the form, so that looking
/// something up cannot change it. Editing is one button away.
class EntryDetailScreen extends ConsumerWidget {
  const EntryDetailScreen({
    super.key,
    required this.groupId,
    required this.entryId,
  }) : _inSheet = false;

  const EntryDetailScreen._sheet({required this.groupId, required this.entryId})
    : _inSheet = true;

  final String groupId;
  final String entryId;
  final bool _inSheet;

  String get _groupPath => '/g/$groupId';

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    await context.push<void>('$_groupPath/e/$entryId/edit');
    if (!context.mounted) return;
    // Deleted from the form: there is nothing left here to come back to.
    final entry = ref.read(entryRecordProvider(entryId)).value;
    if (entry?.isDeleted == false) return;
    if (_inSheet) {
      Navigator.of(context).pop();
      return;
    }
    goBack(context, _groupPath);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(groupLedgerProvider(groupId));
    final record = ref.watch(entryRecordProvider(entryId));
    final unavailable = ledger != null && ledger.me?.isActive != true;
    if (!_inSheet && unavailable) {
      return const GroupUnavailableScreen();
    }
    // The ledger already holds the live entry when opened from its row. The
    // record follows and also covers deleted entries.
    final entry =
        record.value ??
        ledger?.entries.where((entry) => entry.id == entryId).firstOrNull;
    final isPayment = entry?.row.kind == EntryKind.settlement;
    final title = isPayment ? 'Payment' : 'Expense';
    final actions = [
      if (!unavailable &&
          ledger != null &&
          ledger.canEdit &&
          entry != null &&
          !entry.isDeleted)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.tonalIcon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.edit),
            label: const Text('Edit'),
          ),
        ),
    ];

    final content = switch ((ledger, entry)) {
      _ when unavailable => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('Group unavailable')),
      ),
      (final ledger?, final entry?) => _Detail(ledger: ledger, entry: entry),
      _ when record.hasValue && ledger != null => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('This record isn’t on this device.'),
          ),
        ),
      ),
      _ => const SliverToBoxAdapter(),
    };

    if (_inSheet) {
      final theme = Theme.of(context);
      final sheetTheme = theme.bottomSheetTheme;
      final surface =
          sheetTheme.modalBackgroundColor ??
          sheetTheme.backgroundColor ??
          theme.colorScheme.surfaceContainerLow;
      return SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.3,
          initialChildSize: 0.6,
          snap: true,
          snapSizes: const [0.6],
          builder: (context, scroll) => CustomScrollView(
            controller: scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              PinnedHeaderSliver(
                child: ColoredBox(
                  color: surface,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Center(child: _SheetHandle()),
                      AppBar(
                        primary: false,
                        forceMaterialTransparency: true,
                        leading: const CloseButton(),
                        title: Text(title),
                        actions: actions,
                      ),
                    ],
                  ),
                ),
              ),
              content,
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => goBack(context, _groupPath)),
        title: Text(title),
        actions: actions,
      ),
      body: PageBody(
        maxWidth: 640,
        child: CustomScrollView(slivers: [content]),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 32,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      decoration: BoxDecoration(
        color:
            theme.bottomSheetTheme.dragHandleColor ??
            theme.colorScheme.onSurfaceVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.ledger, required this.entry});

  final GroupLedger ledger;
  final Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = ref.watch(currenciesProvider).value?[entry.row.currency];
    final category = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((category) => category.id == entry.row.categoryId)
        .firstOrNull;
    final isPayment = entry.row.kind == EntryKind.settlement;
    String money(int amountMinor) => formatMoney(currency, amountMinor);

    final notes = entry.row.notes?.trim() ?? '';
    final at = entry.row.occurredAt;
    final when = [
      DateFormat.yMMMEd().format(entry.row.entryDate),
      if (at != null) DateFormat.jm().format(at.toLocal()),
    ].join(' · ');

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      sliver: SliverList.list(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: isPayment
                    ? scheme.tertiaryContainer
                    : scheme.secondaryContainer,
                foregroundColor: isPayment
                    ? scheme.onTertiaryContainer
                    : scheme.onSecondaryContainer,
                child: Icon(
                  isPayment
                      ? Icons.handshake_outlined
                      : categoryIcon(category?.icon ?? ''),
                  size: 28,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(isPayment),
                      style: theme.textTheme.titleLarge!.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [if (category != null) category.name, when].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            money(entry.row.amountMinor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: moneyStyle(
              theme.textTheme.displaySmall!,
            ).copyWith(color: scheme.onSurface),
          ),
          if (entry.isDeleted)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Deleted. It no longer counts towards balances.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.error,
                ),
              ),
            )
          else if (!isPayment)
            _YourPart(ledger: ledger, entry: entry, money: money),
          if (notes.isNotEmpty) ...[
            const _Heading('Note'),
            Text(notes, style: theme.textTheme.bodyLarge),
          ],
          if (!isPayment) ...[
            const _Heading('Paid by'),
            SegmentedList(
              children: [
                for (final payer in entry.payers)
                  _PersonTile(
                    ledger: ledger,
                    memberId: payer.memberId,
                    amount: money(payer.amountMinor),
                  ),
              ],
            ),
            _Heading('Split ${_splitWords(entry.row.splitKind)}'.trim()),
            SegmentedList(
              children: [
                for (final share in entry.shares)
                  _PersonTile(
                    ledger: ledger,
                    memberId: share.memberId,
                    amount: money(share.amountMinor),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          EntryHistory(entryId: entry.id, ledger: ledger),
        ],
      ),
    );
  }

  /// What the entry was: an expense's description, or who paid whom.
  String _title(bool isPayment) {
    if (!isPayment) {
      return entry.row.description.isEmpty ? 'Expense' : entry.row.description;
    }
    String name(String? memberId) => memberId == null
        ? '—'
        : memberId == ledger.me?.id
        ? 'you'
        : ledger.nameOf(memberId);
    final from = name(entry.payers.firstOrNull?.memberId);
    final to = name(entry.shares.firstOrNull?.memberId);
    return '${from == 'you' ? 'You' : from} paid $to';
  }

  static String _splitWords(SplitKind kind) => switch (kind) {
    SplitKind.equal => 'equally',
    SplitKind.exact => 'by amounts',
    SplitKind.shares => 'by shares',
    SplitKind.percent => 'by percentage',
    _ => '',
  };
}

/// What this expense meant for the person looking at it.
class _YourPart extends StatelessWidget {
  const _YourPart({
    required this.ledger,
    required this.entry,
    required this.money,
  });

  final GroupLedger ledger;
  final Entry entry;
  final String Function(int amountMinor) money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ledger.me?.id;
    var delta = 0;
    for (final payer in entry.payers) {
      if (payer.memberId == me) delta += payer.amountMinor;
    }
    for (final share in entry.shares) {
      if (share.memberId == me) delta -= share.amountMinor;
    }
    final involved =
        entry.payers.any((payer) => payer.memberId == me) ||
        entry.shares.any((share) => share.memberId == me);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        !involved
            ? 'You were not part of this.'
            : delta == 0
            ? 'You paid exactly your share.'
            : delta > 0
            ? 'You lent ${money(delta)}'
            : 'You owe ${money(-delta)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: balanceColor(theme.colorScheme, involved ? delta : 0),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// One person and the amount against their name.
class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.ledger,
    required this.memberId,
    required this.amount,
  });

  final GroupLedger ledger;
  final String memberId;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = ledger.memberById(memberId);
    return ListTile(
      leading: member == null
          ? null
          : MemberAvatar(ledger: ledger, member: member),
      title: Text(
        member == null ? ledger.nameOf(memberId) : ledger.titleOfMember(member),
      ),
      trailing: Text(
        amount,
        style: moneyStyle(
          theme.textTheme.titleMedium!,
        ).copyWith(color: theme.colorScheme.onSurface),
      ),
    );
  }
}

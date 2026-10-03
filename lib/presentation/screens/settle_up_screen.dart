import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/ledger_providers.dart';
import '../../application/settlement_form.dart';
import '../../application/local_providers.dart';
import '../../application/preferences_providers.dart';
import '../../application/sync_providers.dart';
import '../../data/local/database.dart';
import '../../domain/money_format.dart';
import '../../domain/settle/upi.dart';
import '../amount_input.dart';
import '../navigation.dart';
import '../widgets/currency_picker.dart';
import '../widgets/page_body.dart';

/// Records a payment between two members, optionally handing off to a UPI app
/// first.
///
/// Holds no state of its own: what has been chosen and typed lives in
/// [SettlementForm].
class SettleUpScreen extends ConsumerWidget {
  const SettleUpScreen({
    super.key,
    required this.groupId,
    this.fromMemberId,
    this.toMemberId,
    this.amountMinor,
    this.currency,
  });

  final String groupId;
  final String? fromMemberId;
  final String? toMemberId;
  final int? amountMinor;
  final String? currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = settlementFormProvider(
      groupId,
      fromId: fromMemberId,
      toId: toMemberId,
      amountMinor: amountMinor,
      currency: currency,
    );

    // Started on the way in, so this device's zone is known by the time a
    // settlement is recorded.
    ref.watch(deviceZoneProvider);

    // Revalidate on the way in, and this is the one screen where it is not
    // merely tidiness.
    ref.watch(groupSyncProvider(groupId));

    final ledger = ref.watch(groupLedgerProvider(groupId));
    final form = ref.watch(provider).value;
    if (ledger == null || form == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    return _SettleUp(
      ledger: ledger,
      form: form,
      controller: ref.read(provider.notifier),
    );
  }
}

class _SettleUp extends ConsumerWidget {
  const _SettleUp({
    required this.ledger,
    required this.form,
    required this.controller,
  });

  final GroupLedger ledger;
  final SettlementFormState form;
  final SettlementForm controller;

  Future<void> _record(BuildContext context, WidgetRef ref) async {
    if (!await controller.record() || !context.mounted) return;
    goBack(context, '/g/${ledger.group.id}');

    // The one place the app asks for a review: a debt has just been cleared,
    // which is the app finishing the thing it exists to do.
    final review = ref.read(reviewPromptProvider);
    unawaited(review.isDue().then((due) => due ? review.ask() : null));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencies = ref.watch(currenciesProvider).value ?? const {};
    final currency = currencies[form.currencyCode];
    final payee = form.toId == null ? null : ledger.memberById(form.toId!);
    final payeeName = payee == null ? '' : ledger.nameOfMember(payee);
    final (from, to) = (form.fromId, form.toId);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => goBack(context, '/g/${ledger.group.id}'),
        ),
        title: const Text('Settle up'),
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _MemberDropdown(
              label: 'Who is paying',
              members: ledger.settleable,
              nameOf: ledger.nameOfMember,
              meId: ledger.me?.id,
              value: from,
              onChanged: controller.choosePayer,
            ),
            const SizedBox(height: 16),
            _MemberDropdown(
              label: 'Who is being paid',
              members: ledger.settleable,
              nameOf: ledger.nameOfMember,
              meId: ledger.me?.id,
              value: to,
              excludeId: from,
              onChanged: controller.choosePayee,
            ),
            const SizedBox(height: 16),
            CurrencyPicker(
              value: form.currencyCode,
              onChanged: controller.chooseCurrency,
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: form.amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [DecimalInputFormatter.amount(currency)],
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: currency?.symbol == null
                    ? null
                    : '${currency!.symbol} ',
                errorText: form.error,
              ),
              onChanged: controller.setAmount,
            ),
            if (from != null && to != null && currency != null) ...[
              const SizedBox(height: 8),
              _OutstandingHint(
                ledger: ledger,
                from: from,
                to: to,
                currency: currency,
              ),
            ],
            const SizedBox(height: 24),
            if (currency != null && currency.code == 'INR') ...[
              _UpiSection(
                payeeName: payeeName,
                // A new payee, or their handle arriving with their profile,
                // is a new field: what it shows is never left over from
                // somebody else.
                fieldKey: ValueKey((to, form.knownHandleIn(ledger))),
                handle: form.handleIn(ledger),
                onHandleChanged: to == null ? null : controller.setHandle,
                uri: buildUpiPaymentUri(
                  payeeVpa: form.handleIn(ledger),
                  payeeName: payeeName,
                  amountMinor: currency.parseToMinor(form.amount) ?? 0,
                  currency: currency,
                ),
                onPaid: () => _record(context, ref),
              ),
              const SizedBox(height: 24),
            ],
            FilledButton.icon(
              onPressed: form.saving || currency == null
                  ? null
                  : () => _record(context, ref),
              icon: const Icon(Icons.check),
              label: const Text('Record this payment'),
            ),
            const SizedBox(height: 12),
            Text(
              'OpenSplit does not move or check money. Recording a payment '
              'here only updates the balances in this app.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows what is actually outstanding between the two chosen members, so a
/// typed amount can be sanity-checked against it.
class _OutstandingHint extends StatelessWidget {
  const _OutstandingHint({
    required this.ledger,
    required this.from,
    required this.to,
    required this.currency,
  });

  final GroupLedger ledger;
  final String from;
  final String to;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final net = ledger.balanceOf(from, currency.code);
    if (net >= 0) {
      return Text(
        '${ledger.nameOf(from)} does not owe anything in ${currency.code}.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Text(
      '${ledger.nameOf(from)} owes ${formatMoneyAbs(currency, net)} '
      'in total across this group.',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _UpiSection extends StatelessWidget {
  const _UpiSection({
    required this.payeeName,
    required this.fieldKey,
    required this.handle,
    required this.onHandleChanged,
    required this.uri,
    required this.onPaid,
  });

  final String payeeName;

  /// Identifies what the field was filled from, so a change there gives a
  /// fresh field rather than one still showing the old handle.
  final Key fieldKey;
  final String? handle;

  /// Null until somebody is chosen to be paid.
  final ValueChanged<String>? onHandleChanged;
  final Uri? uri;
  final Future<void> Function() onPaid;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Pay by UPI',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: fieldKey,
              initialValue: handle,
              enabled: onHandleChanged != null,
              decoration: InputDecoration(
                labelText: payeeName.isEmpty
                    ? 'Their UPI ID'
                    : "$payeeName's UPI ID",
                hintText: 'name@bank',
              ),
              onChanged: onHandleChanged,
            ),
            const SizedBox(height: 16),
            if (uri == null)
              Text(
                'Enter a valid UPI ID and an amount to hand off to a payment '
                'app.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (kIsWeb)
              // A browser cannot open an Android intent, but any UPI app can
              // scan the same URI off the screen.
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: uri.toString(),
                      size: 200,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Scan this with any UPI app.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _confirm(context),
                    child: const Text('I have paid — record it'),
                  ),
                ],
              )
            else
              FilledButton.tonalIcon(
                onPressed: () => _launch(context),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open UPI app'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context) async {
    final target = uri;
    if (target == null) return;

    final launched = await launchUrl(
      target,
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted) return;

    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No UPI app could be opened.')),
      );
      return;
    }
    await _confirm(context);
  }

  /// The only thing that turns a handoff into a recorded settlement.
  Future<void> _confirm(BuildContext context) async {
    final paid = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Did the payment go through?'),
        content: const Text(
          'OpenSplit has no way to check. Only say yes if your payment app '
          'confirmed it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, record it'),
          ),
        ],
      ),
    );

    if (paid ?? false) await onPaid();
  }
}

class _MemberDropdown extends StatelessWidget {
  const _MemberDropdown({
    required this.label,
    required this.members,
    required this.nameOf,
    required this.value,
    required this.onChanged,
    this.meId,
    this.excludeId,
  });

  final String label;
  final List<Member> members;

  /// Passed in rather than reached for. A member's display name lives on their
  /// account once they have one, and resolving that needs the ledger — which
  /// this widget has no business holding to render a dropdown.
  final String Function(Member) nameOf;
  final String? value;
  final String? meId;
  final String? excludeId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final member in members)
        if (member.id != excludeId) member,
    ];

    return DropdownMenu<String>(
      // DropdownMenu reads its selection once, and on later changes only
      // follows one it can find among its entries: cleared to nobody, it
      // would go on showing the last name. Keyed by the value, a different
      // value is a fresh menu that shows exactly that.
      key: ValueKey(value),
      initialSelection: options.any((m) => m.id == value) ? value : null,
      label: Text(label),
      // A group's member list is short and every name is already visible, so
      // filtering would be a text field in front of six people.
      requestFocusOnTap: false,
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: [
        for (final member in options)
          DropdownMenuEntry(
            value: member.id,
            label: nameOf(member) + (member.id == meId ? ' (you)' : ''),
          ),
      ],
      onSelected: onChanged,
    );
  }
}

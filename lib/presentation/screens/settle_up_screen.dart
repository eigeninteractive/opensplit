import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/page_body.dart';
import '../../application/providers.dart';
import '../../domain/entry_draft.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/member.dart';
import '../../domain/settle/upi.dart';
import '../format.dart';
import '../widgets/currency_picker.dart';

/// Records a payment between two members, optionally handing off to a UPI app
/// first.
///
/// The handoff and the record are deliberately separate steps. A UPI intent
/// returns no reliable confirmation — the app cannot know whether money moved —
/// so nothing is written until the user says it did. No copy on this screen may
/// suggest OpenSplit checked.
class SettleUpScreen extends ConsumerStatefulWidget {
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
  ConsumerState<SettleUpScreen> createState() => _SettleUpScreenState();
}

class _SettleUpScreenState extends ConsumerState<SettleUpScreen> {
  final _amount = TextEditingController();
  final _payeeVpa = TextEditingController();

  String? _from;
  String? _to;
  String? _currencyCode;
  String? _amountError;
  bool _saving = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _amount.dispose();
    _payeeVpa.dispose();
    super.dispose();
  }

  /// Applies route parameters and sensible defaults once the ledger arrives.
  void _prefillOnce(GroupLedger ledger, Map<String, Currency> currencies) {
    if (_prefilled) return;
    _prefilled = true;

    _from = widget.fromMemberId ?? ledger.me?.id;
    _to = widget.toMemberId;
    _currencyCode = widget.currency ?? ledger.group.defaultCurrency;

    if (widget.amountMinor != null) {
      final currency = currencies[_currencyCode];
      if (currency != null) {
        _amount.text = currency.formatPlain(widget.amountMinor!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(groupLedgerProvider(widget.groupId));
    final currencies = ref.watch(currenciesProvider).value ?? const {};

    if (ledger == null) {
      return Scaffold(appBar: AppBar(leading: const BackButton()));
    }
    _prefillOnce(ledger, currencies);

    final currency = currencies[_currencyCode];
    final payee = _to == null ? null : ledger.memberById(_to!);

    // Fill the payee's handle the first time we learn it, without stamping
    // over anything the user has typed.
    //
    // Their account's handle wins, and the member row's is the fallback for
    // somebody who has no account — which is exactly who most often needs
    // paying, since a placeholder is a real person a friend added.
    final knownVpa = payee == null ? null : ledger.upiOf(payee);
    if (_payeeVpa.text.isEmpty && knownVpa != null) {
      _payeeVpa.text = knownVpa;
    }

    final amountMinor = currency?.parseToMinor(_amount.text);
    final upiUri = buildUpiPaymentUri(
      payeeVpa: _payeeVpa.text,
      payeeName: payee == null ? '' : ledger.nameOfMember(payee),
      amountMinor: amountMinor ?? 0,
      currency: currency ?? const Currency(code: '', exponent: 2, name: ''),
    );

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => goBack(context, '/g/${widget.groupId}'),
        ),
        title: const Text('Settle up'),
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _MemberDropdown(
              label: 'Who is paying',
              members: ledger.members,
              nameOf: ledger.nameOfMember,
              meId: ledger.me?.id,
              value: _from,
              onChanged: (id) => setState(() => _from = id),
            ),
            const SizedBox(height: 16),
            _MemberDropdown(
              label: 'Who is being paid',
              members: ledger.members,
              nameOf: ledger.nameOfMember,
              meId: ledger.me?.id,
              value: _to,
              excludeId: _from,
              onChanged: (id) => setState(() => _to = id),
            ),
            const SizedBox(height: 16),
            CurrencyPicker(
              value: _currencyCode ?? ledger.group.defaultCurrency,
              onChanged: (code) => setState(() => _currencyCode = code),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: currency?.symbol == null
                    ? null
                    : '${currency!.symbol} ',
                errorText: _amountError,
              ),
              onChanged: (_) => setState(() => _amountError = null),
            ),
            if (_from != null && _to != null && currency != null) ...[
              const SizedBox(height: 8),
              _OutstandingHint(
                ledger: ledger,
                from: _from!,
                to: _to!,
                currency: currency,
              ),
            ],
            const SizedBox(height: 24),
            if (currency?.code == 'INR') ...[
              _UpiSection(
                payeeName: payee == null ? '' : ledger.nameOfMember(payee),
                vpaController: _payeeVpa,
                uri: upiUri,
                onChanged: () => setState(() {}),
                onPaid: () => _record(ledger, currency!),
              ),
              const SizedBox(height: 24),
            ],
            FilledButton.icon(
              onPressed: _saving || currency == null
                  ? null
                  : () => _record(ledger, currency),
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

  Future<void> _record(GroupLedger ledger, Currency currency) async {
    final from = _from;
    final to = _to;
    final amountMinor = currency.parseToMinor(_amount.text);

    if (from == null || to == null) {
      setState(() => _amountError = 'Choose who is paying whom.');
      return;
    }
    if (amountMinor == null) {
      setState(
        () => _amountError = currency.exponent == 0
            ? 'Enter a whole amount.'
            : 'Enter an amount with at most ${currency.exponent} decimal '
                  'places.',
      );
      return;
    }
    if (amountMinor <= 0) {
      setState(() => _amountError = 'Enter an amount greater than zero.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(entryRepositoryProvider)
          .create(
            EntryDraft.settlement(
              groupId: widget.groupId,
              currency: currency.code,
              amountMinor: amountMinor,
              fromMemberId: from,
              toMemberId: to,
            ),
            createdBy: ledger.me?.id ?? from,
          );

      if (!mounted) return;
      goBack(context, '/g/${widget.groupId}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _amountError = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    required this.vpaController,
    required this.uri,
    required this.onChanged,
    required this.onPaid,
  });

  final String payeeName;
  final TextEditingController vpaController;
  final Uri? uri;
  final VoidCallback onChanged;
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
            TextField(
              controller: vpaController,
              decoration: InputDecoration(
                labelText: payeeName.isEmpty
                    ? 'Their UPI ID'
                    : "$payeeName's UPI ID",
                hintText: 'name@bank',
              ),
              onChanged: (_) => onChanged(),
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

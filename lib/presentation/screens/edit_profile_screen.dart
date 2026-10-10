import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/ledger_providers.dart';
import '../../data/local/database.dart';
import '../../domain/settle/upi.dart';
import '../navigation.dart';
import '../widgets/page_body.dart';
import '../widgets/sync_status_notice.dart';

/// Which field the editor opens on.
enum ProfileField { name, upi }

/// Edits the name and payment handle everybody in your groups reads.
///
/// Short-lived on purpose: the fields are filled once, from the profile as it
/// is when the editor opens, and nothing outside can change them underneath
/// somebody typing. The account page itself only ever shows the stored
/// profile.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, this.focus = ProfileField.name});

  final ProfileField focus;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _upi = TextEditingController();

  /// What the fields were filled with, which is what "unchanged" means.
  ({String name, String upi})? _original;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Opened straight from a link, the profile may still be on its way.
    ref.listenManual(
      myProfileProvider,
      (_, next) => _fill(next.value),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _upi.dispose();
    super.dispose();
  }

  void _fill(Profile? profile) {
    if (_original != null || profile == null) return;
    final original = (
      name: profile.displayName ?? '',
      upi: profile.upiVpa ?? '',
    );
    _name.text = original.name;
    _upi.text = original.upi;
    setState(() => _original = original);
  }

  bool get _changed {
    final original = _original ?? (name: '', upi: '');
    return _name.text.trim() != original.name ||
        _upi.text.trim() != original.upi;
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(myProfileControllerProvider.notifier)
          .save(displayName: _name.text.trim(), upiVpa: _upi.text.trim());
      if (mounted) goBack(context, '/account');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save. $error')));
    }
  }

  /// Asked only when leaving would lose something. Popping directly is not
  /// held back by the [PopScope] below, which guards the system back gesture.
  Future<void> _leave() async {
    if (_changed && !await _confirmDiscard()) return;
    if (mounted) goBack(context, '/account');
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ready = _original != null;
    // Still reading the device, as against waiting for a profile this device
    // has never received: only the second is worth a spinner.
    final readingSaved = !ref.watch(myProfileProvider).hasValue;

    return ListenableBuilder(
      listenable: Listenable.merge([_name, _upi]),
      builder: (context, _) => PopScope(
        canPop: !_changed,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: _leave,
            ),
            title: const Text('Edit profile'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: ready && _changed && !_saving ? _save : null,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          body: PageBody(
            child: !ready
                ? readingSaved
                      ? const SavedDataLoading(label: 'Loading your profile')
                      : const Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: 'Waiting for your profile',
                          ),
                        )
                : Form(
                    key: _form,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      children: [
                        TextFormField(
                          controller: _name,
                          autofocus: widget.focus == ProfileField.name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            helperText:
                                'What everybody in your groups sees. Changing '
                                'it here changes it everywhere, including for '
                                'them.',
                            helperMaxLines: 3,
                          ),
                          // A blank name would look saved while the member
                          // row's name quietly carried on everywhere else.
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Your name cannot be blank.'
                              : null,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _upi,
                          autofocus: widget.focus == ProfileField.upi,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (_changed) _save();
                          },
                          decoration: const InputDecoration(
                            labelText: 'UPI ID (optional)',
                            hintText: 'you@bank',
                            helperText:
                                'Lets people in your groups open their UPI app '
                                'to pay you. OpenSplit never handles the '
                                'money.',
                            helperMaxLines: 3,
                          ),
                          validator: (value) {
                            final upi = (value ?? '').trim();
                            return upi.isEmpty || isValidUpiVpa(upi)
                                ? null
                                : 'That does not look like a UPI ID.';
                          },
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

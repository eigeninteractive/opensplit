import 'package:material_ui/material_ui.dart';

import '../navigation.dart';

/// Protects a form's changed draft with the standard discard dialog.
///
/// [draft] must have value equality and omit transient saving/error state.
/// Successful saves can navigate directly; [builder]'s callback is for Close
/// and Back, which must also respect an in-flight save.
class FormLeaveGuard extends StatefulWidget {
  const FormLeaveGuard({
    super.key,
    required this.draft,
    required this.saving,
    required this.fallback,
    required this.builder,
  });

  final Object draft;
  final bool saving;
  final String fallback;
  final Widget Function(BuildContext context, VoidCallback leave) builder;

  @override
  State<FormLeaveGuard> createState() => _FormLeaveGuardState();
}

class _FormLeaveGuardState extends State<FormLeaveGuard> {
  late final Object _original = widget.draft;
  bool _asking = false;

  bool get _changed => widget.draft != _original;

  Future<void> _leave() async {
    if (widget.saving || _asking) return;
    if (_changed) {
      _asking = true;
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
      _asking = false;
      if (discard != true) return;
    }
    if (mounted && !widget.saving) goBack(context, widget.fallback);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_changed && !widget.saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: widget.builder(context, _leave),
  );
}

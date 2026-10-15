import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/backend_providers.dart';
import '../../application/preferences_providers.dart';
import '../../data/web/release_updates.dart';

/// Keeps navigation and saved data available while an incompatible app updates.
class UpdateRequiredNotice extends ConsumerStatefulWidget {
  const UpdateRequiredNotice({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateRequiredNotice> createState() =>
      _UpdateRequiredNoticeState();
}

class _UpdateRequiredNoticeState extends ConsumerState<UpdateRequiredNotice> {
  bool _updating = false;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      if (kIsWeb) {
        await updateAndRestart();
      } else {
        await ref.read(appUpdateServiceProvider).updateRequired();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open the update. Try again when the new release is available.',
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(requiresAppUpdateProvider)) return widget.child;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: colors.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error ??
                          'Update required. Saved data is read-only. Pending changes are kept.',
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                  ),
                  FilledButton(
                    onPressed: _updating ? null : _update,
                    child: Text(
                      _updating ? 'Opening update…' : 'Update OpenSplit',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// A mutation-only route has no work to offer until this app is updated.
class RequireCurrentApp extends ConsumerWidget {
  const RequireCurrentApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(requiresAppUpdateProvider)
      ? Scaffold(
          appBar: AppBar(leading: const BackButton()),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Update OpenSplit to make changes. Your saved data is still available.',
              ),
            ),
          ),
        )
      : child;
}

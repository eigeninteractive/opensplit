import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';

/// What a screen says when there is genuinely nothing to show.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  /// Shown above the title, on a tinted disc. Outlined variants read better
  /// at this size than filled ones.
  final IconData icon;

  final String title;
  final String message;

  /// The one thing to do about it, if there is one.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Icon(
                      icon,
                      size: 48,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Previews the layout, which has to be checked by eye rather than asserted.
@Preview(name: 'Empty state', group: 'Empty', size: Size(360, 300))
Widget emptyStatePreview() => const MaterialApp(
  home: Scaffold(
    body: EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'Nothing yet',
      message: 'Add the first expense and balances appear straight away.',
    ),
  ),
);

/// The same widget in dark.
@Preview(name: 'Empty state (dark)', group: 'Empty', size: Size(360, 300))
Widget emptyStateDarkPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: const Scaffold(
    body: EmptyState(
      icon: Icons.groups_outlined,
      title: 'No groups yet',
      message: 'Make one for a trip, a flat, or a single dinner.',
    ),
  ),
);

import 'package:flutter/material.dart';
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

  /// Etched behind the text. Outlined variants read better at this scale than
  /// filled ones, which turn into a blob once the opacity drops.
  final IconData icon;

  final String title;
  final String message;

  /// The one thing to do about it, if there is one.
  final Widget? action;

  /// Large enough to be a texture rather than a picture. Below roughly 100 it
  /// stops being a wash and starts looking like an icon somebody put in the
  /// wrong layer.
  static const double _iconSize = 156;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: _iconSize,
                // Tuned against `surface` in both brightnesses: any lighter and
                // it disappears in light mode, any heavier and it competes with
                // the body text in dark mode, where the same alpha carries
                // further against a dark ground.
                color: scheme.onSurface.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.06 : 0.05,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                if (action != null) ...[const SizedBox(height: 20), action!],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Previews the etched treatment, which is the part that has to be checked by
/// eye rather than asserted: the alpha is chosen against a real surface.
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

/// The same widget in dark, where the alpha has to do a different job.
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

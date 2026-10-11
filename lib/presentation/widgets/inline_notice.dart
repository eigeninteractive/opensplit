import 'package:material_ui/material_ui.dart';

/// A contained notice among page content, using the theme's filled card shape.
///
/// Actions keep their own Material button behaviour and stack when they cannot
/// fit. Reserve [isError] for changes that failed, rather than routine advice.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = isError ? scheme.onErrorContainer : scheme.onSurface;

    return Card.filled(
      color: isError ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: isError ? foreground : scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isError ? foreground : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

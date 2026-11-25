import 'package:material_ui/material_ui.dart';

/// Separates two ways to continue in the sign-in forms.
class AuthMethodDivider extends StatelessWidget {
  const AuthMethodDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        spacing: 12,
        children: [
          const Expanded(child: Divider(height: 1)),
          Text(
            'or',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

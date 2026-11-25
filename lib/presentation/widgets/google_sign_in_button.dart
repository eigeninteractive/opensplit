import 'package:material_ui/material_ui.dart';

/// Google’s light or dark sign-in treatment, with a native button and label.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Google publishes a different background and border for each theme.
    // The artwork comes from its Android + Web button pack.
    final (variant, fill, border, foreground) = dark
        ? (
            'dark',
            const Color(0xFF131314),
            const Color(0xFF8E918F),
            const Color(0xFFE3E3E3),
          )
        : (
            'light',
            Colors.white,
            const Color(0xFF747775),
            const Color(0xFF1F1F1F),
          );
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: fill,
        disabledBackgroundColor: fill,
        foregroundColor: foreground,
        disabledForegroundColor: foreground.withValues(alpha: 0.6),
        side: BorderSide(color: border),
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: 'GoogleSansButton',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 20 / 14,
          letterSpacing: 0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/google_sign_in/google-sign-in-$variant.png',
            width: 20,
            height: 20,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('Continue with Google', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

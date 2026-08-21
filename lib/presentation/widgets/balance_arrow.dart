import 'package:flutter/material.dart';

import '../theme.dart';

/// Which way a balance goes, as a shape.
///
/// Direction is already carried by the wording next to every balance in this
/// app, and by colour. Neither is enough on its own: wording needs reading, and
/// roughly one man in twelve cannot separate the green from the red. An arrow
/// is a third signal that survives both — it is legible at a glance and it does
/// not depend on hue at all.
///
/// Two named icons rather than one glyph rotated in code. The rotation trick
/// saves an icon and costs a reader working out which direction `turns: 0.5`
/// leaves you pointing; `arrow_upward` and `arrow_downward` say what they are.
/// Rounded variants, to match the shape language of the rest of Material 3.
///
/// Renders nothing at all for a settled balance. A zero with an arrow beside it
/// would be claiming a direction that does not exist.
class BalanceArrow extends StatelessWidget {
  const BalanceArrow({super.key, required this.balanceMinor, this.size});

  final int balanceMinor;

  /// Defaults to slightly under the surrounding text size, so the arrow reads
  /// as punctuation on the number rather than as an icon in its own right.
  final double? size;

  @override
  Widget build(BuildContext context) {
    if (balanceMinor == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final owed = balanceMinor > 0;

    return Icon(
      owed ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      size: size ?? (DefaultTextStyle.of(context).style.fontSize ?? 14) * 1.1,
      color: balanceColor(scheme, balanceMinor),
      // The text beside it already says which way this goes; a screen reader
      // announcing "upward arrow" as well would be noise.
      semanticLabel: null,
    );
  }
}

/// An arrow and an amount, as one unit.
///
/// The amount is rendered without a sign, because the arrow carries it. A minus
/// sign and a downward arrow saying the same thing is redundant, and "-₹500"
/// read aloud is a worse sentence than "you owe ₹500".
class BalanceAmount extends StatelessWidget {
  const BalanceAmount({
    super.key,
    required this.balanceMinor,
    required this.text,
    required this.semanticsLabel,
    this.style,
  });

  final int balanceMinor;

  /// The already-formatted, unsigned amount.
  final String text;

  /// What a screen reader should say instead — in words, with the direction.
  final String semanticsLabel;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = (style ?? DefaultTextStyle.of(context).style).copyWith(
      color: balanceColor(scheme, balanceMinor),
      fontWeight: FontWeight.w600,
    );

    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BalanceArrow(
              balanceMinor: balanceMinor,
              size: (resolved.fontSize ?? 14) * 1.1,
            ),
            if (balanceMinor != 0) const SizedBox(width: 2),
            Text(text, style: resolved),
          ],
        ),
      ),
    );
  }
}

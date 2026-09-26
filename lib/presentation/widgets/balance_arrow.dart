import 'package:flutter/material.dart';

import '../theme.dart';

/// Which way a balance goes, as a shape.
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

  /// Carries the weight and the face, and only the colour is applied over it.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = (style ?? DefaultTextStyle.of(context).style).copyWith(
      color: balanceColor(scheme, balanceMinor),
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

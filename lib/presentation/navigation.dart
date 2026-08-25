import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Goes back one screen, or to [fallback] when there is no back to go to.
///
/// Both halves are needed because either one alone is wrong somewhere.
///
/// A plain pop is wrong for a link opened from outside the app. An invite or an
/// App Link drops someone straight onto a group with a single page in the
/// stack, and a back button that can only pop is a dead control on exactly the
/// screen a new user arrives at.
///
/// A plain `go` is wrong everywhere else, and is what this app used to do. `go`
/// replaces the whole route stack and reports the result to the engine as a
/// forward navigation, so tapping back pushed a *new* browser history entry
/// rather than returning to the previous one. The browser's own back button
/// then went forward again, into the screen the user had just left.
void goBack(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

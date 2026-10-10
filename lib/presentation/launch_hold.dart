import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Keeps the platform's launch screen up until the first screen can show what
/// is saved on this device, rather than a placeholder for it.
///
/// Flutter takes down the Android splash, and fires the `flutter-first-frame`
/// event that removes the web loader, when it renders its first frame. [begin]
/// defers that frame. Widgets still build and lay out underneath, so each
/// screen's own queries run exactly as they would otherwise; only the pixels
/// wait. The frame is let through once a built frame contains no
/// [LaunchPlaceholder], or after a time limit, so a slow disk falls back to the
/// placeholder instead of a long splash.
///
/// Only placeholders for local data take part. Anything waiting on the network
/// draws as usual, because a launch screen held on a connection is the slow,
/// online-only start this exists to avoid.
abstract final class LaunchHold {
  static int _placeholders = 0;
  static bool _holding = false;
  static Timer? _limit;

  /// Whether the first frame is still being held back.
  static bool get isHolding => _holding;

  /// Defers the first frame. Call once, before `runApp`.
  ///
  /// The [limit] is how long a launch may wait on the local database. Opening
  /// it usually takes a fraction of that; the limit is for a cold disk or a
  /// debug build.
  static void begin({Duration limit = const Duration(milliseconds: 800)}) {
    if (_holding) return;
    _holding = true;
    WidgetsBinding.instance.deferFirstFrame();
    _limit = Timer(limit, _release);
    _checkAfterNextFrame(settled: false);
  }

  /// Releases the frame once two frames in a row have had nothing to wait for.
  ///
  /// Two, because the router builds its first page a frame after the app
  /// itself, and that page may be the one with a placeholder in it.
  static void _checkAfterNextFrame({required bool settled}) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_holding) return;
      if (_placeholders > 0) return _checkAfterNextFrame(settled: false);
      if (settled) return _release();
      _checkAfterNextFrame(settled: true);
      SchedulerBinding.instance.scheduleFrame();
    });
  }

  static void _release() {
    if (!_holding) return;
    _holding = false;
    _limit?.cancel();
    _limit = null;
    WidgetsBinding.instance.allowFirstFrame();
  }

  /// Forgets any hold, for tests that begin one.
  @visibleForTesting
  static void reset() {
    _release();
    _placeholders = 0;
  }
}

/// Marks [child] as standing in for saved data that is still being read.
///
/// While one of these is on screen, [LaunchHold] keeps the launch screen up.
/// After launch it has no effect. Works in both box and sliver positions.
class LaunchPlaceholder extends StatefulWidget {
  const LaunchPlaceholder({super.key, required this.child});

  final Widget child;

  @override
  State<LaunchPlaceholder> createState() => _LaunchPlaceholderState();
}

class _LaunchPlaceholderState extends State<LaunchPlaceholder> {
  @override
  void initState() {
    super.initState();
    LaunchHold._placeholders++;
  }

  @override
  void dispose() {
    LaunchHold._placeholders--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The caret's blink. The web app draws no caret of its own (glyphTheme.ts sets only `caret-color`): it is the
/// browser's, which stands solid for half a second and is gone for half a second, with no fade, and starts again
/// solid whenever it moves or something is typed.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Blinks a view's `caretOpacity`.
class CaretBlink {
  CaretBlink(this.opacity);

  /// Chromium's caret blink interval: on for this long, off for this long.
  static const Duration half = Duration(milliseconds: 500);

  final ValueNotifier<double> opacity;
  Timer? _timer;

  bool get running => _timer != null;

  /// Starts the blink from solid; called again whenever the caret moves, so it never vanishes under a moving
  /// hand.
  void restart() {
    _timer?.cancel();
    opacity.value = 1;
    _timer = Timer.periodic(half, (_) => opacity.value = opacity.value == 0 ? 1 : 0);
  }

  /// Stops the blink and leaves the caret solid (it is not drawn at all without focus).
  void stop({bool solid = true}) {
    _timer?.cancel();
    _timer = null;
    if (solid) opacity.value = 1;
  }
}

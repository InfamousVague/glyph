/// A tap on a box drawn in the words: a to-do's `[ ]` (`task_toggle.dart`) or a choice's `( )`
/// (`choices.dart`). Both answer a plain press of the main button in a note that can be edited, landing on the
/// box's three characters or within a thumb's slop of them, and both take the press before the caret moves. Ports
/// `src/app/editor/boxTaps.ts`.
///
/// What differs: the page's `MouseEvent` is Flutter's pointer-down, whose modifier keys are the hardware
/// keyboard's.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../editor.dart';

/// How far outside the drawn box a tap still counts, in px: a box is small under a thumb.
const double _slop = 8;

/// A view that cannot be typed in whose boxes still take a tap: the Academy's preview, where a choice is learned
/// by picking one.
final Facet<bool, bool> boxTapsWhileReadOnly = Facet.define<bool, bool>(combine: (values) => values.any((value) => value));

/// Whether `event` is a plain press - the main button, no modifier - in a note that can be changed, or whose boxes
/// can.
bool plainPress(PointerDownEvent event, EditorViewLike view) {
  final changeable = !view.state.readOnly || view.state.facet(boxTapsWhileReadOnly);
  final keys = HardwareKeyboard.instance;
  final main = event.kind != PointerDeviceKind.mouse || event.buttons == kPrimaryButton || event.buttons == 0;
  return main && changeable && !keys.isShiftPressed && !keys.isMetaPressed && !keys.isControlPressed && !keys.isAltPressed;
}

/// Whether a tap at `at` lands on the characters `from`-`to`, or near enough to them.
bool tapsRange(EditorViewLike view, Offset at, int from, int to) {
  final start = view.coordsAtPos(from, 1), end = view.coordsAtPos(to, -1);
  if (start == null || end == null) return false;
  return at.dx >= start.left - _slop && at.dx <= end.right + _slop && at.dy >= start.top - _slop && at.dy <= start.bottom + _slop;
}

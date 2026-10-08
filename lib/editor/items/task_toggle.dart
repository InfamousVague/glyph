/// A tap on a to-do's box ticks it, and another clears it. Only the box: the words beside it are for writing, and
/// a tap there puts the caret in them as ever. Ports the handler of `src/app/editor/taskToggle.ts`; its `boxAt`
/// and `toggleBox` are `lib/editor/commands/task_toggle.dart`'s, and are said again from here.
///
/// The change is an ordinary edit - one undo, saved like typing - so a linked to-do's task follows it.
library;

import 'dart:ui' show Offset;

import 'package:glacier/glacier.dart' show HapticKind, haptic;

import '../commands/task_toggle.dart';
import '../editor.dart';
import 'box_taps.dart';

export '../commands/task_toggle.dart' show boxAt, toggleBox;

/// The box a tap at `at` lands on, or null.
({int from, int to, bool done})? _boxUnder(EditorViewLike view, Offset at) {
  final pos = view.posAtCoords(at, precise: false);
  if (pos == null) return null;
  final box = boxAt(view.state, pos);
  return box != null && tapsRange(view, at, box.from, box.to) ? box : null;
}

final Extension _taskToggle = EditorViewLike.eventHandlers(
  EditorEventHandlers(
    pointerDown: (event, view) {
      if (!plainPress(event, view)) return false;
      final box = _boxUnder(view, event.position);
      if (box == null) return false;
      // Taken here, before the caret moves: a tap on the box ticks it and leaves the caret where it was.
      view.dispatch(toggleBox(view.state, box));
      haptic(HapticKind.selection);
      return true;
    },
  ),
);

/// A tap on a to-do's box ticks or clears it.
Extension taskToggle() => _taskToggle;

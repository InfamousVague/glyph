/// Which presses on a drawn board are the board's, and which are the note's.
///
/// On the page a board is a widget CodeMirror still hears (`ignoreEvent` keeps only the + field and the line under
/// the board from it: boards/widget.ts), and each thing on the board that answers a press takes the press away
/// from the editor itself: a card's words, its tick, its arrows and its More, a chip, a column's + (boards/press.ts
/// `press`, which prevents the mouse's default). A press anywhere else on the board, between its cards or beside
/// them, reaches the editor like a press on any block: the caret goes to the fence and the board steps aside for
/// its lines, which is how the fence is opened from the board itself.
///
/// Here a board's widget says which presses it keeps ([BoardWidget.takesPointer]). The things that answer a press
/// wear [BoardPress], and a press is the board's when it lands on one ([onBoardPress]); any other is the editor's.
/// Scrolling a lane or the board sideways is neither: a scroll view takes its own drag whoever has the press.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class _Mark {
  const _Mark();
}

const Object _mark = _Mark();

/// Something on a board that answers a press itself: the press never reaches the editor.
class BoardPress extends MetaData {
  const BoardPress({super.key, required Widget super.child}) : super(metaData: _mark, behavior: HitTestBehavior.deferToChild);
}

/// Whether `event` lands on something that wears [BoardPress].
bool onBoardPress(PointerEvent event) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
  for (final entry in result.path) {
    final target = entry.target;
    if (target is RenderMetaData && identical(target.metaData, _mark)) return true;
  }
  return false;
}

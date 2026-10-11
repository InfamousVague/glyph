/// Which line the + beside the line is drawn on, if any (insert_plus.dart draws it): the pure half, so every rule
/// is a test (test/editor/plus/plus_line_test.dart). A port of `src/app/editor/plusLine.ts`.
///
/// Matt chose the rule: "EMPTY LINES ONLY, on every platform, Mac hover included". An empty line is one with no
/// words (core/item_syntax.dart [lineWords]): blank, or only a list's, a to-do's or a quote's lead. The first
/// letter typed makes the line one with words, and the + goes. So it never sits beside a sentence being written,
/// and a note being read with the caret in a paragraph shows nothing.
///
/// And only where adding to the note makes sense: a view that can be edited and has the focus (or has handed it to
/// the + or its list), one caret and no selection (a selection belongs to press and hold), a note the screen says
/// is being written (not a notebook's index or a canvas, no AI run writing into it), and a line outside the front
/// matter and outside fenced code, where a picture or a place would be words of the block.
///
/// What differs: nothing but the types' names (`PlusContext` is a class with named fields).
library;

import '../../core/front_matter.dart';
import '../../core/item_syntax.dart';
import '../state/state.dart';
import '../state/text.dart';
import '../view/lines.dart';

/// Where the view stands, for [plusLine].
class PlusContext {
  const PlusContext({required this.focused, required this.editable, required this.allowed});

  /// The view has focus, or the + or its list has.
  final bool focused;

  /// The view can be typed in.
  final bool editable;

  /// The screen allows it: a note of words, shown, with nothing writing into it.
  final bool allowed;
}

/// Whether line `number` is inside the note's front matter. Only as many lines as front matter can run to are
/// read ([frontMatterLines]).
bool _inFrontMatter(EditorState state, int number) {
  final doc = state.doc;
  final most = doc.lines < frontMatterLines ? doc.lines : frontMatterLines;
  final first = <String>[for (var i = 1; i <= most; i += 1) doc.line(i).text];
  return number <= frontMatterEnd(first);
}

/// The caret's line when the + belongs beside it, or null.
Line? plusLine(EditorState state, PlusContext context) {
  if (!context.focused || !context.editable || !context.allowed) return null;
  final selection = state.selection;
  if (selection.ranges.length != 1 || !selection.main.empty) return null;
  final line = state.doc.lineAt(selection.main.head);
  if (lineWords(line.text).isNotEmpty) return null;
  if (_inFrontMatter(state, line.number) || docLineInFence(state.doc, line.number)) return null;
  return line;
}

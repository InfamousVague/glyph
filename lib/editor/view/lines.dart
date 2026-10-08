/// The lines an extension looks at: the ones on screen, which is all a view plugin's decorations may cover, and
/// the ones the selection touches, where marks are shown as written so they can be edited. Ports the half of
/// `src/app/editor/lines.ts` that reads the view and the state; the half that reads only the note's text is
/// `lib/editor/syntax/lines.dart`.
///
/// What differs: nothing but the names of the types (`EditorViewLike` for `EditorView`, `Doc` for `Text`).
library;

import '../state/state.dart';
import '../state/text.dart';
import 'plugin.dart';

/// Calls `visit` with every line inside the view's visible ranges, in order.
void forEachVisibleLine(EditorViewLike view, void Function(Line line) visit) {
  final doc = view.state.doc;
  for (final range in view.visibleRanges) {
    var line = doc.lineAt(range.from);
    for (;;) {
      visit(line);
      if (line.to >= range.to || line.number >= doc.lines) break;
      line = doc.line(line.number + 1);
    }
  }
}

/// A line that opens or closes fenced code: three backticks or three tildes.
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// Calls `visit` with every line of `doc` outside fenced code, in order; the fence lines themselves are skipped
/// too. A fence closes on the marker it opened with, so a `~~~` inside a ``` block is the block's words.
void forEachDocLineOutsideFences(Doc doc, void Function(Line line) visit) {
  String? fence;
  for (var n = 1; n <= doc.lines; n += 1) {
    final line = doc.line(n);
    final marker = _fence.firstMatch(line.text)?.group(1);
    if (marker != null) {
      fence = fence == null ? marker : (fence == marker ? null : fence);
      continue;
    }
    if (fence == null) visit(line);
  }
}

/// Whether line `number` of `doc` is fenced code, or a fence's own line: the lines [forEachDocLineOutsideFences]
/// skips.
bool docLineInFence(Doc doc, int number) {
  String? fence;
  final last = number < doc.lines ? number : doc.lines;
  for (var n = 1; n <= last; n += 1) {
    final marker = _fence.firstMatch(doc.line(n).text)?.group(1);
    if (n == number) return fence != null || marker != null;
    if (marker != null) fence = fence == null ? marker : (fence == marker ? null : fence);
  }
  return false;
}

/// The numbers of the lines the selection touches, every range and every line between its ends.
Set<int> selectedLines(EditorState state) {
  final lines = <int>{};
  for (final range in state.selection.ranges) {
    final first = state.doc.lineAt(range.from).number;
    final last = state.doc.lineAt(range.to).number;
    for (var n = first; n <= last; n += 1) {
      lines.add(n);
    }
  }
  return lines;
}

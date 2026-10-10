/// What a copy or a cut takes out of a note, and how a paste goes in: @codemirror/view input.ts `copiedRange`, its
/// `copy`/`cut` handler and `doPaste`, which the page has from CodeMirror and adds nothing to.
///
/// With something selected, the selected words. With nothing selected, the whole line the caret is on: Ctrl-C
/// copies the line's words, Ctrl-X takes the line and its break out, and the words pasted back with nothing
/// selected go in as a line of their own above the caret's line, the caret staying in its place in its own line.
///
/// What is left out: the clipboard's output and input filters, which nothing in the app registers.
library;

import '../state/change.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/text.dart';

/// `copiedRange`'s answer: the words for the clipboard, the ranges a cut deletes, and whether it took whole lines.
class Copied {
  const Copied(this.text, this.ranges, {required this.linewise});

  final String text;
  final List<({int from, int to})> ranges;
  final bool linewise;
}

/// The words a copy takes: each selected range, joined by the note's line break; or, with nothing selected, the
/// line of each caret (a line with two carets once).
Copied copiedRange(EditorState state) {
  final content = <String>[], ranges = <({int from, int to})>[];
  var linewise = false;
  for (final range in state.selection.ranges) {
    if (range.empty) continue;
    content.add(state.sliceDoc(range.from, range.to));
    ranges.add((from: range.from, to: range.to));
  }
  if (content.isEmpty) {
    // Nothing selected, do a line-wise copy
    var upto = -1;
    for (final range in state.selection.ranges) {
      final line = state.doc.lineAt(range.from);
      if (line.number > upto) {
        content.add(line.text);
        ranges.add((from: line.from, to: line.to + 1 < state.doc.length ? line.to + 1 : state.doc.length));
      }
      upto = line.number;
    }
    linewise = true;
  }
  return Copied(content.join(state.lineBreak), ranges, linewise: linewise);
}

/// The words of the last copy that took whole lines, or null when the last copy took a selection: CodeMirror's
/// `lastLinewiseCopy`, one for every editor as there.
String? lastLinewiseCopy;

/// What a copy or a cut of `state` does: the words for the clipboard (null when there is nothing to take: an empty
/// selection is still its line) and, for a cut of a note that can be changed, the edit that takes them out.
({String? text, TransactionSpec? cut}) copyOf(EditorState state, {required bool cut}) {
  final copied = copiedRange(state);
  if (copied.text.isEmpty && !copied.linewise) return (text: null, cut: null);
  lastLinewiseCopy = copied.linewise ? copied.text : null;
  return (
    text: copied.text,
    cut: cut && !state.readOnly
        ? TransactionSpec(
            changes: <ChangeSpec>[for (final range in copied.ranges) ChangeSpec(from: range.from, to: range.to)],
            scrollIntoView: true,
            userEvent: 'delete.cut',
          )
        : null,
  );
}

/// `doPaste`: how `input` goes into `state`. Lines that were copied whole, pasted with nothing selected, go in as
/// lines above the caret's; as many lines as there are ranges go one to each; anything else replaces the selection.
TransactionSpec pasteOf(EditorState state, String input) {
  final text = state.toText(input);
  final ranges = state.selection.ranges;
  final byLine = text.lines == ranges.length;
  final linewise = lastLinewiseCopy != null && ranges.every((range) => range.empty) && lastLinewiseCopy == text.toString();
  var i = 1;
  final TransactionSpec changes;
  if (linewise) {
    var lastLine = -1;
    changes = state.changeByRange((range) {
      final line = state.doc.lineAt(range.from);
      if (line.from == lastLine) return RangeChange(range: range);
      lastLine = line.from;
      final Doc insert = state.toText((byLine ? text.line(i++).text : input) + state.lineBreak);
      return RangeChange(
        changes: ChangeSpec(from: line.from, insert: insert),
        range: EditorSelection.cursor(range.from + insert.length),
      );
    });
  } else if (byLine) {
    changes = state.changeByRange((range) {
      final line = text.line(i++);
      return RangeChange(
        changes: ChangeSpec(from: range.from, to: range.to, insert: line.text),
        range: EditorSelection.cursor(range.from + line.length),
      );
    });
  } else {
    changes = state.replaceSelection(text);
  }
  return changes;
}

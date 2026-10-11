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

/// The marker of a line that opens or closes fenced code, kept for every line of a document (`LineFact`): a
/// keystroke reads its own lines for one, not the note.
final LineFact<String> fenceMarkers = LineFact<String>((text) {
  // Most lines have neither run, and are not put to the pattern at all.
  if (!text.contains('```') && !text.contains('~~~')) return null;
  return _fence.firstMatch(text)?.group(1);
});

/// Where a document's fenced code is: its fences' own lines, and whether each leaves a fence open after it. A
/// fence closes on the marker it opened with, so a `~~~` inside a ``` block is the block's words. Worked out from
/// the fences' lines alone, which are few, once for each document.
class DocFences {
  DocFences._(this._lines, this._openAfter);

  final List<int> _lines;
  final List<bool> _openAfter;

  static final DocMemo<DocFences> _memo = DocMemo<DocFences>((doc) {
    final lines = <int>[];
    final open = <bool>[];
    String? fence;
    for (final marker in fenceMarkers.of(doc)) {
      fence = fence == null ? marker.fact : (fence == marker.fact ? null : fence);
      lines.add(marker.number);
      open.add(fence != null);
    }
    return DocFences._(lines, open);
  });

  /// The fences of [doc].
  static DocFences of(Doc doc) => _memo.of(doc);

  /// Whether the document has no fence at all.
  bool get isEmpty => _lines.isEmpty;

  /// Whether line [number] is fenced code, or a fence's own line.
  bool covers(int number) {
    // The last fence line at or before the line.
    var lo = 0, hi = _lines.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_lines[mid] <= number) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0) return false;
    return _lines[lo - 1] == number || _openAfter[lo - 1];
  }
}

/// Calls `visit` with every line of `doc` outside fenced code, in order; the fence lines themselves are skipped
/// too. A fence closes on the marker it opened with, so a `~~~` inside a ``` block is the block's words.
///
/// This walks the whole document: for something asked on every keystroke, a [LineFact] of what is looked for and
/// [DocFences.covers] of the few lines that have it.
void forEachDocLineOutsideFences(Doc doc, void Function(Line line) visit) {
  final fences = DocFences.of(doc);
  for (var n = 1; n <= doc.lines; n += 1) {
    if (fences.covers(n)) continue;
    visit(doc.line(n));
  }
}

/// Whether line `number` of `doc` is fenced code, or a fence's own line: the lines [forEachDocLineOutsideFences]
/// skips.
bool docLineInFence(Doc doc, int number) => number <= doc.lines && DocFences.of(doc).covers(number);

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

/// The lines whose marks are shown as written because the selection is on them, in a view that is being typed in:
/// what an extension that folds or replaces off the caret's lines was last drawn for, kept so a caret that moves
/// along its line, which changes none of it, draws nothing again.
class ActiveLines {
  ActiveLines(EditorViewLike view) : _lines = _of(view);

  List<int>? _lines;

  static List<int>? _of(EditorViewLike view) {
    final state = view.state;
    if (!(state.facet(EditorViewLike.editable) && view.hasFocus)) return null;
    final lines = <int>[];
    for (final range in state.selection.ranges) {
      lines
        ..add(state.doc.lineAt(range.from).number)
        ..add(state.doc.lineAt(range.to).number);
    }
    return lines;
  }

  /// Whether the view's lines now differ from the ones last [taken].
  bool differ(EditorViewLike view) {
    final now = _of(view), was = _lines;
    if (now == null || was == null) return now != was;
    if (now.length != was.length) return true;
    for (var i = 0; i < now.length; i++) {
      if (now[i] != was[i]) return true;
    }
    return false;
  }

  /// The view's lines as they are now are the ones drawn for.
  void take(EditorViewLike view) => _lines = _of(view);
}

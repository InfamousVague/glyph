/// The lines an extension looks at that are outside fenced code. A port of the half of `src/app/editor/lines.ts`
/// that reads only the note's text.
///
/// What differs: the web's functions take CodeMirror's `Text` and hand out its `Line`; these take the note as a
/// string and hand out a [TextLine], the same four fields, so they stand apart from the editor's document
/// (lib/editor/state). `forEachVisibleLine` and `selectedLines` read the view and the selection and are ported with
/// those.
library;

/// One line of a note, as CodeMirror's `Line` describes it.
class TextLine {
  const TextLine(this.number, this.from, this.to, this.text);

  /// Counted from 1.
  final int number;

  /// Where the line starts in the note, in UTF-16 code units.
  final int from;

  /// Where it ends, before its line break.
  final int to;
  final String text;

  int get length => to - from;

  @override
  String toString() => 'TextLine($number, $from-$to)';
}

/// Calls [visit] with every line of [text], in order; a visit that answers `false` stops the walk. A note always has
/// a first line, an empty one when it is empty, as a CodeMirror document has.
void forEachLine(String text, dynamic Function(TextLine line) visit) {
  var from = 0;
  for (var number = 1; ; number += 1) {
    final end = text.indexOf('\n', from);
    final to = end < 0 ? text.length : end;
    if (visit(TextLine(number, from, to, text.substring(from, to))) == false) return;
    if (end < 0) return;
    from = end + 1;
  }
}

/// A line that opens or closes fenced code: three backticks or three tildes.
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// Calls [visit] with every line of [text] outside fenced code, in order; the fence lines themselves are skipped
/// too. A fence closes on the marker it opened with, so a `~~~` inside a ``` block is the block's words.
void forEachLineOutsideFences(String text, void Function(TextLine line) visit) {
  String? fence;
  forEachLine(text, (line) {
    final marker = _fence.firstMatch(line.text)?.group(1);
    if (marker != null) {
      fence = fence == null ? marker : (fence == marker ? null : fence);
    } else if (fence == null) {
      visit(line);
    }
  });
}

/// Whether line [number] of [text] is fenced code, or a fence's own line: the lines [forEachLineOutsideFences]
/// skips.
bool inFence(String text, int number) {
  String? fence;
  var answer = false;
  forEachLine(text, (line) {
    final marker = _fence.firstMatch(line.text)?.group(1);
    if (line.number == number) {
      answer = fence != null || marker != null;
      return false;
    }
    if (marker != null) fence = fence == null ? marker : (fence == marker ? null : fence);
    return true;
  });
  return answer;
}

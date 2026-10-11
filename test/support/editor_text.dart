import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/view/line.dart';

/// The editor's lines are painted, not built of `Text` widgets, so `find.text` does not see a note's words. These
/// find them where a test used to look for a `RichText`.

/// What a line shows, as a reader reads it.
String shownText(EditorLine line) => line.spec.projection.display;

/// The editor lines whose shown words contain [part].
Finder editorText(String part) => find.byWidgetPredicate((widget) => widget is EditorLine && shownText(widget).contains(part), description: 'an editor line showing "$part"');

/// The render object of the first line showing [part].
RenderEditorLine editorLine(WidgetTester tester, String part) => tester.renderObject<RenderEditorLine>(editorText(part).first);

/// Where the first [part] is drawn, on the screen: from the start of its first letter to the end of its last, as
/// tall as its line box.
Rect editorTextRect(WidgetTester tester, String part) {
  final line = editorLine(tester, part);
  final proj = line.spec.projection;
  final at = proj.display.indexOf(part);
  final rects = line.rectsForRange(proj.toDoc(at, 1), proj.toDoc(at + part.length, -1));
  return MatrixUtils.transformRect(line.getTransformTo(null), rects.reduce((a, b) => a.expandToInclude(b)));
}

/// The words on each visual line of the first line showing [part].
List<String> visualLinesOf(WidgetTester tester, String part) {
  final line = editorLine(tester, part);
  final proj = line.spec.projection;
  final shown = <String>[];
  var from = 0;
  // A visual line ends where the next one's first position is drawn lower.
  double? top;
  for (var at = 0; at <= proj.length; at++) {
    final here = line.coordsAtPos(at, 1)!.top;
    if (top != null && here > top + 1) {
      shown.add(proj.source.substring(from, at));
      from = at;
    }
    top = here;
  }
  shown.add(proj.source.substring(from));
  return shown;
}

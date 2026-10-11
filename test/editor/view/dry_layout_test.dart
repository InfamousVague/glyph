// A line whose height is asked for before it is laid out (a card's preview is measured for its box, then laid out)
// makes its words' paragraph once: the layout takes the paragraph the asking made, where it made the same one a
// second time (lib/editor/view/line.dart `_dryHeight`). Counted, not timed; and the height asked for is the height
// laid out.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/projection.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

Future<void> pump(WidgetTester tester, Widget child, {double width = 390}) async {
  await pumpApp(
    tester,
    prefs: const AppPreferences(theme: 'light'),
    ratio: 2,
    home: Builder(
      builder: (context) => ColoredBox(
        color: context.tokens.color('glacier-bg'),
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: SingleChildScrollView(child: child))),
      ),
    ),
  );
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
}

const String words = 'A paragraph of plain words, long enough to run over more than one row of a narrow page, so its rows are counted.\n'
    '\n'
    '# A heading\n'
    '- a list item with words enough to wrap under its own first letter, as a hanging line does\n'
    '- [ ] a to-do\n'
    '\n'
    '> a quoted line\n'
    'words with a face :smile: among them';

EditorView viewOf(String doc) => EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions()));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a column measured and then laid out makes each plain line\'s paragraph once', (tester) async {
    // Laid out alone first: how many paragraphs the lines make with nobody asking their height.
    final alone = viewOf(words);
    addTearDown(alone.destroy);
    RenderEditorLine.paragraphs = 0;
    await pump(tester, EditorColumn(view: alone));
    final plain = RenderEditorLine.paragraphs;
    final heights = <double>[for (final line in drawnLines(tester)) line.size.height];
    expect(drawnLines(tester).length, 8);
    expect(plain, 8, reason: 'a paragraph for each line');
    final withWidgets = drawnLines(tester).where((line) => line.spec.projection.segments.any((s) => s.kind == SegmentKind.widget)).length;
    expect(withWidgets, 1, reason: 'the face is a widget in its line');
    await tester.pumpWidget(const SizedBox.shrink());

    // Measured first (what a box sized to its child asks), then laid out.
    final measured = viewOf(words);
    addTearDown(measured.destroy);
    RenderEditorLine.paragraphs = 0;
    await pump(tester, IntrinsicHeight(child: EditorColumn(view: measured)));
    final lines = drawnLines(tester);
    expect(<double>[for (final line in lines) line.size.height], heights, reason: 'measured first or not, the lines are as tall');
    // One for each line, and one more for the line with a widget in it: its height is asked of its words alone
    // (a widget's size is not asked for outside a layout), which is another paragraph than the one laid out.
    expect(RenderEditorLine.paragraphs, plain + withWidgets, reason: 'the layout takes the paragraph the measuring made (it was ${2 * plain} before)');
    for (final line in lines) {
      if (line.spec.projection.segments.any((s) => s.kind == SegmentKind.widget)) continue;
      final before = RenderEditorLine.paragraphs;
      expect(line.getMaxIntrinsicHeight(line.size.width), line.size.height, reason: 'the height asked for is the height laid out: "${line.spec.projection.display}"');
      expect(line.getDryLayout(BoxConstraints.tightFor(width: line.size.width)).height, line.size.height);
      expect(RenderEditorLine.paragraphs, before, reason: 'and asking a laid-out line makes no paragraph');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
  });

  testWidgets('a height asked at one width and a layout at another are each their own', (tester) async {
    final view = viewOf(words);
    addTearDown(view.destroy);
    await pump(tester, EditorColumn(view: view), width: 390);
    final line = drawnLines(tester).first;
    final narrow = line.getMaxIntrinsicHeight(200);
    expect(narrow, greaterThan(line.size.height), reason: 'narrower is taller');
    expect(line.getMaxIntrinsicHeight(390), line.size.height);
    // Laid out again narrower: as tall as was said.
    await pump(tester, EditorColumn(view: view), width: 200);
    expect(drawnLines(tester).first.size.height, narrow);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
  });
}

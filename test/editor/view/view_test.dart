// The view's own life: its plugins and listeners hear what CodeMirror's hear, a compartment swaps the view mode in
// place, focus opens the caret's line, and a preview is clipped as the web's is.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/markdown_view.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/extended.dart';
import 'package:ghost_md/editor/view/syntax_tree.dart';
import 'package:ghost_md/editor/view/text_panel.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../../support/editor_text.dart';
import '../../support/render.dart';

class _Heard extends PluginValue {
  _Heard(this.view) {
    made += 1;
  }

  final EditorViewLike view;
  static int made = 0;
  static int destroyed = 0;
  static final List<String> said = <String>[];

  @override
  void update(ViewUpdate update) {
    said.add([
      if (update.docChanged) 'doc',
      if (update.selectionSet) 'selection',
      if (update.focusChanged) 'focus',
      if (update.viewportChanged) 'viewport',
      if (update.geometryChanged && !update.docChanged) 'geometry',
    ].join('+'));
  }

  @override
  void destroy() => destroyed += 1;
}

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

void main() {
  setUpAll(loadAppFonts);

  testWidgets('plugins and listeners hear each update; a transaction that does not start from the state is refused', (tester) async {
    _Heard.made = _Heard.destroyed = 0;
    _Heard.said.clear();
    final plugin = ViewPlugin.define<_Heard>(_Heard.new);
    final updates = <ViewUpdate>[];
    final view = EditorView(
      wholeDocument: true,
      state: EditorState.create(doc: '# One\n\nwords', extensions: noteExtensions(more: [plugin, EditorViewLike.updateListener.of(updates.add)])),
    );
    expect(_Heard.made, 1);
    expect(view.plugin(plugin), isA<_Heard>());
    expect(view.viewport, const DocRange(0, 12));
    await pump(tester, EditorColumn(view: view));
    // The look arrives with the first build: the markers are measured again (CodeMirror's geometry change).
    expect(_Heard.said, ['geometry']);

    final stale = view.state.update(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x')));
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: 12, insert: '!'), selection: EditorSelection.single(13)));
    expect(view.state.doc.toString(), '# One\n\nwords!');
    expect(_Heard.said.last, 'doc+selection+viewport');
    expect(updates.last.docChanged, isTrue);
    expect(updates.last.startState.doc.length, 12);
    expect(view.viewport, const DocRange(0, 13));
    expect(syntaxTree(view.state).length, 13);
    expect(() => view.dispatch(stale), throwsRangeError);

    view.setFocused(true);
    expect(view.hasFocus, isTrue);
    expect(_Heard.said.last, 'focus');
    await tester.pump();

    var measured = 0;
    view.requestMeasure(MeasureRequest<int>(read: (v) => v.state.doc.length, write: (length, v) => measured = length, key: 'k'));
    view.requestMeasure(MeasureRequest<int>(read: (v) => v.state.doc.length * 2, write: (length, v) => measured = length, key: 'k'));
    await tester.pump();
    expect(measured, 26, reason: 'two requests with one key are one, the later');

    view.destroy();
    expect(_Heard.destroyed, 1);
    debugDisableShadows = true;
  });

  testWidgets('the view mode is swapped in place, and the caret’s line shows its marks while the note is written', (tester) async {
    final display = Compartment();
    final view = EditorView(
      wholeDocument: true,
      state: EditorState.create(doc: '# One\n\nSome **bold** words', extensions: noteExtensions(more: [display.of(noteView(NoteView.mixed))])),
    );
    addTearDown(view.destroy);
    await pump(tester, EditorColumn(view: view));
    expect(editorText('# One'), findsOneWidget);
    expect(view.state.facet(formattedView), isFalse);

    view.dispatch(TransactionSpec(effects: display.reconfigure(noteView(NoteView.formatted))));
    await tester.pump();
    expect(view.state.facet(formattedView), isTrue);
    expect(shownText(tester.widget(editorText('One').first)), 'One');
    expect(shownText(tester.widget(editorText('bold').first)), 'Some bold words');
    // What is hidden is stepped over: the plugin's ranges are the view's atomic ranges.
    final atomic = <(int, int)>[];
    for (final set in view.atomicRanges) {
      set.between(0, view.state.doc.length, (from, to, _) {
        atomic.add((from, to));
        return null;
      });
    }
    expect(atomic, [(0, 2), (12, 14), (18, 20)]);

    // The caret on the heading, in a focused editor: its hashes are back; the other line stays formatted.
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(3)));
    await tester.pump();
    expect(editorText('# One'), findsOneWidget);
    expect(shownText(tester.widget(editorText('bold').first)), 'Some bold words');
    final caret = editorLine(tester, '# One');
    expect(caret.selection.carets, [(3, 1)]);
    // Away again, and it is formatted again.
    view.setFocused(false);
    await tester.pump();
    expect(shownText(tester.widget(editorText('One').first)), 'One');
    expect(editorLine(tester, 'One').selection.carets, isEmpty);
    debugDisableShadows = true;
  });

  testWidgets('a selection is drawn on each line it crosses, with a handle’s anchor at each end', (tester) async {
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: 'one\ntwo\nthree', extensions: noteExtensions()));
    addTearDown(view.destroy);
    await pump(tester, EditorColumn(view: view));
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(1, 10)));
    await tester.pump();
    final one = editorLine(tester, 'one'), two = editorLine(tester, 'two'), three = editorLine(tester, 'three');
    expect([one.selection.ranges, one.selection.pastEnd, one.selection.startHandle, one.selection.endHandle], [[(1, 3)], true, 1, null]);
    expect([two.selection.ranges, two.selection.pastEnd], [[(0, 3)], true]);
    expect([three.selection.ranges, three.selection.pastEnd, three.selection.endHandle], [[(0, 2)], false, 2]);
    // The rectangles a selection's ground is painted in: from the "n" to past the line's end.
    final rects = one.rectsForRange(1, 3, pastEnd: true);
    expect(rects.single.left, closeTo(one.coordsAtPos(1)!.left, 0.01));
    expect(rects.single.right, greaterThan(one.coordsAtPos(3)!.left + 5));
    // Each end's line leads its link: a follower layer on either hangs a handle there.
    expect(one.alwaysNeedsCompositing, isTrue);
    expect(two.alwaysNeedsCompositing, isFalse);
    expect(three.alwaysNeedsCompositing, isTrue);
    debugDisableShadows = true;
  });

  testWidgets('a preview is the note small, cut at its lines with more below, and whole when it is short', (tester) async {
    final long = [for (var i = 1; i <= 12; i++) 'Line $i of the note.'].join('\n');
    await pump(tester, MarkdownView(markdown: long), width: 300);
    final t = tester.element(find.byType(MarkdownView)).tokens;
    final em = t.fontSize('lg') * 0.62 * t.len('app-text-scale');
    // `max-block-size: calc(1.6em * 6.2)`
    expect(tester.getSize(find.byType(MarkdownView)).height, closeTo(1.6 * em * 6.2, 0.01));
    expect(tester.getSize(find.byType(PeekClip)).height, lessThan(tester.getSize(find.byType(EditorColumn)).height));
    expect(editorLine(tester, 'Line 1 ').spec.look.base.style.color, t.color('app-ink-3'));
    expect(editorLine(tester, 'Line 1 ').spec.look.base.fontSize, closeTo(em, 1e-9));

    // A dense card: 4.2 lines.
    await pump(tester, MarkdownView(markdown: long, lines: 4.2), width: 300);
    expect(tester.getSize(find.byType(MarkdownView)).height, closeTo(1.6 * em * 4.2, 0.01));

    // Short: as tall as its lines (17.3 each at this size), not cut.
    await pump(tester, const MarkdownView(markdown: 'one\ntwo'), width: 300);
    expect(tester.getSize(find.byType(MarkdownView)).height, closeTo(tester.getSize(find.byType(EditorColumn)).height, 0.01));

    // Whole: the note's own ink and its heading a step up, held to 10rem.
    await pump(tester, MarkdownView(markdown: '# A title\n\n$long', whole: true), width: 300);
    expect(tester.getSize(find.byType(MarkdownView)).height, closeTo(t.lenOf('10rem'), 0.01));
    expect(editorLine(tester, 'Line 1 ').spec.look.base.style.color, t.color('glacier-text'));
    expect(editorLine(tester, 'A title').spec.runs.last.fontSize, closeTo(t.fontSize('4xl') * 0.62 * t.len('app-text-scale'), 1e-9));

    // At the page's own sizes, with its marks.
    await pump(tester, const MarkdownView(markdown: '# A title', peek: false, display: NoteView.mixed));
    expect(editorLine(tester, '# A title').spec.runs.last.fontSize, closeTo(t.len('app-h1'), 1e-9));
    debugDisableShadows = true;
  });

  testWidgets('front matter folds to its keys where the note can be edited, opens for the caret, and is its lines where it cannot', (tester) async {
    const doc = '---\ntitle: A note\nplace: Lisbon\n---\n# After\nwords';
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions()));
    addTearDown(view.destroy);
    await pump(tester, EditorColumn(view: view));
    expect(frontMatterFolded(view.state), isTrue);
    expect(find.text('title · place'), findsOneWidget);
    expect(editorText('title: A note'), findsNothing);
    // A tap on the fold puts the caret on its first key, and the block opens.
    await tester.tapAt(tester.getCenter(find.text('title · place')));
    view.setFocused(true);
    await tester.pump();
    expect(view.state.selection.main.head, 4);
    expect(frontMatterFolded(view.state), isFalse);
    expect(editorText('title: A note'), findsOneWidget);
    expect(editorLine(tester, 'title: A note').spec.projection.className, 'cm-front');

    // Read-only: the lines as they are.
    final still = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: noteExtensions(readOnly: true)));
    addTearDown(still.destroy);
    await pump(tester, EditorColumn(view: still));
    expect(frontMatterFolded(still.state), isFalse);
    expect(editorText('place: Lisbon'), findsOneWidget);
    debugDisableShadows = true;
  });

  testWidgets('a text panel hangs under the words it was asked for, one of a kind at a time', (tester) async {
    final view = EditorView(wholeDocument: true, state: EditorState.create(doc: 'A note[^1] and more.', extensions: noteExtensions()));
    addTearDown(view.destroy);
    await pump(tester, Stack(children: [EditorColumn(view: view), Positioned.fill(child: EditorTextPanels(view: view))]));
    showTextPanel(view, 6, 'The first.', className: 'cm-footnotePanel', label: 'Footnote');
    await tester.pump();
    showTextPanel(view, 6, 'The footnote’s words.', className: 'cm-footnotePanel', label: 'Footnote');
    await tester.pump();
    expect(find.text('The first.'), findsNothing);
    final words = view.coordsAtPos(6)!;
    final panel = tester.getRect(find.ancestor(of: find.text('The footnote’s words.'), matching: find.byType(Container)).first);
    expect(panel.top, closeTo(words.bottom + 6, 0.5));
    expect(panel.left, closeTo(words.left, 0.5));
    closeTextPanel(view, 'cm-footnotePanel');
    await tester.pump();
    expect(find.text('The footnote’s words.'), findsNothing);
    debugDisableShadows = true;
  });
}

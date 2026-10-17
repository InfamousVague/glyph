// Suggested edits as they are drawn (lib/editor/suggestions/suggestions.dart): the marks hidden off the caret's
// line and shown as typed on it, the new words underlined and the old struck, Keep and Revert on a tap, the line over
// the note with Keep all and Revert all, and a read-only note offering none of it.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/ai/ai_changes.dart' show AiPill;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/suggestions/suggestions.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/projection.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../../support/editor_text.dart';
import '../../support/render.dart';
import '../media/support.dart';

/// What each drawn line shows, in order.
List<String> shown(WidgetTester tester) => <String>[for (final line in tester.widgetList<EditorLine>(find.byType(EditorLine))) shownText(line)];

/// The style the first run of shown text holding [part] is drawn in.
TextStyle styleOf(WidgetTester tester, String part) {
  final line = tester.widget<EditorLine>(editorText(part).first);
  final segments = line.spec.projection.segments;
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (segment.kind != SegmentKind.text) continue;
    if (line.spec.projection.source.substring(segment.from, segment.to).contains(part)) return line.spec.runs[i].style;
  }
  throw StateError('no run holds "$part"');
}

bool underlined(TextStyle style) => style.decoration?.contains(TextDecoration.underline) ?? false;
bool struck(TextStyle style) => style.decoration?.contains(TextDecoration.lineThrough) ?? false;

Finder pill(String word) => find.byKey(ValueKey<String>('cm-aiPill-$word'));
Finder pills() => find.byKey(const ValueKey<String>('cm-suggestPills'));
String barWords(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey<String>('cm-suggestBarWords'))).data!;

/// A press landing on the first [part] shown, as the editor's gestures hand it to the plugins
/// (lib/editor/input/gestures.dart), which the column drawn here has none of: whether one kept it.
Future<bool> press(WidgetTester tester, EditorView view, String part) async {
  final at = editorTextRect(tester, part).center;
  final kept = view.eventHandlers.any((h) => h.mouseDown?.call(PointerDownEvent(position: at), view) ?? false);
  await tester.pump();
  return kept;
}

/// [pumpNote] with Ghost.md's own marks switched on, as the note's editor has them: `++added++` is one, and is
/// inside every insertion.
Future<EditorView> pumpMarked(WidgetTester tester, String doc, {NoteView display = NoteView.mixed, int? caret}) async {
  final view = EditorView(
    wholeDocument: true,
    state: EditorState.create(doc: doc, extensions: noteExtensions(formats: marks, display: display, more: <Extension>[markExtensions(marks), suggestions(), history()])),
  );
  addTearDown(view.destroy);
  await pumpApp(
    tester,
    prefs: AppPreferences(),
    home: Builder(
      builder: (context) => ColoredBox(
        color: context.tokens.color('glacier-bg'),
        child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 390, child: SingleChildScrollView(child: EditorColumn(view: view)))),
      ),
    ),
  );
  debugDisableShadows = true;
  await tester.pump();
  if (caret != null) {
    view.setFocused(true);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(caret)));
    await tester.pump();
  }
  return view;
}

const String _doc = 'Intro line.\nThe deposit is {--four--}{>>Claude<<}{++five++}{>>Claude<<} and {~~due~>paid~~}{>>Claude<<} today.\nLast line.';

void main() {
  setUpAll(loadAppFonts);

  group('suggestions, drawn', () {
    testWidgets('hide their marks and the author’s note off the caret’s line', (tester) async {
      await pumpNote(tester, _doc, more: <Extension>[suggestions(), history()]);
      expect(shown(tester), <String>['Intro line.', 'The deposit is fourfive and duepaid today.', 'Last line.']);
    });

    testWidgets('hide them in the formatted view too, where the parser’s own ~~ marks go as well', (tester) async {
      await pumpNote(tester, _doc, more: <Extension>[suggestions()], display: NoteView.formatted);
      expect(shown(tester), contains('The deposit is fourfive and duepaid today.'));
    });

    testWidgets('show them as typed on the caret’s line, and only there', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions()], caret: 14);
      expect(shown(tester), <String>['Intro line.', 'The deposit is {--four--}{>>Claude<<}{++five++}{>>Claude<<} and {~~due~>paid~~}{>>Claude<<} today.', 'Last line.']);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(2)));
      await tester.pump();
      expect(shown(tester)[1], 'The deposit is fourfive and duepaid today.');
    });

    testWidgets('underline the new words, unstruck, and strike the old', (tester) async {
      await pumpNote(tester, _doc, more: <Extension>[suggestions()]);
      expect(underlined(styleOf(tester, 'five')), isTrue);
      expect(struck(styleOf(tester, 'five')), isFalse);
      expect(struck(styleOf(tester, 'four')), isTrue);
      expect(underlined(styleOf(tester, 'four')), isFalse);
      // A replacement is a strikethrough to the parser: its old words are struck, its new ones not.
      expect(struck(styleOf(tester, 'due')), isTrue);
      expect(struck(styleOf(tester, 'paid')), isFalse);
      expect(underlined(styleOf(tester, 'paid')), isTrue);
      // The plain words round them are neither.
      expect(underlined(styleOf(tester, 'today')) || struck(styleOf(tester, 'today')), isFalse);
      expect(styleOf(tester, 'five').color, isNot(styleOf(tester, 'today').color));
    });

    testWidgets('read the same with the note’s own marks on, whose ++added++ is inside every insertion', (tester) async {
      await pumpMarked(tester, _doc);
      expect(shown(tester), <String>['Intro line.', 'The deposit is fourfive and duepaid today.', 'Last line.']);
      expect(underlined(styleOf(tester, 'five')), isTrue);
      expect(struck(styleOf(tester, 'five')), isFalse);
      expect(struck(styleOf(tester, 'four')), isTrue);
      await tester.pumpWidget(const SizedBox());
      await pumpMarked(tester, _doc, display: NoteView.formatted);
      expect(shown(tester)[1], 'The deposit is fourfive and duepaid today.');
      await tester.pumpWidget(const SizedBox());
      await pumpMarked(tester, _doc, caret: 14);
      expect(shown(tester)[1], 'The deposit is {--four--}{>>Claude<<}{++five++}{>>Claude<<} and {~~due~>paid~~}{>>Claude<<} today.');
    });

    testWidgets('wear the colour their author is given', (tester) async {
      await pumpNote(tester, 'a {++one++}{>>Claude<<} b {++two++}{>>Sam<<}', more: <Extension>[suggestions(hueOf: (author) => author == 'Sam' ? 'rose' : null)]);
      expect(styleOf(tester, 'one').color, isNot(styleOf(tester, 'two').color));
    });

    testWidgets('say how many there are, and who suggested them, over the note', (tester) async {
      await pumpNote(tester, _doc, more: <Extension>[suggestions()]);
      expect(barWords(tester), 'Claude suggested 3 changes');
      expect(tester.widgetList<AiPill>(find.byType(AiPill)).map((p) => p.word), <String>['Keep all', 'Revert all']);
    });

    testWidgets('say nothing over a note with none, or with them only in code', (tester) async {
      await pumpNote(tester, 'Plain.\n```\n{++x++}{>>Claude<<}\n```', more: <Extension>[suggestions()]);
      expect(find.byKey(const ValueKey<String>('cm-suggestBar')), findsNothing);
      expect(shown(tester).join('\n'), contains('{++x++}{>>Claude<<}'));
    });
  });

  group('Keep and Revert', () {
    testWidgets('come on a tap, which leaves the caret where it was, and go on a tap elsewhere', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions(), history()]);
      expect(pills(), findsNothing);
      final head = view.state.selection.main.head;
      expect(await press(tester, view, 'five'), isTrue);
      expect(pills(), findsOneWidget);
      expect(openSuggestion(view.state), suggestionsOf(view.state.doc)[1].from);
      expect(view.state.selection.main.head, head);
      expect(view.state.doc.toString(), _doc);
      expect(await press(tester, view, 'Last'), isFalse);
      expect(pills(), findsNothing);
    });

    testWidgets('come on a tap on the caret’s line too, where the caret goes with the finger to edit the marks', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions()], caret: 14);
      expect(await press(tester, view, 'five'), isFalse);
      expect(pills(), findsOneWidget);
      // A second tap on the one already open is the editor's alone.
      expect(await press(tester, view, 'five'), isFalse);
      expect(pills(), findsOneWidget);
    });

    testWidgets('go with any edit', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions()]);
      await press(tester, view, 'five');
      expect(pills(), findsOneWidget);
      view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'x')));
      await tester.pump();
      expect(pills(), findsNothing);
    });

    testWidgets('keep one: the new words without the marks, one undo back', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions(), history()]);
      await press(tester, view, 'paid');
      await tester.tap(find.descendant(of: pills(), matching: pill('keep')));
      await tester.pump();
      expect(view.state.doc.toString(), 'Intro line.\nThe deposit is {--four--}{>>Claude<<}{++five++}{>>Claude<<} and paid today.\nLast line.');
      expect(pills(), findsNothing);
      expect(barWords(tester), 'Claude suggested 2 changes');
      undo(view);
      await tester.pump();
      expect(view.state.doc.toString(), _doc);
    });

    testWidgets('revert one: the old words without the marks, one undo back', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions(), history()]);
      await press(tester, view, 'four');
      await tester.tap(find.descendant(of: pills(), matching: pill('revert')));
      await tester.pump();
      expect(view.state.doc.toString(), 'Intro line.\nThe deposit is four{++five++}{>>Claude<<} and {~~due~>paid~~}{>>Claude<<} today.\nLast line.');
      undo(view);
      await tester.pump();
      expect(view.state.doc.toString(), _doc);
    });

    testWidgets('keep all from the line over the note, one undo back, and the line goes', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions(), history()]);
      await tester.tap(pill('keep all'));
      await tester.pump();
      expect(view.state.doc.toString(), 'Intro line.\nThe deposit is five and paid today.\nLast line.');
      expect(find.byKey(const ValueKey<String>('cm-suggestBar')), findsNothing);
      undo(view);
      await tester.pump();
      expect(view.state.doc.toString(), _doc);
      expect(barWords(tester), 'Claude suggested 3 changes');
    });

    testWidgets('revert all from the line over the note, one undo back', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions(), history()]);
      await tester.tap(pill('revert all'));
      await tester.pump();
      expect(view.state.doc.toString(), 'Intro line.\nThe deposit is four and due today.\nLast line.');
      undo(view);
      await tester.pump();
      expect(view.state.doc.toString(), _doc);
    });
  });

  group('a read-only note', () {
    testWidgets('draws its suggestions and offers nothing', (tester) async {
      final view = await pumpNote(tester, _doc, more: <Extension>[suggestions()], readOnly: true, display: NoteView.formatted);
      expect(shown(tester), contains('The deposit is fourfive and duepaid today.'));
      expect(barWords(tester), 'Claude suggested 3 changes');
      expect(find.byType(AiPill), findsNothing);
      expect(await press(tester, view, 'five'), isFalse);
      expect(pills(), findsNothing);
      expect(find.byType(AiPill), findsNothing);
      expect(openSuggestion(view.state), isNull);
      expect(view.state.doc.toString(), _doc);
    });
  });

  test('the line over the note names no one where the suggestions do not', () {
    expect(suggestedWords(suggestionsIn('{++a++}')), '1 suggested change');
    expect(suggestedWords(suggestionsIn('{++a++}{>>Claude<<}')), 'Claude suggested 1 change');
    expect(suggestedWords(suggestionsIn('{++a++}{>>Claude<<} {--b--}{>>Sam<<}')), '2 suggested changes');
  });
}

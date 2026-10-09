// The panel a tap on an answer opens (lib/editor/ai/fill_panel.dart): `src/app/editor/fillPanel.test.ts`, case for
// case and by the same names, then the tap that opens it and what closes it, how it is drawn, held to the theme's
// own numbers, and pictures in shots/ to lay beside the page.
//
// What is asked differently: the page's test read the panel's `<p>`s and `<button>`s; here the panel a view shows is
// its content (`fillPanelOf(view)`), whose words are the title and the lines and whose actions are the buttons. A
// press on a button is `pressPanelAction`, which is all the drawn button calls. `inLocale('en-GB', …)` is the
// panel's own default form for a day.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/backend.dart' show modelLimits;
import 'package:ghost_md/ai/fills/queue.dart';
import 'package:ghost_md/editor/ai/blanks.dart';
import 'package:ghost_md/editor/ai/fill_panel.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/text_panel.dart';
import 'package:glacier/glacier.dart';

import '../support/editor_text.dart';
import '../support/render.dart';
import 'blanks_support.dart';

EditorView open(String doc, {Given? given, bool noHooks = false, bool readOnly = false}) =>
    editor(doc, given: given, noHooks: noHooks, readOnly: readOnly, more: <Extension>[fillPanel()]);

/// The panel's words, its title first, and its actions, opened on what sits at `at`.
({List<String> words, List<String> actions}) panel(EditorView view, int at) {
  openFillPanel(view, at);
  final shown = fillPanelOf(view).value;
  return (words: shown?.content.words ?? const <String>[], actions: <String>[for (final action in shown?.content.actions ?? const <PanelAction>[]) action.label]);
}

void press(EditorView view, String label) => pressPanelAction(view, fillPanelOf(view).value!.content.actions.firstWhere((action) => action.label == label));

const String tokyo = 'Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)';

/// A view that is told where a tap lands (the web's `vi.spyOn(view, 'posAtCoords')`).
class _TapView extends EditorView {
  _TapView({required super.state}) : super(wholeDocument: true);

  int? at;

  @override
  int? posAtCoords(Offset global, {bool precise = true}) => at;
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(forgetFills);

  group('the panel on a filled answer', () {
    test('says whose it is, from memory, when and what was asked, and the one sentence about every model', () {
      final view = open(tokyo);
      final shown = panel(view, tokyo.indexOf('midweek'));
      expect(shown.words, ['Qwen3.5 4B, from memory', 'Asked on 28 September 2026: what day / time?', modelLimits, 'General advice, not today’s fares.']);
      expect(shown.actions, ['Keep as mine', 'Ask again', 'Put the question back']);
    });

    test('says from this note, and from the web with its source', () {
      const note = 'Who brings the charger? ??Sam??(Qwen3.5 4B from this note, 2026-09-28)';
      expect(panel(open(note), note.indexOf('Sam')).words.take(1), ['Qwen3.5 4B, from this note']);
      const web = 'Weather in Lisbon tomorrow: ??Rain??(Qwen3.5 4B from Open-Meteo, 2026-09-28. Asked: weather)';
      expect(panel(open(web), web.indexOf('Rain')).words[2], 'The phone asked Open-Meteo, and the model wrote this from what came back. It can still be wrong.');
    });

    test('keeps an answer as the person’s own, or puts the question back', () {
      final view = open(tokyo);
      panel(view, tokyo.indexOf('midweek'));
      press(view, 'Keep as mine');
      expect(view.state.doc.toString(), 'Flights are cheapest to Tokyo on midweek');
      final again = open(tokyo);
      panel(again, tokyo.indexOf('midweek'));
      press(again, 'Put the question back');
      expect(again.state.doc.toString(), 'Flights are cheapest to Tokyo on {?what day / time?}');
    });

    test('puts three items back as one blank, and leaves a second fill of the same question alone', () {
      String item(String words, int n) => '- ??$words??(Qwen3.5 4B from memory, 2026-09-28. Asked: more. $n of 3)';
      final note = ['## Packing', '- Passport', item('Rail pass', 1), item('Shoes', 2), item('Cash', 3), item('Umbrella', 1), item('Hat', 2), item('Map', 3)].join('\n');
      final view = open(note);
      panel(view, note.indexOf('Shoes'));
      press(view, 'Put the question back');
      expect(view.state.doc.toString(), ['## Packing', '- Passport', '- {?more}', item('Umbrella', 1), item('Hat', 2), item('Map', 3)].join('\n'));
    });

    test('asks again for the whole answer, told what it is not', () {
      final given = Given();
      const note = 'The 2022 World Cup was won by ??France??(Qwen3.5 4B from memory, 2026-09-28)';
      final view = open(note, given: given);
      panel(view, note.indexOf('France'));
      press(view, 'Ask again');
      expect(given.pressed.map(targetsJson), [
        [
          {
            'key': 'again\u0000${note.indexOf('??')}',
            'question': '',
            'order': 0,
            'again': {'mark': note.substring(note.indexOf('??')), 'words': 'France'},
          },
        ],
      ]);
    });

    test('has no actions where the note is only read', () {
      expect(panel(open(tokyo, noHooks: true, readOnly: true), tokyo.indexOf('midweek')).actions, isEmpty);
    });
  });

  group('the panel on a blank', () {
    test('shows a worked-out answer’s working, and writes it in', () {
      const note = '- Cabin \$200\n- Ferry \$45\n\nTotal: {?}';
      final view = open(note);
      final shown = panel(view, note.indexOf('{?'));
      expect(shown.words, ['Worked out by the app', '\$200 + \$45 = \$245.', 'The model was not asked.']);
      expect(shown.actions, ['Write it in']);
      press(view, 'Write it in');
      expect(view.state.doc.toString(), '- Cabin \$200\n- Ferry \$45\n\nTotal: \$245');
    });

    test('says why the app can’t, and asks the model anyway', () {
      final given = Given();
      const note = 'Days until Easter: {?}';
      final view = open(note, given: given);
      final shown = panel(view, note.indexOf('{?'));
      expect(shown.words, ['The app can’t work this out', 'Easter moves each year, and the app does not know when it falls.']);
      expect(shown.actions, ['Ask the model anyway']);
      press(view, 'Ask the model anyway');
      expect(given.pressed.map(targetsJson), [
        [
          {'key': '\u00000', 'question': '', 'order': 0, 'anyway': true},
        ],
      ]);
    });

    test('says a live blank no source answers can’t be known offline', () {
      const note = 'A return flight costs {?price today}';
      final view = open(note);
      final shown = panel(view, note.indexOf('{?'));
      expect(shown.words, ['The model can’t know this', 'Prices change, and the model has no internet.', 'No public source the phone can ask answers this.']);
      expect(shown.actions, ['Ask the model anyway']);
    });

    test('offers no Ask anyway where the model can never run', () {
      const note = 'Days until Easter: {?}';
      expect(panel(open(note, given: Given(canFill: false)), note.indexOf('{?')).actions, isEmpty);
    });
  });

  // The port's own, for what the page's test left to the shots.
  group('the panel, opened and closed', () {
    _TapView tapView(String doc) {
      final view = _TapView(state: EditorState.create(doc: doc, extensions: noteExtensions(formats: marks, more: <Extension>[markExtensions(marks), blanks(Given().hooks), fillPanel()])));
      addTearDown(view.destroy);
      return view;
    }

    bool tap(_TapView view, int? at) {
      view.at = at;
      var handled = false;
      for (final handlers in view.eventHandlers) {
        handled = (handlers.pointerDown?.call(const PointerDownEvent(), view) ?? false) || handled;
      }
      return handled;
    }

    test('a tap on a filled answer opens it, never takes the press, and leaves the mark’s own note panel shut', () {
      final view = tapView(tokyo);
      expect(tap(view, tokyo.indexOf('midweek') + 3), isFalse);
      final shown = fillPanelOf(view).value!;
      expect(shown.content.title, 'Qwen3.5 4B, from memory');
      // Under the answer's own words, past the `??`.
      expect(shown.at, tokyo.indexOf('??') + 2);
      expect(textPanels(view).value, isEmpty);
    });

    test('a tap elsewhere closes it, and so does a change to the note', () {
      final view = tapView(tokyo);
      tap(view, tokyo.indexOf('midweek'));
      expect(fillPanelOf(view).value, isNotNull);
      tap(view, 3);
      expect(fillPanelOf(view).value, isNull);
      tap(view, tokyo.indexOf('midweek'));
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'Oh. ')));
      expect(fillPanelOf(view).value, isNull);
      tap(view, null);
      expect(fillPanelOf(view).value, isNull);
    });

    test('opens on nothing where there is neither a blank nor an answer', () {
      final view = open('Plain words.');
      expect(openFillPanel(view, 3), isFalse);
      expect(fillPanelOf(view).value, isNull);
    });

    test('says what a paused lookup waits for, and what came of a press, in the app’s words', () {
      const note = 'Weather in Lisbon today: {?weather}';
      expect(panel(open(note, given: Given(lookups: Lookups.localOnly)), note.indexOf('{?')).words, [
        'The model can’t know this',
        'Weather changes by the hour, and the model has no internet.',
        'Local only is on, so this waits. The phone would ask Open-Meteo for it.',
      ]);
      expect(panel(open(note, given: Given(lookups: Lookups.off)), note.indexOf('{?')).words.last, 'Look up blanks online is off in Settings, so the phone doesn’t ask the web.');
      final looked = panel(open(note), note.indexOf('{?'));
      expect(looked.words, ['Looked up online', 'Weather changes by the hour, and the model has no internet.', 'On Fill, the phone asks Open-Meteo, and the answer is written from what comes back. Only the question goes.']);
      expect(looked.actions, isEmpty);
    });

    test('writes a day in the form the screen gives, where it gives one', () {
      final view = editor(tokyo, more: <Extension>[fillPanel(), fillPanelDay.of((day) => '${day.month}/${day.day}/${day.year}')]);
      expect(panel(view, tokyo.indexOf('midweek')).words[1], 'Asked on 9/28/2026: what day / time?');
    });
  });

  group('how it is drawn', () {
    testWidgets('under the words, six pixels down, inside the editor’s width, in the note’s face a touch smaller', (tester) async {
      final view = await pumpBlanks(tester, 'Short.\n\n$tokyo');
      openFillPanel(view, view.state.doc.toString().indexOf('midweek'));
      await tester.pump();
      final t = tester.element(find.byKey(const ValueKey<String>(fillPanelClass))).tokens;
      final em = t.len('app-body') * 0.84;
      final box = tester.getRect(find.byKey(const ValueKey<String>(fillPanelClass)));
      final words = view.coordsAtPos(view.state.doc.toString().indexOf('midweek'))!;
      expect(box.top, closeTo(words.bottom + 6, 0.01));
      // max-inline-size: min(22rem, 86vw); left: max(8, min(the words' left, the editor's width - its own - 8)).
      expect(box.width, closeTo(390 * 0.86, 0.01));
      expect(words.left, greaterThan(390 - box.width - 8));
      expect(box.left, closeTo(390 - box.width - 8, 0.01));
      final head = tester.widget<Text>(find.text('Qwen3.5 4B, from memory'));
      expect((head.style!.fontSize, head.style!.color, head.style!.fontWeight), (em, t.color('app-ink'), FontWeight.w600));
      final line = tester.widget<Text>(find.text(modelLimits));
      expect((line.style!.fontSize, line.style!.color, line.style!.height), (em, t.color('app-ink-2'), 1.4));
      // padding: 0.55em 0.75em 0.6em, inside a 1px border.
      final headRow = tester.getRect(find.byKey(const ValueKey<String>('cm-fillPanelHead')));
      expect(headRow.top - box.top, closeTo(0.55 * em + 1, 0.01));
      expect(headRow.left - box.left, closeTo(0.75 * em + 1, 0.01));
      // The actions: 0.45em under the last line, each 0.3em of padding over and under a line of 1.4.
      final actions = tester.getRect(find.byKey(const ValueKey<String>('cm-fillPanelActions')));
      final last = tester.getRect(find.byKey(const ValueKey<String>('cm-fillPanelLine-2')));
      expect(actions.top - last.bottom, closeTo(0.45 * em, 0.01));
      final keep = tester.getRect(find.byKey(const ValueKey<String>('cm-fillPanelAction-Keep as mine')));
      expect(keep.height, closeTo(2 * em, 1.0));
      expect(box.bottom - actions.bottom, closeTo(0.6 * em + 1, 0.01));
      await closeBlanks(tester);
    });

    testWidgets('a press on a button closes the panel and does what it says', (tester) async {
      final view = await pumpBlanks(tester, tokyo);
      openFillPanel(view, tokyo.indexOf('midweek'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('cm-fillPanelAction-Keep as mine')));
      await tester.pump();
      expect(view.state.doc.toString(), 'Flights are cheapest to Tokyo on midweek');
      expect(find.byKey(const ValueKey<String>(fillPanelClass)), findsNothing);
      await closeBlanks(tester);
    });

    testWidgets('near the right edge it is held eight pixels inside the editor', (tester) async {
      const note = 'A long line of words that ends in an answer: ??yes??(Qwen3.5 4B from memory, 2026-09-28)';
      final view = await pumpBlanks(tester, note);
      openFillPanel(view, note.indexOf('yes'));
      await tester.pump();
      final box = tester.getRect(find.byKey(const ValueKey<String>(fillPanelClass)));
      expect(box.right, lessThanOrEqualTo(390 - 8 + 0.01));
      expect(box.left, greaterThanOrEqualTo(8));
      expect(editorText('A long line'), findsOneWidget);
      await closeBlanks(tester);
    });
  });

  // Pictures, to lay beside the page's own drawing of the same note (editor/fillPanel.ts's theme):
  // `flutter test --update-goldens test/editor_ai/fill_panel_test.dart`, then open shots/.
  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('the panel on a filled answer, $theme', (tester) async {
        final view = await pumpBlanks(tester, '# Tokyo trip\n\n$tokyo\n\nThe capital of Australia is {?}.\n', theme: theme, shadows: true);
        openFillPanel(view, view.state.doc.toString().indexOf('midweek'));
        await tester.pump();
        await shot(tester, 'fill-panel-fill-$theme');
        await closeBlanks(tester);
      });

      testWidgets('the panel on a worked-out blank, $theme', (tester) async {
        const note = '- Cabin \$200\n- Ferry \$45\n\nTotal: {?}\n';
        final view = await pumpBlanks(tester, note, theme: theme, shadows: true);
        openFillPanel(view, note.indexOf('{?'));
        await tester.pump();
        await shot(tester, 'fill-panel-blank-$theme');
        await closeBlanks(tester);
      });

      testWidgets('the panel on a blank the app refuses, with Ask the model anyway, $theme', (tester) async {
        const note = 'A return flight costs {?price today}\n';
        final view = await pumpBlanks(tester, note, theme: theme, shadows: true);
        openFillPanel(view, note.indexOf('{?'));
        await tester.pump();
        await shot(tester, 'fill-panel-refused-$theme');
        await closeBlanks(tester);
      });
    }
  });
}

// Blanks, drawn (lib/editor/ai/blanks.dart): `src/app/editor/blanks.test.ts`, case for case and by the same names,
// then how each thing is drawn, held to the theme's own numbers, and pictures in shots/ to lay beside the page.
//
// What is asked differently: the page's test read its DOM (`.cm-blank`, `.cm-fillPill`, `.cm-blankWords`); here the
// same things are the view's decorations, the marks by their class and the widgets by their kind
// (blanks_support.dart). The editor can be given the focus here, so what the page's test asked only `if
// (view.hasFocus)` is always asked. Fake timers are a widget test's own clock.
//
// Left out: `ai/fills/voice.test.ts` reads the web's source files for a semicolon, a dash or an ellipsis in a
// sentence; the sentences here are the web's, letter for letter, and are held by the cases below and the panel's.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/queue.dart';
import 'package:ghost_md/ai/fills/fill_landing.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/editor/ai/blanks.dart';
import 'package:ghost_md/editor/ai/blanks_paint.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/tables/tables.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:glacier/glacier.dart';

import '../support/editor_text.dart';
import '../support/render.dart';
import 'blanks_support.dart';

void main() {
  setUpAll(loadAppFonts);

  tearDown(() {
    forgetFills();
    preferences.update((p) => p.copyWith(autoFill: true));
  });

  group('the square', () {
    test('draws a blank in a dashed box, its braces dim in the Markdown view', () {
      final view = editor('Flights are cheapest on {?what day / time?}');
      expect(squares(view), hasLength(1));
      expect(marked(view, 'cm-blankMark'), hasLength(2));
      final question = marked(view, 'cm-blankQuestion').single;
      expect(view.state.sliceDoc(question.from, question.to), 'what day / time?');
      expect(labels(view), ['A blank for the AI: what day / time?']);
    });

    test('keeps a short square on one line, and lets a long question wrap', () {
      final view = editor('Weather in Lisbon tomorrow: {?weather}\n\nA plan: {?a friendlier way to say: fix the boiler now, and the date}');
      final found = squares(view).where((s) => s.value.spec.attributes?['role'] == 'group').toList();
      expect(found[0].value.spec.attributes!.containsKey('data-short'), isTrue);
      expect(found[1].value.spec.attributes!.containsKey('data-short'), isFalse);
    });

    test('hides the braces in the Formatted view, but on the line being written', () {
      final view = editor('Flights are cheapest on {?which day}\n\nAnother line', formatted: true, anchor: 40);
      // expect(html(view)).not.toContain('{?'): the opening brace is replaced by nothing, the closing one by the icon.
      expect(hiddenRanges(view), [(from: 24, to: 26)]);
      expect(widgets<IconWidget>(view).single.brace, isFalse);
      expect(drawn(view).where((d) => d.value.widget is IconWidget).map((d) => (d.from, d.to)), [(35, 36)]);
      expect(marked(view, 'cm-blankMark'), isEmpty);
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(5)));
      expect(marked(view, 'cm-blankMark'), hasLength(2));
      expect(widgets<IconWidget>(view).single.brace, isTrue);
      // And with the caret inside the braces the closing one is words again, with no icon.
      view.dispatch(TransactionSpec(selection: EditorSelection.single(30)));
      expect(widgets<IconWidget>(view), isEmpty);
      expect(hiddenRanges(view), isEmpty);
    });

    test('draws nothing in code, maths, a comment, a link’s address or front matter', () {
      final view = editor('---\ntitle: {?x}\n---\nA `{?code}` and \$x {?m}\$ and <!-- {?c} --> and [w](https://a.b/{?u})\n\n```\n{?fenced}\n```');
      expect(squares(view), isEmpty);
      expect(editorBlanks(view.state), isEmpty);
    });
  });

  group('the icon and what follows', () {
    test('says what will happen: the model, the app’s working, a lookup, or nothing to be known', () {
      final view = editor(['Flights are cheapest on {?which day}', 'Days until Christmas: {?}', 'Weather in Lisbon today: {?weather}', 'Days until Easter: {?}', 'A return flight costs {?price today}'].join('\n\n'));
      expect(labels(view), [
        'A blank for the AI: which day',
        'Worked out: Days until Christmas:',
        'Looked up online when pressed: weather',
        "Can't work out: Days until Easter:",
        'No source to ask: price today',
      ]);
      expect(after(view), ['88 days', 'Can’t work out', 'No source to ask']);
      expect(widgets<IconWidget>(view), hasLength(5));
      expect([for (final icon in widgets<IconWidget>(view)) icon.icon.name], ['message-circle-question-mark', 'calendar-days', 'wifi', 'calendar-days', 'wifi-off']);
    });

    test('keeps a live blank paused under Local only, and refused with Look up blanks online off', () {
      expect(after(editor('Weather in Lisbon today: {?weather}', given: Given(lookups: Lookups.localOnly))), ['Paused']);
      expect(after(editor('Weather in Lisbon today: {?weather}', given: Given(lookups: Lookups.off))), ['Can’t know offline']);
    });

    test('redraws a worked-out answer as a number changes', () {
      final view = editor('- Cabin \$200\n- Ferry \$45\n- Food \$80\n\nTotal so far: {?total}');
      expect(after(view), ['\$325']);
      final at = view.state.doc.toString().indexOf('\$80');
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: at + 1, to: at + 3, insert: '95')));
      expect(after(view), ['\$340']);
    });

    test('draws no icon while the caret is inside the braces', () {
      final view = editor('Cheapest on {?which day}', anchor: 16);
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(16)));
      expect(widgets<IconWidget>(view), isEmpty);
    });
  });

  group('the Fill pill', () {
    test('counts the line’s blanks for the model and leaves out the rest', () {
      final view = editor('Cheapest on {?which day} and {?which airport}\n\nDays until Christmas: {?}\n\nThe capital is {?}.');
      expect(pills(view), ['Fill 2', 'Fill']);
    });

    test('is not drawn where the model can never run', () {
      expect(pills(editor('Cheapest on {?which day}', given: Given(canFill: false))), isEmpty);
      expect(pills(editor('Cheapest on {?which day}', noHooks: true)), isEmpty);
    });

    test('presses its line’s blanks, tracked from then on', () {
      final given = Given();
      final view = editor('Cheapest on {?which day}\n\nThe capital is {?}.', given: given);
      widgets<PillWidget>(view).first.press(view);
      expect(given.pressed.map(targetsJson), [
        [
          {'key': 'which day\u00000', 'question': 'which day', 'order': 0},
        ],
      ]);
      expect(view.state.field(blanksField)['which day\u00000'], (from: 12, to: 24));
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'Oh. ')));
      expect(view.state.field(blanksField)['which day\u00000'], (from: 16, to: 28));
    });

    testWidgets('waits on the line being typed until the hands have stopped', (tester) async {
      final view = editor('Cheapest on ', anchor: 12);
      view.setFocused(true);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 12, insert: '{?which day}'), selection: EditorSelection.single(24), userEvent: 'input.type'));
      expect(pills(view), isEmpty);
      await tester.pump(const Duration(milliseconds: pauseMs + 10));
      expect(pills(view), ['Fill']);
      view.destroy();
    });
  });

  group('Fill the blanks', () {
    test('takes every blank the model or a lookup can answer, top to bottom', () {
      final given = Given();
      final view = editor('Cheapest on {?which day}\n\nDays until Christmas: {?}\n\nWeather in Lisbon today: {?weather}\n\nThe capital is {?}.', given: given);
      expect(fillableBlanks(view.state).map((b) => b.question), ['which day', 'weather', '']);
      expect(fillAll(view), 3);
      expect(given.pressed[0].map((t) => t.question), ['which day', 'weather', '']);
    });

    test('says why a title has nothing to be named from, and runs nothing', () {
      final given = Given();
      final view = editor('# {?}\n\nToo few words.', given: given);
      expect(fillAll(view), 0);
      expect(given.said, ['Write a few lines first. The title is made from them.']);
    });
  });

  group('filling on their own once the typing stops', () {
    test('offers every blank the phone can answer, less a title with too little under it', () {
      final view = editor('# {?}\n\nCheapest on {?which day}\n\nWeather in Lisbon today: {?weather}\n\nThe capital is {?}.');
      // The empty title blank is left out: a press would only refuse it with a sentence.
      expect(idleFillable(view, <String>{}).blanks.map((b) => b.question), ['which day', 'weather', '']);
    });

    test('leaves the blank the caret still sits in, and any already tried, alone', () {
      final view = editor('Cheapest on {?which day} and {?which airport}', anchor: 16);
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(16)));
      expect(idleFillable(view, <String>{}).blanks.map((b) => b.question), ['which airport']);
      expect(idleFillable(view, <String>{'which airport\u00000'}).blanks.map((b) => b.question), isEmpty);
      // And without the focus, as the page's test had it, the caret holds nothing back.
      view.setFocused(false);
      expect(idleFillable(view, <String>{'which airport\u00000'}).blanks.map((b) => b.question), ['which day']);
    });

    test('stands down where the model can’t run, or with the setting off', () {
      expect(idleFillable(editor('Cheapest on {?which day}', given: Given(canFill: false)), <String>{}).blanks, isEmpty);
      final view = editor('Cheapest on {?which day}');
      preferences.update((p) => p.copyWith(autoFill: false));
      expect(idleFillable(view, <String>{}).blanks, isEmpty);
    });

    testWidgets('presses them a few seconds after the hands stop, once', (tester) async {
      final given = Given();
      final view = editor('Cheapest on ', given: given, anchor: 12);
      view.setFocused(true);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 12, insert: '{?which day}'), selection: EditorSelection.single(24), userEvent: 'input.type'));
      await tester.pump(const Duration(milliseconds: pauseMs + 10));
      expect(given.pressed, isEmpty);
      await tester.pump(const Duration(milliseconds: pauseSettleMs));
      expect(given.pressed[0].map((t) => t.question), ['which day']);
      // Pressing it is remembered, so a later rest leaves it alone rather than pressing the same blank again.
      await tester.pump(const Duration(milliseconds: pauseMs + pauseSettleMs + 10));
      expect(given.pressed, hasLength(1));
      view.destroy();
    });
  });

  // The port's own, for what the page's test left to the shots.
  group('what the queue says', () {
    test('the words after a blank, for every state a press can leave it in', () {
      const model = ModelLaneForWords();
      expect(wordsAfter(model.lane, const FillStatus.paused(why: PausedWhy.offline), null), 'Waiting for a connection');
      expect(wordsAfter(model.lane, const FillStatus.paused(why: PausedWhy.localOnly), null), 'Paused');
      expect(wordsAfter(model.lane, const FillStatus.looking(), null), 'Looking it up');
      expect(wordsAfter(model.lane, const FillStatus.waiting(), null), isNull);
      expect(wordsAfter(model.lane, const FillStatus.filling(runId: 'r'), const FillOutcome(why: FillWhy.none, model: 'm')), isNull);
      expect(wordsAfter(model.lane, null, const FillOutcome(why: FillWhy.unknown, model: 'm')), 'Not known');
      expect(wordsAfter(model.lane, null, const FillOutcome(why: FillWhy.none, model: 'm')), 'No answer came');
      expect(wordsAfter(model.lane, null, const FillOutcome(why: FillWhy.didntFit, model: 'm')), 'Didn’t fit');
      expect(wordsAfter(model.lane, null, const FillOutcome(why: FillWhy.nothing, model: 'm')), 'Not found online');
      expect(wordsAfter(model.lane, null, null), isNull);
    });

    test('counts what a press of Fill the blanks would take, and where the live ones would be asked', () {
      final view = editor('Cheapest on {?which day}\n\nWeather in Lisbon today: {?weather}\n\nDays until Christmas: {?}');
      final plan = fillPlanOf(view.state);
      expect(plan.count, 2);
      expect(plan.online, ['Open-Meteo']);
    });

    testWidgets('tells the open note’s count half a second after it opens, and forgets it as the note goes', (tester) async {
      final view = editor('Cheapest on {?which day}\n\nDays until Christmas: {?}');
      expect(openNoteBlanks.value, isNull);
      await tester.pump(const Duration(milliseconds: 510));
      expect(openNoteBlanks.value, (noteId: 'n1', count: 1));
      view.destroy();
      expect(openNoteBlanks.value, isNull);
    });

    testWidgets('a square redraws when the queue speaks: Waiting, then Filling, then what came of it', (tester) async {
      final fills = FakeFills()..start();
      final given = fills.given();
      final view = editor('Cheapest on {?which day}', given: given);
      final landing = FillLanding('n1', view, wisp: () => false, owner: () => null);
      addTearDown(landing.dispose);
      final stamp = view.state.field(blankStamp);
      widgets<PillWidget>(view).first.press(view);
      await tester.pump();
      expect(pills(view).single, anyOf('Waiting', 'Filling'));
      for (var i = 0; i < 50 && fills.models.isEmpty; i++) {
        await tester.pump();
      }
      expect(pills(view), ['Filling']);
      expect(squares(view).single.value.spec.attributes!.containsKey('data-busy'), isTrue);
      expect(view.state.field(blankStamp), greaterThan(stamp));
      fills.models.single.finish('[1] UNKNOWN');
      for (var i = 0; i < 50 && fillOutcome('n1', 'which day\u00000') == null; i++) {
        await tester.pump();
      }
      await tester.pump();
      expect(after(view), ['Not known']);
      expect(pills(view), ['Fill']);
      view.destroy();
      fills.stop();
      await tester.pump(const Duration(seconds: 5));
    });

    test('a table’s cell: its words, its squares and its filled answers in order, and nothing where it has neither', () {
      const doc = '| Item | Cost |\n| --- | --- |\n| Cabin {?how much} | ??\$200??(Qwen3.5 4B from memory, 2026-09-28) each |\n| Ferry | \$45 |';
      final view = editor(doc);
      String plain(String text) => text.trim();
      final first = doc.indexOf('Cabin');
      final cell = drawCell(view, 'Cabin {?how much}', first, plain)!;
      expect(cell.pieces, hasLength(2));
      expect((cell.pieces[0] as CellWords).text, 'Cabin');
      final blank = cell.pieces[1] as CellBlank;
      expect((blank.blank.question, blank.label, blank.icon.name, blank.after), ('how much', 'A blank for the AI: how much', 'message-circle-question-mark', null));
      const filled = '??\$200??(Qwen3.5 4B from memory, 2026-09-28) each';
      final second = drawCell(view, filled, doc.indexOf(filled), plain)!;
      expect((second.pieces[0] as CellFill).words, '\$200');
      expect((second.pieces[0] as CellFill).at, doc.indexOf(filled) + 2);
      expect((second.pieces[1] as CellWords).text, 'each');
      expect(drawCell(view, 'Ferry', doc.indexOf('Ferry'), plain), isNull);
      // The pill after the table: its one blank for the model.
      final pill = tablePill(view, 0, doc.length);
      expect(pill, isA<FillPill>());
      expect((pill! as FillPill).label, 'Fill');
      expect(tablePill(editor(doc, given: Given(canFill: false)), 0, doc.length), isNull);
      expect(tablePill(view, doc.indexOf('| Ferry'), doc.length), isNull);
    });
  });

  group('in a drawn table', () {
    const doc = 'Costs\n\n| Item | Cost |\n| --- | --- |\n| Cabin {?how much} | ??\$200??(Qwen3.5 4B from memory, 2026-09-28) each |\n| Ferry | \$45 |\n';

    testWidgets('a cell with a blank or a filled answer holds its own box in the table, and the rest are the table’s words', (tester) async {
      await pumpBlanks(tester, doc, more: <Extension>[drawnTables()]);
      final table = tester.widget<GlyphTable>(find.byType(GlyphTable));
      expect([for (final cell in table.cells) (cell.row, cell.column)], [(1, 0), (1, 1)]);
      expect(find.descendant(of: find.byType(GlyphTable), matching: find.byType(BlankCell)), findsNWidgets(2));
      expect(find.descendant(of: find.byType(GlyphTable), matching: find.byKey(const ValueKey<String>('cm-blank'))), findsOneWidget);
      expect(find.descendant(of: find.byType(GlyphTable), matching: find.text('\$200')), findsOneWidget);
      // Each box sits inside its own cell, and its column is as wide as the box needs.
      final render = tester.renderObject<RenderGlyphTable>(find.byType(GlyphTable));
      final origin = tester.getTopLeft(find.byType(GlyphTable));
      final boxes = tester.widgetList<BlankCell>(find.byType(BlankCell)).toList();
      for (final (at, held) in table.cells.indexed) {
        final cell = render.table.cells[held.row][held.column].rect.shift(origin);
        final box = tester.getRect(find.byWidget(boxes[at]));
        expect(cell.contains(box.topLeft) && cell.contains(box.bottomRight - const Offset(0.01, 0.01)), isTrue, reason: 'cell ${held.row},${held.column}: $box in $cell');
      }
      // The Fill pill follows the table's last row, as before.
      expect(find.byType(FillPill), findsOneWidget);
      await closeBlanks(tester);
    });

    testWidgets('a tap on a filled answer in a cell opens its panel, and the table does not open for it', (tester) async {
      final view = await pumpBlanks(tester, doc, more: <Extension>[drawnTables()]);
      await tester.tap(find.descendant(of: find.byType(GlyphTable), matching: find.byKey(const ValueKey<String>('cm-fillWords'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(GlyphTable), findsOneWidget, reason: 'the caret is not in the table: it is still drawn');
      expect(view.state.selection.main.head, 0);
      await closeBlanks(tester);
    });

    testWidgets('the table is drawn again when its blank’s state changes under it', (tester) async {
      final view = await pumpBlanks(tester, doc, more: <Extension>[drawnTables()]);
      final before = tester.widget<DrawnTable>(find.byType(DrawnTable));
      view.dispatch(TransactionSpec(effects: blanksRedraw.of(null)));
      await tester.pump();
      expect(identical(tester.widget<DrawnTable>(find.byType(DrawnTable)), before), isFalse);
      await closeBlanks(tester);
    });

    testWidgets('a table with no blank holds nothing, and is laid out as it always was', (tester) async {
      await pumpBlanks(tester, 'Costs\n\n| Item | Cost |\n| --- | --- |\n| Ferry | \$45 |\n', more: <Extension>[drawnTables()]);
      expect(tester.widget<GlyphTable>(find.byType(GlyphTable)).cells, isEmpty);
      expect(find.byType(BlankCell), findsNothing);
      await closeBlanks(tester);
    });
  });

  group('how each is drawn', () {
    testWidgets('the square: a hairline of the words’ ink round the question, a quarter of an em inside each end', (tester) async {
      final view = await pumpBlanks(tester, 'Cheapest on {?which day} or so');
      final t = tester.element(find.byType(BlankIcon)).tokens;
      final body = t.len('app-body');
      final start = tester.getRect(find.byKey(const ValueKey<String>('cm-blank-start')));
      final end = endOfSquare(tester);
      final question = editorTextRect(tester, 'which da');
      final letter = question.width / 'which da'.length;
      final brace = tester.getRect(find.byKey(const ValueKey<String>('cm-blankMark-end')));
      // padding: 0 0.25em and a 1px border, each end.
      expect(start.width, closeTo(body * 0.25 + 1, 0.02));
      expect(end.right - brace.right, closeTo(body * 0.25 + 1, 0.02));
      // The start stands straight before `{?`; the icon, the closing brace and the end are one box after the words.
      expect(question.left - start.right, closeTo(2 * letter, 0.6));
      expect(end.left, closeTo(question.right + letter, 0.6));
      expect(brace.width, closeTo(letter, 0.6));
      expect(brace.left - tester.getRect(find.byKey(const ValueKey<String>('cm-blankIcon'))).right, closeTo(body * 0.05, 0.6));
      expect(end.right, closeTo(editorTextRect(tester, ' or so').left, 0.6));
      // One box round the whole square, from the start's outer edge to the end's.
      final box = tester.renderObject<RenderBlankPiece>(find.byKey(const ValueKey<String>('cm-blank-start'))).boxes.single;
      expect(box.left, start.left);
      expect(box.right, closeTo(end.right, 0.01));
      expect(box.height, start.height);
      // The border box: the words' content area and a pixel over and under it.
      final piece = tester.renderObject<RenderBlankPiece>(find.byKey(const ValueKey<String>('cm-blank-start')));
      final area = contentArea(editorLine(tester, 'Cheapest').spec.look.base.style);
      expect(start.height, area.ascent + area.descent + 2);
      // border: 1px dashed color-mix(in oklch, currentColor 45%, transparent)
      expect(piece.color, t.colorOf('color-mix(in oklch, currentColor 45%, transparent)', current: editorLine(tester, 'Cheapest').spec.look.base.color));
      // The marks' own inks.
      final line = editorLine(tester, 'Cheapest').spec;
      Color inkOf(String part) {
        final at = line.projection.display.indexOf(part);
        final index = line.projection.segments.indexWhere((s) => s.displayFrom <= at && s.displayTo > at);
        return line.runs[index].color;
      }

      expect(inkOf('{?'), t.color('app-ink-4'));
      expect(inkOf('which'), t.color('app-ink-3'));
      expect(tester.widget<InlineWords>(find.byKey(const ValueKey<String>('cm-blankMark-end'))).style.color, t.color('app-ink-4'));
      expect(view.state.doc.toString(), 'Cheapest on {?which day} or so');
      await closeBlanks(tester);
    });

    testWidgets('the icon: nine tenths of an em, a fifth of an em after the question, its foot under the baseline', (tester) async {
      await pumpBlanks(tester, 'Cheapest on {?which day}');
      final t = tester.element(find.byType(BlankIcon)).tokens;
      final body = t.len('app-body');
      final icon = tester.getRect(find.byKey(const ValueKey<String>('cm-blankIcon')));
      final words = editorTextRect(tester, 'which da');
      final question = Rect.fromLTRB(words.left, words.top, words.right + words.width / 'which da'.length, words.bottom);
      expect(icon.width, closeTo(body * 0.9, 0.01));
      expect(icon.height, closeTo(body * 0.9, 0.01));
      expect(icon.left - question.right, closeTo(body * 0.2, 0.6));
      final line = editorLine(tester, 'Cheapest');
      final baseline = line.localToGlobal(Offset.zero).dy + line.visualLines.first.baseline;
      // vertical-align: -0.08em on a box with no words: its foot that far under the baseline.
      expect(icon.bottom - baseline, closeTo(body * 0.08, 0.6));
      final drawnIcon = tester.widget<AppIcon>(find.byKey(const ValueKey<String>('cm-blankIcon-message-circle-question-mark')));
      expect((drawnIcon.color, drawnIcon.strokeWidth), (t.color('app-ink-3'), 2.2));
      await closeBlanks(tester);
    });

    testWidgets('the words after: four fifths of the line, the quiet ink, six tenths of their own em off the square', (tester) async {
      await pumpBlanks(tester, 'Days until Easter: {?}', width: 600);
      final t = tester.element(find.byType(BlankAfter)).tokens;
      final body = t.len('app-body');
      final words = tester.widget<InlineWords>(find.byKey(const ValueKey<String>('cm-blankWords')));
      expect((words.text, words.style.fontSize, words.style.color), ('Can’t work out', body * 0.8, t.color('app-ink-3')));
      final box = tester.getRect(find.byKey(const ValueKey<String>('cm-blankWords')));
      // An empty blank is drawn whole.
      final end = tester.getRect(find.byKey(const ValueKey<String>('cm-blank-whole')));
      expect(box.left - end.right, closeTo(body * 0.8 * 0.6, 0.6));
      await closeBlanks(tester);
    });

    testWidgets('a worked-out answer stands after its square as a sum’s does, and a tap on it opens the panel', (tester) async {
      final view = await pumpBlanks(tester, 'Days until Christmas: {?}');
      expect(find.text('→ 88 days'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('cm-blankAnswer')));
      await tester.pump();
      expect(find.text('Worked out by the app'), findsOneWidget);
      // The tap was the answer's own: the caret did not move.
      expect(view.state.selection.main.head, 0);
      await closeBlanks(tester);
    });

    testWidgets('the pill is the suggestion pill, after the line; a tap presses its blanks and never moves the caret', (tester) async {
      final given = Given();
      final view = await pumpBlanks(tester, 'Cheapest on {?which day}\n\nThe capital is {?}.', given: given, caret: 40);
      final t = tester.element(find.byType(FillPill).first).tokens;
      final body = t.len('app-body');
      final pill = find.byKey(const ValueKey<String>('cm-fillPill')).first;
      final words = tester.widget<InlineWords>(find.descendant(of: pill, matching: find.byType(InlineWords)));
      expect((words.text, words.style.fontSize, words.style.color), ('Fill', body * 0.68, t.color('app-ink-3')));
      await tester.tap(pill);
      await tester.pump();
      expect(given.pressed.map(targetsJson), [
        [
          {'key': 'which day\u00000', 'question': 'which day', 'order': 0},
        ],
      ]);
      expect(view.state.selection.main.head, 40);
      await closeBlanks(tester);
    });

    test('a press on the icon or an end is the editor’s, so a tap on the square places the caret; one on the words after or the pill is its own', () {
      final down = PointerDownEvent();
      expect(const IconWidget(Lucide.wifi, false).takesPointer(down), isFalse);
      expect(const BlankEndWidget(BlankEnd.start).takesPointer(down), isFalse);
      expect(const AfterWidget('Paused', false, 0).takesPointer(down), isTrue);
      expect(const PillWidget('Fill', false, <int>[0], 'Fill the blank').takesPointer(down), isTrue);
    });

    testWidgets('an empty blank is one box: its ends, its braces and its icon, as tall as any square', (tester) async {
      await pumpBlanks(tester, 'The capital is {?}. And {?where}');
      final t = tester.element(find.byType(BlankIcon).first).tokens;
      final body = t.len('app-body');
      final whole = tester.getRect(find.byKey(const ValueKey<String>('cm-blank-whole')));
      final start = tester.getRect(find.byKey(const ValueKey<String>('cm-blank-start')));
      final letter = editorTextRect(tester, 'capital').width / 7;
      // Border and padding either end, three characters, and the icon with its margins.
      expect(whole.width, closeTo(2 * (body * 0.25 + 1) + 3 * letter + body * (0.2 + 0.9 + 0.05), 0.6));
      expect((whole.top, whole.height), (start.top, start.height));
      await closeBlanks(tester);
    });

    testWidgets('in a heading the square’s icon and ends are the heading’s size', (tester) async {
      await pumpBlanks(tester, '# Trip {?where} now');
      final t = tester.element(find.byType(BlankIcon)).tokens;
      final icon = tester.getRect(find.byKey(const ValueKey<String>('cm-blankIcon')));
      expect(icon.width, closeTo(t.len('app-h1') * 0.9, 0.01));
      expect(tester.getRect(find.byKey(const ValueKey<String>('cm-blank-start'))).width, closeTo(t.len('app-h1') * 0.25 + 1, 0.02));
      await closeBlanks(tester);
    });

    testWidgets('a card’s still note draws the square with no icon', (tester) async {
      await pumpBlanks(tester, 'Cheapest on {?which day}', still: true);
      expect(find.byType(BlankIcon), findsNothing);
      expect(find.byKey(const ValueKey<String>('cm-blank-start')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('cm-blank-end')), findsOneWidget);
      expect(tester.renderObject<RenderBlankPiece>(find.byKey(const ValueKey<String>('cm-blank-start'))).boxes, hasLength(1));
      await closeBlanks(tester);
    });
  });

  // Pictures, to lay beside the page's own drawing of the same note (editor/blanks.ts's theme):
  // `flutter test --update-goldens test/editor_ai/blanks_test.dart`, then open shots/.
  group('pictures', () {
    const note = '# Trip to {?where}\n\n'
        'The capital of Portugal is {?}.\n\n'
        'Flights are cheapest on {?what day / time?}\n\n'
        'Days until Christmas: {?}\n\n'
        'Weather in Lisbon today: {?weather}\n\n'
        'Days until Easter: {?}\n\n'
        'A return flight costs {?price today}\n\n'
        'A plan: {?a friendlier way to say: fix the boiler now, and the date it must be done by}\n\n'
        '- [ ] Pack {?what for rain} and {?what for sun}\n';
    for (final theme in ['light', 'dark']) {
      testWidgets('a drawn table with a blank and a filled answer in its cells, and its Fill pill, $theme', (tester) async {
        await pumpBlanks(
          tester,
          'Costs\n\n| Item | Cost | When |\n| --- | --: | --- |\n| Cabin {?how much a night} | ??\$200??(Qwen3.5 4B from memory, 2026-09-28) each | {?} |\n| Ferry | \$45 | Friday |\n',
          theme: theme,
          more: <Extension>[drawnTables()],
        );
        await shot(tester, 'blanks-table-$theme');
        await closeBlanks(tester);
      });

      testWidgets('a note with its blanks, in the Markdown view, $theme', (tester) async {
        await pumpBlanks(tester, note, theme: theme);
        await shot(tester, 'blanks-note-$theme');
        await closeBlanks(tester);
      });

      testWidgets('the same note in the Formatted view, its braces gone, $theme', (tester) async {
        await pumpBlanks(tester, note, theme: theme, display: NoteView.formatted);
        await shot(tester, 'blanks-formatted-$theme');
        await closeBlanks(tester);
      });

      testWidgets('blanks being filled, one waiting behind, $theme', (tester) async {
        final fills = FakeFills()..start();
        const doc = 'Flights are cheapest on {?what day / time?}\n\nThe capital of Portugal is {?}.\n\nUntouched: {?which airport}\n';
        final view = await pumpBlanks(tester, doc, theme: theme, given: fills.given());
        final landing = FillLanding('n1', view, wisp: () => false, owner: () => null);
        addTearDown(landing.dispose);
        final all = editorBlanks(view.state);
        pressBlanks(view, all.take(2).toList(), all);
        for (var i = 0; i < 50 && fills.models.isEmpty; i++) {
          await tester.pump();
        }
        await tester.pump();
        expect(pills(view), ['Filling', 'Filling', 'Fill']);
        await shot(tester, 'blanks-busy-$theme', settle: const Duration(milliseconds: 400));
        fills.stop();
        await closeBlanks(tester);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('the words after a blank that did not fill, and one paused, $theme', (tester) async {
        final fills = FakeFills()..start();
        const doc = 'Flights are cheapest on {?what day / time?}\n\nThe capital of Portugal is {?}.\n';
        final view = await pumpBlanks(tester, doc, theme: theme, given: fills.given());
        final landing = FillLanding('n1', view, wisp: () => false, owner: () => null);
        addTearDown(landing.dispose);
        fillAll(view);
        for (var i = 0; i < 50 && fills.models.isEmpty; i++) {
          await tester.pump();
        }
        fills.models.single.finish('[1] UNKNOWN\n[2]');
        for (var i = 0; i < 50 && fillOutcome('n1', '\u00000') == null; i++) {
          await tester.pump();
        }
        await tester.pump();
        expect(after(view), ['Not known', 'No answer came']);
        await shot(tester, 'blanks-failed-$theme', settle: const Duration(milliseconds: 400));
        fills.stop();
        await closeBlanks(tester);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('a live blank paused under Local only, and refused with lookups off, $theme', (tester) async {
        await pumpBlanks(tester, 'Weather in Lisbon today: {?weather}\n\nWeather in Porto tomorrow: {?}\n', theme: theme, given: Given(lookups: Lookups.localOnly));
        await shot(tester, 'blanks-paused-$theme');
        await closeBlanks(tester);
      });

      testWidgets('a filled answer, its bracket hidden, beside a blank, $theme', (tester) async {
        const doc = 'Flights are cheapest to Tokyo on ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)\n\nThe capital of Australia is {?}.\n';
        await pumpBlanks(tester, doc, theme: theme);
        await shot(tester, 'blanks-filled-$theme');
        await closeBlanks(tester);
      });
    }

    testWidgets('a square that wraps is closed on each line it is on, light', (tester) async {
      await pumpBlanks(tester, 'A plan: {?a friendlier way to say: fix the boiler now, and the date it must be done by}', display: NoteView.formatted);
      final boxes = tester.renderObject<RenderBlankPiece>(find.byKey(const ValueKey<String>('cm-blank-start'))).boxes;
      expect(boxes, hasLength(3));
      expect(boxes[1].top, greaterThan(boxes[0].bottom));
      await closeBlanks(tester);
    });

    testWidgets('the line being written: no icon and no pill until the hands stop, light', (tester) async {
      final view = await pumpBlanks(tester, 'Cheapest on \n\nThe capital is {?}.', caret: 12);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 12, insert: '{?which day}'), selection: EditorSelection.single(23), userEvent: 'input.type'));
      await tester.pump();
      expect(pills(view), ['Fill']);
      await shot(tester, 'blanks-typing-light', settle: const Duration(milliseconds: 200));
      await closeBlanks(tester);
    });
  });
}

/// The box that ends the first square on screen: the icon, the closing brace and the end's room.
Rect endOfSquare(WidgetTester tester) => tester.getRect(find.byWidgetPredicate((w) => w is BlankPiece && w.end == BlankEnd.end).first);

/// A blank for the model, as its lane: what `wordsAfter` is asked with where only the status matters.
class ModelLaneForWords {
  const ModelLaneForWords();

  Lane get lane {
    final view = editor('Cheapest on {?which day}');
    return laneAt(view.state, editorBlanks(view.state).single);
  }
}

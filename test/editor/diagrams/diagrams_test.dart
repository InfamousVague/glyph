// A diagram drawn in a note (lib/editor/diagrams/diagrams.dart): "a diagram drawn in a note" of
// src/app/editor/mermaid.test.ts, case for case and in its order, with the web view stood in for as that file
// stands in for Mermaid (support.dart), and then what the page left to the browser or does not have: the caret in
// the fence, a tap on the drawing, where the picture sits, the picture kept while another is made, the height
// remembered, and how little a keystroke may cost.
//
// What is asked differently: "drawn safely and in the page's colours" looked at the settings Mermaid was handed
// (`securityLevel: 'strict'`, `theme: 'neutral'`). Those are the page's here (assets/diagrams/page.js), read as
// they are written, and what the block asks is which way the app is painted.
import 'dart:io';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/editor_text.dart';
import '../../support/render.dart';
import '../media/support.dart' show pumpNote;
import 'support.dart';

const Key _text = ValueKey<String>('cm-mermaidText');
const Key _why = ValueKey<String>('cm-mermaidWhy');
const Key _picture = ValueKey<String>('cm-mermaidPicture');

late HeldBridge bridge;

/// A note with a diagram of each of `codes`, in order.
String noteOf(List<String> codes) => ['Before', for (final code in codes) '```mermaid\n$code\n```', 'After'].join('\n\n');

Future<EditorView> open(WidgetTester tester, List<String> codes, {String theme = 'light', int? caret, bool readOnly = false}) =>
    pumpNote(tester, noteOf(codes), more: <Extension>[drawnMermaid()], theme: theme, caret: caret, readOnly: readOnly);

/// What a drawn block shows of itself.
String? textOf(WidgetTester tester, Finder block) {
  final found = find.descendant(of: block, matching: find.byKey(_text));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

String? whyOf(WidgetTester tester, Finder block) {
  final found = find.descendant(of: block, matching: find.byKey(_why));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

/// The render asked `index`th draws, and the block hears of it: the answer is handed on after a frame, and shown in
/// the next.
Future<void> finish(WidgetTester tester, int index, {Size block = const Size(390, 120), Rect at = const Rect.fromLTWH(145, 12, 100, 80)}) async {
  bridge.finish(index, block: block, at: at);
  await tester.pump();
  await tester.pump();
}

/// The render asked `index`th fails, in Mermaid's words, and the block hears of it.
Future<void> fail(WidgetTester tester, int index, String said) async {
  bridge.fail(index, said);
  await tester.pump();
  await tester.pump();
}

bool drawn(WidgetTester tester, Finder block) => find.descendant(of: block, matching: find.byKey(_picture)).evaluate().isNotEmpty;

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    bridge = HeldBridge();
    diagramStore = DiagramStore(bridge: bridge, decode: smallPicture);
    rememberDiagramHeights = false;
  });

  group('a diagram drawn in a note', () {
    testWidgets('is its own text until it is drawn, then the picture, in the page\'s colours', (tester) async {
      await open(tester, ['flowchart TD\n  A --> B']);
      final diagram = find.byType(DrawnDiagram);
      expect(diagram, findsOneWidget);
      expect(find.bySemanticsLabel('Diagram'), findsOneWidget);
      expect(textOf(tester, diagram), 'flowchart TD\n  A --> B');
      // The fence's own lines are not on the page: the block stands in their place.
      expect(editorText('```mermaid'), findsNothing);
      expect(editorText('Before'), findsOneWidget);
      await tester.pump();
      expect(bridge.codes, ['flowchart TD\n  A --> B']);
      await finish(tester, 0);
      expect(drawn(tester, diagram), isTrue);
      expect(textOf(tester, diagram), isNull);
      // Mermaid's grey on a light page, in a note 390 across on a screen 390 across.
      final ask = bridge.asked.single;
      expect((ask.dark, ask.room, ask.viewport), (false, 390, 390));
    });

    testWidgets('is asked of Mermaid safely, in grey on a light page and never in its lavender', (tester) async {
      final page = File('assets/diagrams/page.js').readAsStringSync();
      // A note can come from anywhere: no HTML out of a diagram, ever.
      expect(page, contains("securityLevel: 'strict'"));
      expect(page, contains("theme: ask.dark ? 'dark' : 'neutral'"));
      expect(page, contains('themeVariables: ask.dark ? DARK_GANTT : {}'));
      expect(page, contains('startOnLoad: false'));
      expect(page, contains("fontFamily: 'inherit'"));
      // And the page lets nothing in from anywhere but its own folder.
      final html = File('assets/diagrams/index.html').readAsStringSync();
      expect(html, contains("default-src 'none'"));
      expect(html, isNot(contains('://')));
      // The Mermaid in the folder is the one a picture's key names.
      expect(File('assets/diagrams/mermaid.min.js').lengthSync(), greaterThan(1 << 20));
      expect(File('assets/diagrams/MERMAID-LICENSE').readAsStringSync(), contains('MIT License'));
    });

    testWidgets('draws one diagram at a time, and draws what it has drawn once', (tester) async {
      await open(tester, ['graph one', 'graph two']);
      await tester.pump();
      // The second waits its turn: Mermaid keeps its settings in one place, and two at once could swap themes.
      expect(bridge.codes, ['graph one']);
      await finish(tester, 0);
      expect(bridge.codes, ['graph one', 'graph two']);
      await finish(tester, 1);
      final diagrams = find.byType(DrawnDiagram);
      expect(drawn(tester, diagrams.at(0)) && drawn(tester, diagrams.at(1)), isTrue);
      expect(bridge.most, 1);

      // The same diagram shown again, in another note, is not drawn again: it is there in its first frame.
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, ['graph one']);
      expect(drawn(tester, find.byType(DrawnDiagram)), isTrue);
      await tester.pump();
      expect(bridge.asked.length, 2);
    });

    testWidgets('keeps a diagram written wrong as its text, saying what mermaid said, and draws the ones after it', (tester) async {
      await open(tester, ['graph broken', 'graph after']);
      await tester.pump();
      await fail(tester, 0, 'Parse error on line 2:\n...A -->\n------^');
      expect(bridge.codes, ['graph broken', 'graph after']);
      await finish(tester, 1);
      final diagrams = find.byType(DrawnDiagram);
      expect(whyOf(tester, diagrams.at(0)), 'That diagram has a mistake: Parse error on line 2:');
      expect(drawn(tester, diagrams.at(0)), isFalse);
      expect(textOf(tester, diagrams.at(0)), 'graph broken');
      expect(drawn(tester, diagrams.at(1)), isTrue);
    });

    testWidgets('says a diagram could not be drawn here, not that it is wrong, when nothing is there to draw it', (tester) async {
      await open(tester, ['graph offline']);
      await tester.pump();
      await fail(tester, 0, '');
      final diagram = find.byType(DrawnDiagram);
      expect(whyOf(tester, diagram), 'This diagram could not be drawn here.');
      expect(textOf(tester, diagram), 'graph offline');
    });

    testWidgets('is drawn again in the other colours when the app is painted the other way', (tester) async {
      await open(tester, ['graph painted']);
      await tester.pump();
      await finish(tester, 0);
      final diagram = find.byType(DrawnDiagram);
      expect(drawn(tester, diagram), isTrue);
      // A drawn diagram carries its colours inside its picture, so it cannot follow a token.
      preferences.value = const AppPreferences(theme: 'dark');
      await tester.pump();
      await tester.pump();
      expect(bridge.asked.map((ask) => ask.dark), [false, true]);
      // The picture it has stays until the other is made: no words in between.
      expect(drawn(tester, diagram), isTrue);
      expect(textOf(tester, diagram), isNull);
      expect(tester.state<DrawnDiagramState>(diagram).drawn, isFalse);
      await finish(tester, 1);
      expect(tester.state<DrawnDiagramState>(diagram).drawn, isTrue);
    });

    testWidgets('draws nothing for an empty fence', (tester) async {
      await pumpNote(tester, '```mermaid\n\n```', more: <Extension>[drawnMermaid()]);
      expect(find.byType(DrawnDiagram), findsNothing);
      await tester.pump();
      expect(bridge.asked, isEmpty);
    });
  });

  group('the block', () {
    testWidgets('steps aside for its lines while the caret is in them, and is drawn again when the caret leaves', (tester) async {
      final doc = noteOf(['graph LR']);
      final view = await open(tester, ['graph LR'], caret: doc.indexOf('graph LR') + 3);
      // The caret in the fence: the lines themselves, to edit.
      expect(find.byType(DrawnDiagram), findsNothing);
      expect(editorText('```mermaid'), findsOneWidget);
      expect(editorText('graph LR'), findsOneWidget);
      // On either fence is in it too, edges included.
      for (final at in [doc.indexOf('```mermaid'), doc.lastIndexOf('```') + 3]) {
        view.dispatch(TransactionSpec(selection: EditorSelection.single(at)));
        await tester.pump();
        expect(find.byType(DrawnDiagram), findsNothing, reason: 'the caret at $at');
      }
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      expect(find.byType(DrawnDiagram), findsOneWidget);
      expect(editorText('```mermaid'), findsNothing);
      // A view with no caret, never focused or left, draws every block.
      view.dispatch(TransactionSpec(selection: EditorSelection.single(doc.indexOf('graph LR'))));
      await tester.pump();
      expect(find.byType(DrawnDiagram), findsNothing);
      view.setFocused(false);
      await tester.pump();
      expect(find.byType(DrawnDiagram), findsOneWidget);
    });

    testWidgets('a tap puts the caret at the fence\'s first line; in a note that cannot be edited it stays drawn', (tester) async {
      final doc = noteOf(['graph LR']);
      final view = await open(tester, ['graph LR']);
      view.focusRequest = () => view.setFocused(true);
      await tester.pump();
      await finish(tester, 0);
      await tester.tap(find.byType(DrawnDiagram));
      await tester.pump();
      expect(view.state.selection.main.head, doc.indexOf('```mermaid'));
      expect(find.byType(DrawnDiagram), findsNothing);
      expect(editorText('```mermaid'), findsOneWidget);

      // The Formatted view, a card read on a canvas: nothing to type.
      await tester.pumpWidget(const SizedBox.shrink());
      final still = await open(tester, ['graph LR'], readOnly: true);
      still.focusRequest = () => still.setFocused(true);
      await tester.tap(find.byType(DrawnDiagram));
      await tester.pump();
      expect(find.byType(DrawnDiagram), findsOneWidget);
      // And the caret put in its fence does not open it there either.
      still.setFocused(true);
      still.dispatch(TransactionSpec(selection: EditorSelection.single(doc.indexOf('graph LR'))));
      await tester.pump();
      expect(find.byType(DrawnDiagram), findsOneWidget);
    });

    testWidgets('is as tall as the page made it, its picture where the page had it and at its pixels\' size', (tester) async {
      await open(tester, ['flowchart TD\n  A --> B']);
      await tester.pump();
      await finish(tester, 0, block: const Size(390, 141.5), at: const Rect.fromLTWH(120.25, 11.5, 150, 118.5));
      final block = tester.getRect(find.byType(DrawnDiagram));
      expect(block.size, const Size(390, 141.5));
      final picture = tester.getRect(find.byKey(_picture));
      expect(picture.shift(-block.topLeft), const Rect.fromLTWH(120.25, 11.5, 150, 118.5));
      // One image and nothing else painted for it.
      expect(find.descendant(of: find.byType(DrawnDiagram), matching: find.byType(RawImage)), findsOneWidget);
    });

    testWidgets('keeps the picture it has while its words change under it, and asks once more however many letters', (tester) async {
      // A note nobody has the caret in, written from elsewhere: the Academy's page, another member's hand.
      final view = await open(tester, ['graph LR']);
      await tester.pump();
      await finish(tester, 0);
      final diagram = find.byType(DrawnDiagram);
      expect(drawn(tester, diagram), isTrue);
      var at = view.state.doc.toString().indexOf('graph LR') + 8;
      // The first letter goes to the web view; the forty behind it arrive while that render is under way.
      for (var i = 0; i < 41; i += 1) {
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: 'x')));
        at += 1;
        await tester.pump();
        expect(drawn(tester, diagram), isTrue, reason: 'the picture stays through letter ${i + 1}');
        expect(textOf(tester, diagram), isNull);
      }
      expect(bridge.codes, ['graph LR', 'graph LRx']);
      await finish(tester, 1);
      expect(bridge.codes, ['graph LR', 'graph LRx', 'graph LR${'x' * 41}']);
      // Still the old picture: the answer that came was for words the block no longer says.
      expect(tester.state<DrawnDiagramState>(diagram).drawn, isFalse);
      await finish(tester, 2);
      expect(tester.state<DrawnDiagramState>(diagram).drawn, isTrue);
      expect(bridge.most, 1);
    });

    testWidgets('a diagram that turns wrong while it is drawn lets its picture go for its words and why', (tester) async {
      final view = await open(tester, ['graph LR']);
      await tester.pump();
      await finish(tester, 0);
      final at = view.state.doc.toString().indexOf('graph LR') + 8;
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: '\n  A -->')));
      await tester.pump();
      await fail(tester, 1, 'Parse error on line 3:');
      final diagram = find.byType(DrawnDiagram);
      expect(drawn(tester, diagram), isFalse);
      expect(textOf(tester, diagram), 'graph LR\n  A -->');
      expect(whyOf(tester, diagram), 'That diagram has a mistake: Parse error on line 3:');
    });

    testWidgets('a room that changes under a picture fits the picture it has, and asks for the room\'s own once it is still', (tester) async {
      final width = ValueNotifier<double>(390);
      addTearDown(width.dispose);
      final view = EditorView(wholeDocument: true, state: EditorState.create(doc: noteOf(['graph LR']), extensions: noteExtensions(more: <Extension>[drawnMermaid()])));
      addTearDown(view.destroy);
      await pumpApp(
        tester,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(devicePixelRatio: 1),
            child: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (context, wide, _) => SizedBox(width: wide, child: SingleChildScrollView(child: EditorColumn(view: view))),
              ),
            ),
          ),
        ),
      );
      debugDisableShadows = true;
      await tester.pump();
      await tester.pump();
      await finish(tester, 0, block: const Size(390, 120));
      final diagram = find.byType(DrawnDiagram);
      expect(tester.getSize(diagram), const Size(390, 120));
      // A pane dragged narrower, a frame at a time: every width on the way is not a picture worth making.
      for (final wide in <double>[380, 360, 330, 300]) {
        width.value = wide;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(bridge.asked.length, 1);
      expect(tester.getSize(diagram).height, closeTo(120 * 300 / 390, 0.01));
      expect(tester.getSize(find.byKey(_picture)).width, closeTo(100 * 300 / 390, 0.01));
      await tester.pump(diagramSettle);
      await tester.pump();
      expect(bridge.asked.map((ask) => ask.room), [390, 300]);
      await finish(tester, 1, block: const Size(300, 104), at: const Rect.fromLTWH(100, 12, 100, 80));
      expect(tester.getSize(diagram), const Size(300, 104));
      // Wider than the picture was made for, it sits in the middle at its own size until the new one comes.
      width.value = 350;
      await tester.pump();
      expect(tester.getRect(find.byKey(_picture)).left, 25 + 100);
      await tester.pump(diagramSettle);
      await tester.pump();
      expect(bridge.asked.last.room, 350);
      // And back at a width it has the picture for, that picture is there at once, and nothing is asked.
      width.value = 390;
      await tester.pump();
      expect(tester.getSize(diagram), const Size(390, 120));
      await tester.pump(diagramSettle);
      await tester.pump();
      expect(bridge.asked.length, 3);
    });

    testWidgets('a block that leaves the page before its turn is never drawn', (tester) async {
      final doc = noteOf(['graph one', 'graph two']);
      final view = await open(tester, ['graph one', 'graph two']);
      view.focusRequest = () => view.setFocused(true);
      await tester.pump();
      expect(bridge.codes, ['graph one']);
      // The caret goes into the second while the first is in the web view: its block is gone.
      view.setFocused(true);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(doc.indexOf('graph two'))));
      await tester.pump();
      await finish(tester, 0);
      await tester.pump();
      expect(bridge.codes, ['graph one']);
    });
  });

  group('how tall', () {
    test('a diagram never drawn is guessed at from how much it says', () {
      rememberDiagramHeights = false;
      expect(guessDiagramHeight('flowchart TD\n  A --> B'), 80 + 2 * 34);
      // Blank lines are not steps, and a long one is no taller than a screen's half.
      expect(guessDiagramHeight('flowchart TD\n\n  A --> B\n   \n'), 80 + 2 * 34);
      expect(guessDiagramHeight(List<String>.filled(40, 'A --> B').join('\n')), 420);
      expect(const MermaidWidget(code: 'a\nb\nc', from: 0).estimatedHeight, 80 + 3 * 34);
    });

    testWidgets('a diagram drawn is remembered at its height, and waits for its picture at that height, not as its words', (tester) async {
      rememberDiagramHeights = true;
      addTearDown(() => rememberDiagramHeights = false);
      const code = 'graph remembered\n  A --> B\n  B --> C';
      await open(tester, [code]);
      await tester.pump();
      await finish(tester, 0, block: const Size(390, 263.4));
      // To the whole pixel, as the page keeps it; the write waits half a second.
      expect(knownDiagramHeight(code), 263);
      expect(const MermaidWidget(code: code, from: 0).estimatedHeight, 263);
      await tester.pump(const Duration(milliseconds: 600));

      // The next launch: memory has no picture, and the block keeps its room while one is found.
      await tester.pumpWidget(const SizedBox.shrink());
      diagramStore = DiagramStore(bridge: bridge, decode: smallPicture);
      await open(tester, [code]);
      final diagram = find.byType(DrawnDiagram);
      expect(textOf(tester, diagram), isNull);
      expect(tester.getSize(diagram), const Size(390, 263));
      await tester.pump();
      await finish(tester, 1, block: const Size(390, 263.4));
      expect(drawn(tester, diagram), isTrue);
    });
  });

  group('what a keystroke costs', () {
    /// A note of six hundred lines with one diagram in the middle of it. (test/editor/diagrams/fences_test.dart
    /// holds the same counts in a note of two thousand, without a screen.)
    final long = [
      for (var i = 0; i < 300; i += 1) 'A line of the note, number $i.',
      '```mermaid',
      'flowchart TD',
      '  A[Speak] --> B[Note]',
      '```',
      for (var i = 0; i < 300; i += 1) 'Another line, number $i.',
    ].join('\n');

    testWidgets('a letter outside a diagram reads no diagram, asks for no picture and draws the same blocks', (tester) async {
      final view = await pumpNote(tester, long, more: <Extension>[drawnMermaid()], caret: long.length);
      await tester.pump();
      await finish(tester, 0);
      expect(bridge.asked.length, 1);
      DiagramWork.reset();
      // Typed after the diagram: nothing of it moved, and the set of blocks drawn is the same set.
      final blocks = drawnMermaidIn(view.state);
      for (var i = 0; i < 50; i += 1) {
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: 'x'), selection: EditorSelection.single(view.state.doc.length + 1)));
        await tester.pump();
      }
      expect(drawnMermaidIn(view.state), same(blocks));
      // Typed before it: it moved, and that is all.
      for (var i = 0; i < 50; i += 1) {
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: 6 + i, insert: 'x'), selection: EditorSelection.single(7 + i)));
        await tester.pump();
      }
      // A hundred letters: each looked at its own line, before and after, for a fence's mark, and no more.
      expect((DiagramWork.scans, DiagramWork.reads, DiagramWork.lines), (0, 0, 200));
      expect(bridge.asked.length, 1);
      expect(drawn(tester, find.byType(DrawnDiagram)), isTrue);
      // And the caret wandering the note outside it: nothing.
      DiagramWork.reset();
      final moved = drawnMermaidIn(view.state);
      for (var i = 0; i < 50; i += 1) {
        view.dispatch(TransactionSpec(selection: EditorSelection.single(i * 30)));
        await tester.pump();
      }
      expect(drawnMermaidIn(view.state), same(moved));
      expect((DiagramWork.scans, DiagramWork.reads, DiagramWork.lines), (0, 0, 0));
      expect(bridge.asked.length, 1);
    });

    testWidgets('letters typed in a diagram\'s fence ask for nothing until the caret leaves it, then for one picture', (tester) async {
      final view = await pumpNote(tester, long, more: <Extension>[drawnMermaid()], caret: 0);
      await tester.pump();
      await finish(tester, 0);
      var at = long.indexOf('B[Note]') + 7;
      view.dispatch(TransactionSpec(selection: EditorSelection.single(at)));
      await tester.pump();
      DiagramWork.reset();
      const typed = '\n  B --> C[Board]';
      for (var i = 0; i < typed.length; i += 1) {
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: typed[i]), selection: EditorSelection.single(at + 1)));
        at += 1;
        await tester.pump();
      }
      // Each letter read the diagram it is in again, and not the note; the web view heard nothing.
      expect((DiagramWork.scans, DiagramWork.reads), (0, typed.length));
      expect(bridge.asked.length, 1);
      view.dispatch(TransactionSpec(selection: EditorSelection.single(0)));
      await tester.pump();
      await tester.pump();
      expect(bridge.codes, ['flowchart TD\n  A[Speak] --> B[Note]', 'flowchart TD\n  A[Speak] --> B[Note]\n  B --> C[Board]']);
    });

    testWidgets('a note with no diagram does nothing for one', (tester) async {
      final plain = long.replaceAll('```', '');
      final view = await pumpNote(tester, plain, more: <Extension>[drawnMermaid()], caret: 0);
      DiagramWork.reset();
      for (var i = 0; i < 50; i += 1) {
        view.dispatch(TransactionSpec(changes: ChangeSpec(from: i, insert: 'x'), selection: EditorSelection.single(i + 1)));
        await tester.pump();
      }
      expect(drawnMermaidIn(view.state), same(Decoration.none));
      expect((DiagramWork.scans, DiagramWork.reads, DiagramWork.lines), (0, 0, 100));
      expect(bridge.asked, isEmpty);
    });
  });
}

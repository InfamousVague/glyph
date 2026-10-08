// editor/suggestions.test.ts, case for case.
//
// What is asked differently: the word is a widget in a drawn note, pressed with the tester's own finger. The page's
// three cases of "what a finger's press is allowed to do" were about the browser (a touch whose default is taken
// away never becomes a click; a pointer or mouse press with its default taken keeps the caret off the line): here
// there is one press, so they are asked as what they were for: a touch still runs what is offered, and the
// editor is told the press is the word's own (`takesPointer`), which is what keeps the caret off the line.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/suggestions.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../../support/render.dart';
import 'support.dart';

/// Every to-do line gets a word, like the Notion plugin offers.
List<LineSuggestion> todos(String body, Future<void> Function() run) => <LineSuggestion>[
  for (final (index, text) in body.split('\n').indexed)
    if (text.startsWith('- [ ] ')) LineSuggestion(line: index + 1, label: 'Notion', busyLabel: 'Sending', run: run),
];

Future<void> nothing() async {}

Future<EditorView> open(WidgetTester tester, String doc, int caret, {Future<void> Function() run = nothing}) =>
    pumpNote(tester, doc, more: <Extension>[lineSuggestions(suggest: (body) => todos(body, run))], caret: caret);

List<String> words(WidgetTester tester) => tester.widgetList<SuggestWord>(find.byType(SuggestWord)).map((word) => word.word.label).toList();

LineSuggestion second({Future<void> Function() run = nothing}) => LineSuggestion(line: 2, label: 'Notion', busyLabel: 'Sending', run: run);

void main() {
  setUpAll(loadAppFonts);

  group('inline suggestions', () {
    testWidgets('puts the word after every line offered, except the one being typed', (tester) async {
      final view = await open(tester, '- [ ] milk\n- [ ] eggs\nplain\n', 0);
      expect(words(tester), <String>['Notion']);
      // The caret leaves the first line: both to-dos have their word.
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length)));
      await tester.pump();
      expect(words(tester), <String>['Notion', 'Notion']);
    });

    testWidgets('follows the note as it changes', (tester) async {
      final view = await open(tester, 'plain\n', 0);
      expect(words(tester), isEmpty);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: view.state.doc.length, insert: '- [ ] call the plumber\n'), selection: EditorSelection.single(0)));
      await tester.pump();
      expect(words(tester), <String>['Notion']);
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 6, to: 12, insert: '- [x] ')));
      await tester.pump();
      expect(words(tester), isEmpty);
    });

    testWidgets('says its busy word while it runs, then the word again', (tester) async {
      final running = Completer<void>();
      await open(tester, '- [ ] milk\n', 11, run: () => running.future);
      expect(words(tester), <String>['Notion']);
      await tester.tap(find.byType(SuggestWord));
      await tester.pump();
      expect(words(tester), <String>['Sending']);
      expect(tester.widget<SuggestWord>(find.byType(SuggestWord)).word.busy, isTrue);
      // A busy word takes no second press.
      await tester.tap(find.byType(SuggestWord));
      running.complete();
      await tester.pump();
      await tester.pump();
      expect(words(tester), <String>['Notion']);
    });
  });

  group('a pill pressed with a finger', () {
    testWidgets('stays on its line while the finger is down, even once the caret lands there', (tester) async {
      final view = await pumpNote(tester, '- [ ] Book the cabin\n- [ ] Call Sam', more: <Extension>[lineSuggestions(suggest: (_) => <LineSuggestion>[second()])], caret: 0);
      expect(find.byType(SuggestWord), findsOneWidget);
      // A finger goes down on it, and the caret moves to that line the way a tap on the editor moves it.
      final finger = await tester.startGesture(tester.getCenter(find.byType(SuggestWord)));
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.line(2).from + 3)));
      await tester.pump();
      expect(find.byType(SuggestWord), findsOneWidget, reason: 'the pill is held while the finger is down');
      // The finger lifts: the line is being typed on now, so the pill goes as it always did.
      await finger.cancel();
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.line(2).from + 4)));
      await tester.pump();
      expect(find.byType(SuggestWord), findsNothing);
    });
  });

  group('what a finger’s press is allowed to do', () {
    Future<EditorView> pill(WidgetTester tester, {Future<void> Function() run = nothing}) =>
        pumpNote(tester, 'words\n- [ ] Book the cabin', more: <Extension>[lineSuggestions(suggest: (_) => <LineSuggestion>[second(run: run)])], caret: 0);

    testWidgets('keeps a touch alive so it still makes a tap of it', (tester) async {
      var done = 0;
      await pill(tester, run: () async => done += 1);
      await tester.tap(find.byType(SuggestWord), kind: PointerDeviceKind.touch);
      await tester.pump();
      expect(done, 1, reason: 'a touch on the pill must still run what it offers');
    });

    testWidgets('keeps a mouse or pointer press from the editor, which is what keeps the caret off the line', (tester) async {
      final view = await pill(tester);
      final at = tester.getCenter(find.byType(SuggestWord));
      final hit = view.hitAt(at)!;
      for (final kind in <PointerDeviceKind>[PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
        expect(hit.widget, isA<SuggestWidget>());
        expect(hit.widget!.takesPointer(PointerDownEvent(position: at, kind: kind)), isTrue, reason: kind.name);
      }
      final before = view.state.selection.main.head;
      await tester.tap(find.byType(SuggestWord), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(view.state.selection.main.head, before);
    });

    testWidgets('runs what it offers when the tap arrives', (tester) async {
      var done = 0;
      await pill(tester, run: () async => done += 1);
      await tester.tap(find.byType(SuggestWord));
      await tester.pump();
      expect(done, 1);
    });
  });
}

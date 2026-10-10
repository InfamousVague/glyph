// The AI's changes as they are drawn (lib/editor/ai/ai_changes.dart): the cases of `src/app/editor/aiChanges.test.ts`
// that ask the page what it shows (`.cm-aiAdded`, `.cm-aiGoneBlock`, `.cm-aiPill`), which test/ai/ai_changes_test.dart
// had to skip, then what each widget is drawn with, held to the theme's own numbers, and pictures in shots/ to lay
// beside the page.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/ai/ai_changes.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import '../editor/media/support.dart';
import '../support/editor_text.dart';
import '../support/render.dart';

AiChange change({String id = 'c1', String runId = 'r1', int from = 0, int to = 0, String removed = '', bool block = true}) =>
    AiChange(id: id, runId: runId, from: from, to: to, removed: removed, block: block);

/// The `cm-aiAdded` marks, in order: the words under each.
List<String> added(EditorView view) {
  final found = <({int from, int to})>[];
  for (final set in view.decorations) {
    set.between(0, view.state.doc.length, (from, to, value) {
      if ((value.spec.className ?? '') == 'cm-aiAdded') found.add((from: from, to: to));
      return null;
    });
  }
  found.sort((a, b) => a.from - b.from);
  return [for (final mark in found) view.state.sliceDoc(mark.from, mark.to)];
}

Finder pill(String word) => find.byKey(ValueKey<String>('cm-aiPill-$word'));
Finder goneLines() => find.byKey(const ValueKey<String>('cm-aiGoneLine'));

void main() {
  setUpAll(loadAppFonts);

  group('the AI’s changes, tracked', () {
    testWidgets('marks added words, draws the words that went, and tells the note when the marks change', (tester) async {
      final told = <int>[];
      final v = await pumpNote(tester, '# Trip\nCall the plumber.\n', more: [aiChanges(onMarks: (changes) => told.add(changes.length))]);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 7, to: 24, removed: 'call plumber')])));
      await tester.pump();
      expect(told, [1]);
      expect(added(v), ['Call the plumber.']);
      expect(tester.widget<Text>(goneLines()).data, 'call plumber');
      expect(tester.widgetList<AiPill>(find.byType(AiPill)).map((p) => p.word), ['Keep', 'Revert']);
    });

    testWidgets('keeps a change from its pill: the marks go and the words stay', (tester) async {
      final v = await pumpNote(tester, 'a\nb\n', more: [aiChanges()]);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 2, to: 3)])));
      await tester.pump();
      await tester.tap(pill('keep'));
      await tester.pump();
      expect(v.state.field(aiChangesField), isEmpty);
      expect(v.state.doc.toString(), 'a\nb\n');
      expect(find.byType(AiPill), findsNothing);
      expect(added(v), isEmpty);
    });

    testWidgets('reverts a change from its pill, and a press on a pill never moves the caret', (tester) async {
      final v = await pumpNote(tester, 'a\nNEW\nc\n', more: [aiChanges()], caret: 0);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 2, to: 5)])));
      await tester.pump();
      await tester.tap(pill('revert'));
      await tester.pump();
      expect(v.state.doc.toString(), 'a\nc\n');
      expect(v.state.selection.main.head, 0);
      expect(v.state.field(aiChangesField), isEmpty);
    });

    testWidgets('gives neighbouring changes from one run one pair of pills, and another run its own', (tester) async {
      final v = await pumpNote(tester, 'one\ntwo\nthree\n\nfar\n', more: [aiChanges()]);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([
        change(id: 'a', from: 0, to: 3),
        change(id: 'b', from: 4, to: 7),
        change(id: 'c', runId: 'r2', from: 8, to: 13),
        change(id: 'd', from: 15, to: 18),
      ])));
      await tester.pump();
      expect([for (final pills in tester.widgetList<AiPills>(find.byType(AiPills))) pills.ids], [['a', 'b'], ['c'], ['d']]);
    });
  });

  group('how each is drawn', () {
    testWidgets('struck words within a line stand before the words that came, without their leading space', (tester) async {
      final v = await pumpNote(tester, 'Call on Thursday.\n', more: [aiChanges()]);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 8, to: 16, removed: ' friday', block: false)])));
      await tester.pump();
      final gone = tester.widget<InlineWords>(find.byKey(const ValueKey<String>('cm-aiGone')));
      final t = tester.element(find.byKey(const ValueKey<String>('cm-aiGone'))).tokens;
      expect(gone.text, 'friday');
      expect(gone.style.decoration, TextDecoration.lineThrough);
      expect(gone.style.color, t.color('app-ink-4'));
      expect(gone.style.decorationColor, t.colorOf('color-mix(in oklch, var(--app-ink, currentColor) 45%, transparent)', current: t.color('app-ink-4')));
      // Before the words that came, a third of an em between them.
      final goneBox = tester.getRect(find.byKey(const ValueKey<String>('cm-aiGone')));
      final words = editorTextRect(tester, 'Thursday');
      expect(goneBox.right, lessThanOrEqualTo(words.left - t.len('app-body') * 0.3 + 0.6));
      expect(goneBox.left, greaterThan(editorTextRect(tester, 'on').right));
      expect(goneBox.right, greaterThan(goneBox.left));
    });

    // Differs 28 (docs/PARITY.md): the page's `.cm-aiGone` is an inline span, which wraps with its line; the port drew
    // the words as one box that could not, so a sentence taken out stood on a row of its own, cut at the page's edge.
    testWidgets('struck words within a line wrap with the line, between words, with the strike across the gaps', (tester) async {
      const gone = ' we should really ring the plumber some time before the end of next week if at all possible';
      expect(goneWords(gone).length, 18);
      expect(goneWords(gone).first, 'we\u00A0');
      expect(goneWords(gone).last, 'possible');
      expect(goneWords(' friday'), ['friday']);
      final v = await pumpNote(tester, 'Call on Thursday.\n', more: [aiChanges()], width: 320);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 8, to: 16, removed: gone, block: false)])));
      await tester.pump();
      final pieces = find.byKey(const ValueKey<String>('cm-aiGone'));
      expect([for (final words in tester.widgetList<InlineWords>(pieces)) words.text.replaceAll('\u00A0', ' ')].join(), gone.trimLeft());
      final rects = [for (final piece in pieces.evaluate()) tester.getRect(find.byWidget(piece.widget))];
      // Nothing of them is past the page's edge, and they are on more rows than one, each row read left to right.
      for (final rect in rects) {
        expect(rect.right, lessThanOrEqualTo(320.5));
      }
      final rows = {for (final rect in rects) rect.top.round()};
      expect(rows.length, greaterThan(1));
      for (var i = 1; i < rects.length; i++) {
        final sameRow = rects[i].top.round() == rects[i - 1].top.round();
        // On a row each piece starts where the last ended: the gap is the last one's own, struck with it.
        if (sameRow) expect(rects[i].left, closeTo(rects[i - 1].right, 0.6));
        if (!sameRow) expect(rects[i].top, greaterThan(rects[i - 1].top));
      }
      // The first is on the line of the words before it, and the words that came follow the last, a third of an em on.
      expect(rects.first.left, greaterThan(editorTextRect(tester, 'on').right));
      final t = tester.element(pieces.first).tokens;
      final came = editorTextRect(tester, 'Thursday');
      expect(came.top.round(), greaterThanOrEqualTo(rects.last.top.round() - 6));
      if ((came.top - rects.last.top).abs() < 8) expect(rects.last.right, lessThanOrEqualTo(came.left - t.len('app-body') * 0.3 + 0.6));
      // Said once, by the first piece: the pieces after it are the same words.
      expect(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Words the AI took out'), findsOneWidget);
    });

    testWidgets('struck lines stand above the line, each on a row at least an em tall, flush with the page as the page has them', (tester) async {
      final v = await pumpNote(tester, '# Trip\nCall the plumber.\n', more: [aiChanges()]);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 7, to: 24, removed: 'call plumber\n\nthursday')])));
      await tester.pump();
      final rows = tester.widgetList<Text>(goneLines()).toList();
      expect([for (final row in rows) row.data], ['call plumber', ' ', 'thursday']);
      final t = tester.element(goneLines().first).tokens;
      final body = t.len('app-body');
      for (final row in rows) {
        expect((row.style!.decoration, row.style!.color, row.style!.fontSize, row.style!.height), (TextDecoration.lineThrough, t.color('app-ink-4'), body, 1.6));
      }
      final block = tester.getRect(find.byKey(const ValueKey<String>('cm-aiGoneBlock')));
      final line = editorTextRect(tester, 'Call the plumber.');
      // `.cm-aiGoneBlock` has no inline padding: it is a block beside the lines, not a `.cm-line`.
      expect(block.left, 0);
      expect(block.bottom, lessThanOrEqualTo(line.top + 0.5));
      expect(block.top, greaterThanOrEqualTo(tester.getRect(editorText('Trip')).bottom - 0.5));
      // Three rows of the editor's leading, and a tenth of an em under them.
      expect(block.height, closeTo(3 * body * 1.6 + body * 0.1, 1.5));
    });

    testWidgets('the pills are a step smaller than the line, Keep the darker, after the last word', (tester) async {
      final v = await pumpNote(tester, 'Call the plumber.\n', more: [aiChanges()]);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 0, to: 17)])));
      await tester.pump();
      final t = tester.element(find.byType(AiPills)).tokens;
      final body = t.len('app-body');
      final keep = tester.widget<InlineWords>(find.descendant(of: pill('keep'), matching: find.byType(InlineWords)));
      final revert = tester.widget<InlineWords>(find.descendant(of: pill('revert'), matching: find.byType(InlineWords)));
      expect((keep.style.fontSize, keep.style.color), (body * 0.68, t.color('app-ink')));
      expect((revert.style.fontSize, revert.style.color), (body * 0.68, t.color('app-ink-3')));
      final keepBox = tester.getRect(pill('keep')), revertBox = tester.getRect(pill('revert'));
      final words = editorTextRect(tester, 'Call the plumber.');
      // margin-inline-start: 0.6em; gap: 0.35em; line-height 1.7 of its own size, and a hairline round it.
      expect(keepBox.left - words.right, closeTo(body * 0.6, 0.6));
      expect(revertBox.left - keepBox.right, closeTo(body * 0.35, 0.6));
      expect(keepBox.height, closeTo(body * 0.68 * 1.7 + 2, 0.6));
      // Padding of 0.6em of its own size either side of the word.
      final word = tester.getRect(find.descendant(of: pill('keep'), matching: find.byType(InlineWords)));
      expect(word.left - keepBox.left, closeTo(body * 0.68 * 0.6 + 1, 0.6));
    });
  });

  // Pictures, to lay beside the page's own drawing of the same note (editor/aiChanges.ts's theme):
  // `flutter test --update-goldens test/editor_ai/ai_changes_test.dart`, then open shots/.
  group('pictures', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('a rewrite landed in a note, $theme', (tester) async {
        const doc = '# Trip\n\n- [ ] Call the plumber, before Thursday.\n- [ ] Eggs and coffee.\n\nBook the cabin for the second week of October.\n';
        final v = await pumpNote(tester, doc, more: [aiChanges()], theme: theme);
        final plumber = doc.indexOf('- [ ] Call');
        final call = doc.indexOf('Call');
        final thursday = doc.indexOf('before Thursday.');
        final eggs = doc.indexOf('- [ ] Eggs');
        final book = doc.indexOf('Book the cabin');
        v.dispatch(TransactionSpec(effects: addAiChanges.of([
          change(id: 'a', from: 0, to: 6, removed: 'trip', block: false),
          change(id: 'b', from: plumber, to: plumber + 5, removed: '', block: false),
          change(id: 'c', from: call, to: call + 4, removed: 'call', block: false),
          change(id: 'd', from: thursday, to: thursday + 16, removed: ' thursday', block: false),
          change(id: 'e', from: eggs, to: eggs + 22),
          change(id: 'f', runId: 'r2', from: book, to: book, removed: 'old thing\nand another line the model took out'),
        ])));
        await tester.pump();
        await shot(tester, 'ai-changes-$theme');
      });
    }

    testWidgets('a pill held down, light', (tester) async {
      final v = await pumpNote(tester, 'Call the plumber.\n', more: [aiChanges()]);
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 0, to: 17)])));
      await tester.pump();
      final gesture = await tester.startGesture(tester.getCenter(pill('keep')));
      await tester.pump(const Duration(milliseconds: 50));
      await shot(tester, 'ai-pill-pressed-light', settle: Duration.zero);
      await gesture.up();
    });
  });
}

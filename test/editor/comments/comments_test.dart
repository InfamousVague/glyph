// Comments drawn in the note (lib/editor/comments/comments.dart): `src/app/editor/comments.test.ts`, case for case
// and in its order. Each anchor a round in its author's colour that opens its thread, the words round a selection
// washed in that colour, a resolved thread a ring with no wash, the fence drawn as the threads, and the text as
// written wherever the caret is on it.
//
// What is asked differently: a round and a wash are read from the view's decorations (the widget and the mark the
// page's test found in its HTML), and from what is on the screen where the case is about a press or a picture; the
// wash's colour, which the page left to its stylesheet, is asked of the run's own painter, since here the rule is
// code. The pictures (shots/) are the note drawn in both inks, looked at beside CommentCard.module.css.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/comments/ui/card.dart';
import 'package:ghost_md/editor/comments/comments.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/run_paint.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:glacier/glacier.dart';

import '../../support/editor_text.dart';
import '../../support/render.dart';
import 'support.dart';

/// The ground the highlight round `venue` is painted in.
Color? groundOf(WidgetTester tester, EditorView view) {
  for (final line in tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine))) {
    for (final run in line.spec.runs) {
      final painter = run.painter;
      if (painter is! MarkPaint) continue;
      for (final layer in painter.layers) {
        if (layer is BoxLayer && layer.color != null) return layer.color;
      }
    }
  }
  return null;
}

void main() {
  setUpAll(loadAppFonts);

  group('comments in a note', () {
    testWidgets('draws each anchor as a round in its author’s colour, a resolved one as a ring', (tester) async {
      final view = await pumpComments(tester, note, Hooked().hooks);
      final [venue, band] = roundsOf(view);
      expect(venue.hue, 'sea');
      expect(venue.resolved, isFalse);
      expect(venue.label, 'Comment by sam, 1 reply');
      expect(band.hue, 'rose');
      expect(band.resolved, isTrue);
      expect(band.label, 'Comment by You, resolved');
      // The anchor's text is drawn over: the round stands in for `[^c1]`.
      expect(editorText('[^c1]'), findsNothing);
      expect(editorText('venue'), findsOneWidget);
      expect(find.bySemanticsLabel('Comment by sam, 1 reply'), findsOneWidget);
    });

    testWidgets('opens the thread on a tap of its round, and leaves the caret where it was', (tester) async {
      final hooked = Hooked();
      final view = await pumpComments(tester, note, hooked.hooks);
      final before = view.state.selection.main.head;
      await tester.tap(find.bySemanticsLabel('Comment by sam, 1 reply'));
      await tester.pump();
      expect(hooked.opened, ['c1']);
      expect(view.state.selection.main.head, before);
    });

    testWidgets('washes the words round a selection in the author’s colour, and in none once resolved', (tester) async {
      final view = await pumpComments(tester, note, Hooked().hooks);
      final wash = washesOf(view).single;
      expect(wash.attrs['data-hue'], 'sea');
      expect(wash.attrs.containsKey('data-resolved'), isFalse);
      // The highlight's own span is inside it: the wash is round `==venue==`, delimiters and all.
      expect(view.state.sliceDoc(wash.from, wash.to), '==venue==');
      final t = tester.element(find.byType(EditorLine).first).tokens;
      expect(groundOf(tester, view), hued(t, 'sea').colorOf('color-mix(in oklch, var(--app-space) 30%, transparent)'));
      expect(groundOf(tester, view), isNot(t.colorOf('var(--app-mark, var(--app-wash))')));

      final resolved = note.replaceFirst('  The hall.', '  The hall.\n  resolved matt 2026-10-04T19:06:00Z');
      final after = await pumpComments(tester, resolved, Hooked().hooks);
      expect(washesOf(after).single.attrs.containsKey('data-resolved'), isTrue);
      expect(groundOf(tester, after), const Color(0x00000000));
    });

    testWidgets('leaves a highlight nobody commented on the highlighter’s own colour', (tester) async {
      final view = await pumpComments(tester, 'A ==plain== highlight.\n', Hooked().hooks);
      final t = tester.element(find.byType(EditorLine).first).tokens;
      expect(groundOf(tester, view), t.colorOf('var(--app-mark, var(--app-wash))'));
    });

    testWidgets('shows the anchor as written while the caret is on it, in a focused editor', (tester) async {
      final at = note.indexOf('[^c1]') + 2;
      final view = await pumpComments(tester, note, Hooked().hooks, selection: at);
      // Not focused: the caret on it still leaves the round, since nobody is typing.
      expect(roundsOf(view), hasLength(2));
      view.setFocused(true);
      await tester.pump();
      expect(roundsOf(view), hasLength(1));
      expect(editorText('==venue==[^c1]'), findsOneWidget);
      view.setFocused(false);
      await tester.pump();
      expect(roundsOf(view), hasLength(2));
    });

    testWidgets('draws the fence as the list of threads, open ones first, and a tap opens one and brings its anchor in', (tester) async {
      final hooked = Hooked();
      final effects = <StateEffect<Object?>>[];
      await pumpComments(
        tester,
        note,
        hooked.hooks,
        more: <Extension>[
          EditorViewLike.updateListener.of((update) {
            for (final tr in update.transactions) {
              effects.addAll(tr.effects);
            }
          }),
        ],
      );
      final list = find.byType(DrawnComments);
      expect(list, findsOneWidget);
      expect(wordsOf(tester, list), contains('2 comments, 1 open'));
      final rows = find.descendant(of: list, matching: find.byWidgetPredicate((widget) => widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith('thread ')));
      expect([for (final row in rows.evaluate()) wordsOf(tester, find.byWidget(row.widget))], [contains('The hall or the barn?'), contains('Which band?')]);
      expect(wordsOf(tester, rows.at(0)), contains('1 reply'));
      expect(wordsOf(tester, rows.at(1)), contains('Resolved'));
      expect(editorText('c1 sam 2026'), findsNothing);
      await tester.tap(rows.at(0));
      await tester.pump();
      expect(hooked.opened, ['c1']);
      expect(effects.where((effect) => effect.isOf(EditorViewLike.scrollIntoViewEffect)), hasLength(1));
    });

    testWidgets('puts the caret in the fence from its pencil, which shows its lines', (tester) async {
      final view = await pumpComments(tester, note, Hooked().hooks);
      await tester.tap(find.bySemanticsLabel('Show the comments as written'));
      await tester.pump();
      expect(view.state.doc.lineAt(view.state.selection.main.head).text, 'c1 sam 2026-10-04T19:00:12Z');
      await tester.pump();
      expect(find.byType(DrawnComments), findsNothing);
    });

    testWidgets('has no pencil in a note that cannot be changed', (tester) async {
      await pumpComments(tester, note, Hooked().hooks, readOnly: true);
      expect(find.byType(DrawnComments), findsOneWidget);
      expect(find.bySemanticsLabel('Show the comments as written'), findsNothing);
    });

    testWidgets('draws again in the new colours when told', (tester) async {
      final hooked = Hooked(<String, String>{'sam': 'sea'});
      final view = await pumpComments(tester, note, hooked.hooks);
      expect(roundsOf(view).first.hue, 'sea');
      hooked.colours['sam'] = 'moss';
      view.dispatch(TransactionSpec(effects: refreshComments.of(null)));
      await tester.pump();
      expect(roundsOf(view).first.hue, 'moss');
    });

    testWidgets('draws nothing without hooks, and nothing for a note with no fence', (tester) async {
      final bare = await pumpComments(tester, note, null);
      expect(roundsOf(bare), isEmpty);
      expect(find.byType(DrawnComments), findsNothing);
      expect(editorText('[^c1]'), findsOneWidget);
      final plain = await pumpComments(tester, 'Words[^c1]\n', Hooked().hooks);
      expect(roundsOf(plain), isEmpty);
    });

    testWidgets('tells the hooks when the note changes, so an open card reads its thread again', (tester) async {
      final hooked = Hooked();
      final view = await pumpComments(tester, note, hooked.hooks);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'x')));
      await tester.pump();
      expect(hooked.changed, 1);
    });
  });

  group('how they look', () {
    for (final theme in const ['light', 'dark']) {
      testWidgets('a note with two threads, $theme', (tester) async {
        await pumpComments(tester, note, Hooked().hooks, theme: theme);
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/note-$theme.png'));
      });
    }

    testWidgets('where the round stands on its line: its disc 0.28em over the baseline, in a box for a thumb', (tester) async {
      await pumpComments(tester, note, Hooked().hooks);
      final round = tester.getRect(find.bySemanticsLabel('Comment by sam, 1 reply'));
      final t = tester.element(find.byType(EditorLine).first).tokens;
      final em = t.len('app-body');
      // 0.58em of disc and 0.22em of padding either side, and 0.02em of margin outside that.
      expect(round.width, closeTo(1.06 * em, 0.05));
      expect(round.height, closeTo(1.02 * em, 0.05));
    });
  });
}

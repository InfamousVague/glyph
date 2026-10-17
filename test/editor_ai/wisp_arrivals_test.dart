// Ports, from src/app/editor/wispArrivals.test.ts (tauri/), the cases about the drawing, in its order and under
// its names, onto lib/editor/ai/wisp_arrivals.dart: 'words drawn arriving' (a filter each and no more than the pool
// holds, every word of a paragraph settled past the pool, the filters gone with the editor) and 'the smoke of text
// that went' (drawn in the look the text had). The cases about what is set in motion ('text arriving from smoke in
// the editor', and 'is read where the text stood when the same change adds lines above it') are ported in
// test/editor/marks/wisp_motion_test.dart, onto the file that decides, and are not written twice; one case here
// holds that `wispArrivals()` is that same field.
//
// What is read differently (the Dart file's header, "What differs"):
// - `.cm-wispCh` and `.cm-wispWait` in the DOM are the plugin's marks, read from `view.plugin(wispPlugin)`; a word
//   in motion is the letters wearing one filter, so "how many words are drawing" is how many filters are worn.
// - `svg defs filter` is the filters the editor named (`filtersOf(prefix)`).
// - `vi.advanceTimersByTime` is the held clock (`wispNow`) moved on a frame at a time.
// - The ghost's classes are its text style: the look of the run it stood in.
//
// And beyond the web's cases, a real editor pumped: the marks cover exactly the letters that came, each word starts
// in its turn, each is settled when its time is up and not before, nothing at all happens with reduced motion, the
// filter's numbers along the arc (`shapeAt`), and the lines lie exactly where they do with no extension at all.
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/ai/wisp_arrivals.dart';
import 'package:ghost_md/editor/ai/wisp_filters.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/looks/look.dart';
import 'package:ghost_md/editor/looks/sheets.dart' show baseTheme;
import 'package:ghost_md/editor/marks/wisp_motion.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../support/render.dart';
import 'wisp_support.dart';

TransactionSpec heard(int from, String insert, {int? to, WispKind kind = WispKind.heard}) => TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: insert), annotations: wisp.of(kind));

/// A paragraph of `count` words, heard at once: more than the pool of filters can draw together.
Future<EditorView> hearAtOnce(WidgetTester tester, int count) async {
  final view = await pumpEditor(tester, '', more: <Extension>[wispArrivals()]);
  view.dispatch(heard(0, <String>[for (var n = 0; n < count; n++) 'w$n'].join(' ')));
  await tester.pump();
  return view;
}

/// Every `settle` the editor was told, with the clock as it was.
Extension settles(List<({List<int> ids, double at})> into) => EditorViewLike.updateListener.of((update) {
  for (final tr in update.transactions) {
    for (final effect in tr.effects) {
      final settled = settle.cast(effect);
      if (settled != null) into.add((ids: settled.value, at: clock));
    }
  }
});

void main() {
  setUpAll(loadAppFonts);
  holdClock();

  group('text arriving from smoke in the editor', () {
    test('is the field the motion decides in: a heard phrase moving word by word, and with typing on what is taken out', () {
      final next = EditorState.create(doc: '', extensions: wispArrivals()).update(heard(0, 'buy milk')).state;
      expect(<String>[for (final m in moving(next)) next.doc.sliceString(m.from, m.to)], <String>['buy', 'milk']);
      expect(next.facet(typing), isFalse);
      final typed = EditorState.create(doc: 'buy milk', extensions: wispArrivals(typing: true));
      expect(typed.facet(typing), isTrue);
      final word = typed.update(const TransactionSpec(changes: ChangeSpec(from: 4, to: 8), userEvent: 'delete.selection')).state;
      expect(<String>[for (final m in moving(word)) m.gone], <String>['milk']);
      expect(commonEnds('buy mil', 'buy milk'), (prefix: 7, suffix: 0));
    });

    test('shapes a filter along its arc: bent, soft, low and clear at first, crisp and in place before the end', () {
      expect(shapeAt(0), (scale: 34.0, stdDeviation: 5.0, dy: 4.0, slope: 0.0));
      // The letter fades in over the first third and lifts into place by half way.
      expect(shapeAt(0.3).slope, 1);
      expect(shapeAt(0.15).slope, 0.5);
      expect(shapeAt(0.25).dy, 2);
      expect(shapeAt(0.5).dy, 0);
      // The bend is over by three quarters of the way and the blur a little later.
      expect(shapeAt(0.36).scale, closeTo(34 * 0.25, 0.01));
      expect(shapeAt(0.72).scale, 0);
      expect(shapeAt(0.72).stdDeviation, greaterThan(0));
      expect(shapeAt(0.9), (scale: 0.0, stdDeviation: 0.0, dy: 0.0, slope: 1.0));
      // A tapped box's letter: a gentle throw, and no lift at all.
      expect(shapeAt(0, box: true), (scale: 8.0, stdDeviation: 5.0, dy: 0.0, slope: 0.0));
      // An AI's typed word: the same curves, a lighter throw, blur and lift, so it reads at once.
      expect(shapeAt(0, light: true), (scale: 12.0, stdDeviation: 2.0, dy: 2.0, slope: 0.0));
      expect(shapeAt(0.3, light: true).slope, 1);
      expect(shapeAt(0.5, light: true).scale, lessThan(1.5));
      expect(shapeAt(0.9, light: true), (scale: 0.0, stdDeviation: 0.0, dy: 0.0, slope: 1.0));
      // Leaving: the same curves backwards, thinning as it goes, and rising.
      expect(shapeAt(0, leaving: true), (scale: 0.0, stdDeviation: 0.0, dy: 0.0, slope: 1.0));
      expect(shapeAt(1, leaving: true), (scale: 34.0, stdDeviation: 5.0, dy: -4.8, slope: 0.0));
    });
  });

  group('words drawn arriving', () {
    testWidgets('draws each moving word through a filter of its own, and no more at once than the pool holds', (tester) async {
      final on = await hearAtOnce(tester, 90);
      await advance(tester, 1400);
      final drawing = <String?>{for (final mark in wearing(on)) mark.filter};
      expect(drawing.length, greaterThan(0));
      expect(drawing.length, lessThanOrEqualTo(poolMax));
      expect(filtersOf('${on.plugin(wispPlugin)!.prefix}-').length, lessThanOrEqualTo(poolMax));
      // No two words in one filter.
      final words = <String, Set<int>>{};
      for (final m in moving(on.state)) {
        for (final mark in wearing(on)) {
          if (mark.from >= m.from && mark.to <= m.to) words.putIfAbsent(mark.filter!, () => <int>{}).add(m.id);
        }
      }
      expect(words.values.every((ids) => ids.length == 1), isTrue);
      // A word whose filter is still another's waits its turn, there but unseen.
      expect(waiting(on).length, greaterThan(0));
      await done(tester);
    });

    testWidgets('settles every word of a paragraph heard at once, past as many as the pool holds', (tester) async {
      // A word waiting on a filter once asked to be looked at again next frame; the frame loop then redrew and
      // returned every frame before it settled anything, and past 32 letters in motion none ever finished.
      final on = await hearAtOnce(tester, 90);
      await advance(tester, 10000);
      expect(moving(on.state), isEmpty);
      expect(drawn(on), isEmpty);
      // And then nothing asks for another frame.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      await done(tester);
    });

    testWidgets('takes its filters away with the editor', (tester) async {
      final on = await hearAtOnce(tester, 3);
      await advance(tester, 100);
      final prefix = '${on.plugin(wispPlugin)!.prefix}-';
      expect(filtersOf(prefix), isNotEmpty);
      expect(filterNamed(wearing(on).first.filter), isNotNull);
      on.destroy();
      expect(filtersOf(prefix), isEmpty);
      await done(tester);
    });
  });

  group('the smoke of text that went', () {
    testWidgets('is drawn in the look the text had, where it stood', (tester) async {
      // The box of a to-do is set in the monospace face and the accent colour (markdown.module.css `.taskMarker`);
      // its smoke, drawn as a widget of the line, took the note's prose face until it was given the same classes.
      final box = EditorViewLike.decorations.of(Decoration.set(<Range<Decoration>>[Decoration.mark(className: 'probe-box').range(2, 5)]));
      final probe = baseTheme(LookSheet('probe', <LookRule>[LookRule('probe-box', (p, e) => p.weight = 700)]));
      final view = await pumpEditor(tester, 'a [x] milk', more: <Extension>[box, probe, wispArrivals(typing: true)]);
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 3, to: 4, insert: ' '), userEvent: 'input.type'));
      await tester.pump();
      final ghost = find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_Ghost');
      expect(ghost, findsOneWidget);
      // ignore: avoid_dynamic_calls
      expect((tester.widget(ghost) as dynamic).moving.gone, 'x');
      // ignore: avoid_dynamic_calls
      expect(((tester.widget(ghost) as dynamic).style as TextStyle).fontWeight, FontWeight.w700);
      await advance(tester, 600);
      await done(tester);
    });
  });

  group('a real editor with the arrivals', () {
    testWidgets('marks exactly the letters that came, each word in its turn, and settles each when its time is up', (tester) async {
      final told = <({List<int> ids, double at})>[];
      final view = await pumpEditor(tester, 'Already said. ', more: <Extension>[wispArrivals(), settles(told)]);
      expect(drawn(view), isEmpty);
      const said = 'buy oat milk';
      view.dispatch(heard(14, said));
      await tester.pump();
      final words = moving(view.state);
      expect(<String>[for (final m in words) view.state.doc.sliceString(m.from, m.to)], <String>['buy', 'oat', 'milk']);
      // Staggered: the first starts now, each later one after the one before.
      expect(words[0].at, clock);
      expect(words[1].at, greaterThan(words[0].at));
      expect(words[2].at, greaterThan(words[1].at));
      // At once the first word wears a filter, letter by letter, and the others wait, unseen; the text already set
      // and the spaces between wear nothing.
      expect(<String?>[for (final mark in wearing(view)) mark.text], <String>['b', 'u', 'y']);
      expect(<(int, int)>[for (final mark in wearing(view)) (mark.from, mark.to)], <(int, int)>[(14, 15), (15, 16), (16, 17)]);
      expect(<(int, int)>[for (final mark in waiting(view)) (mark.from, mark.to)], <(int, int)>[(18, 21), (22, 26)]);
      expect(drawn(view).every((mark) => mark.from >= 14), isTrue);
      // The filter starts where the arc does: fully bent, blurred and clear.
      final first = filterNamed(wearing(view).first.filter)!;
      expect((first.scale, first.stdDeviation, first.dy, first.slope), (34.0, 5.0, 4.0, 0.0));

      // The second word's turn: it takes a filter of its own, and the third still waits.
      clock = words[1].at + 1;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(<String?>[for (final mark in wearing(view)) mark.text].join(), 'buyoat');
      expect(<String?>{for (final mark in wearing(view)) mark.filter}.length, 2);
      expect(<(int, int)>[for (final mark in waiting(view)) (mark.from, mark.to)], <(int, int)>[(22, 26)]);
      // The first word's filter has moved on with the clock.
      final t = (clock - words[0].at) / words[0].dur;
      expect(first.scale, shapeAt(t).scale);
      expect(first.slope, shapeAt(t).slope);
      expect(first.scale, lessThan(34));

      // All three in motion: every letter that came is marked, and nothing else.
      clock = words[2].at + 1;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(<String?>[for (final mark in wearing(view)) mark.text].join(), 'buyoatmilk');
      expect(waiting(view), isEmpty);
      expect(<int>{for (final mark in wearing(view)) ...<int>[for (var pos = mark.from; pos < mark.to; pos++) pos]}, <int>{14, 15, 16, 18, 19, 20, 22, 23, 24, 25});
      expect(told, isEmpty, reason: 'nothing settles before its time');

      // Each word's time is up its own arc after it really began (the second and third a millisecond late, above):
      // half a millisecond before, it is still moving; half a millisecond after, the editor has been told, once.
      final ends = <int, double>{for (final m in words) m.id: (m.id == words[0].id ? m.at : m.at + 1) + m.dur};
      final order = <int>[for (final m in words) m.id]..sort((a, b) => ends[a]!.compareTo(ends[b]!));
      for (final id in order) {
        clock = ends[id]! - 0.5;
        await tester.pump(const Duration(milliseconds: 16));
        expect(moving(view.state).any((m) => m.id == id), isTrue, reason: 'word $id is not settled half a millisecond early');
        expect(told.any((one) => one.ids.contains(id)), isFalse);
        clock = ends[id]! + 0.5;
        await tester.pump(const Duration(milliseconds: 16));
        expect(told.where((one) => one.ids.contains(id)).length, 1, reason: 'word $id is settled when its time is up');
        expect(moving(view.state).any((m) => m.id == id), isFalse);
      }
      // Nothing was told early, and nothing twice.
      expect(<int>[for (final one in told) ...one.ids]..sort(), order.toList()..sort());
      for (final one in told) {
        for (final id in one.ids) {
          expect(one.at, greaterThanOrEqualTo(ends[id]!));
        }
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(moving(view.state), isEmpty);
      expect(drawn(view), isEmpty);
      expect(view.state.doc.toString(), 'Already said. buy oat milk');
      await done(tester);
    });

    testWidgets('moves only the letter a rewrite changed, and leaves what it took away to the ghost', (tester) async {
      final view = await pumpEditor(tester, 'buy mil', more: <Extension>[wispArrivals()]);
      view.dispatch(heard(0, 'buy milk', to: 7, kind: WispKind.rewrite));
      await tester.pump();
      expect(<(int, int, String?)>[for (final mark in wearing(view)) (mark.from, mark.to, mark.text)], <(int, int, String?)>[(7, 8, 'k')]);
      await advance(tester, 600);
      expect(moving(view.state), isEmpty);
      // What a rewrite takes back is a ghost, and takes no filter of the pool.
      view.dispatch(heard(0, 'by milk', to: 8, kind: WispKind.rewrite));
      await tester.pump();
      expect(<String>[for (final m in moving(view.state)) m.gone], <String>['u']);
      expect(drawn(view), isEmpty);
      expect(find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_Ghost'), findsOneWidget);
      await advance(tester, 600);
      await tester.pump();
      expect(moving(view.state), isEmpty);
      await done(tester);
    });

    testWidgets('does nothing at all where less motion is asked for', (tester) async {
      final told = <({List<int> ids, double at})>[];
      final view = await pumpEditor(tester, 'Already said. ', more: <Extension>[wispArrivals(typing: true), wispStill.of(true), settles(told)]);
      view.dispatch(heard(14, 'buy oat milk'));
      await tester.pump();
      expect(view.state.doc.toString(), 'Already said. buy oat milk');
      expect(moving(view.state), isEmpty);
      expect(drawn(view), isEmpty);
      expect(filtersOf('${view.plugin(wispPlugin)!.prefix}-'), isEmpty);
      view.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, to: 8), userEvent: 'delete.selection'));
      await tester.pump();
      expect(moving(view.state), isEmpty);
      await tester.pump(const Duration(milliseconds: 50));
      expect(SchedulerBinding.instance.transientCallbackCount, 0, reason: 'no frame is asked for');
      await advance(tester, 1000);
      expect(told, isEmpty);
      await done(tester);
    });

    testWidgets('moves at the chosen pace: a relaxed arc is drawn and settled later', (tester) async {
      final told = <({List<int> ids, double at})>[];
      final view = await pumpEditor(tester, '', more: <Extension>[wispArrivals(), wispPace.of(1.6), settles(told)]);
      view.dispatch(heard(0, 'milk'));
      await tester.pump();
      final word = moving(view.state).single;
      expect(word.dur, greaterThanOrEqualTo(350 * 1.6));
      await advance(tester, 350 * 1.6 - 20, step: 20);
      expect(told, isEmpty);
      await advance(tester, 100 * 1.6 + 60, step: 20);
      expect(told.single.ids, <int>[word.id]);
      await done(tester);
    });

    testWidgets('lays the lines out exactly as with no extension, waiting, mid-arc and settled', (tester) async {
      const before = '# A heading\n\nAlready said, and long enough that the words to come wrap onto a second row. ';
      const said = 'Then **buy** oat milk, find the *keys* and call home before the shops shut.';
      final plain = await pumpEditor(tester, '$before$said');
      final expected = layoutOf(plain);
      final still = await pixels(tester);
      await done(tester);

      final view = await pumpEditor(tester, before, more: <Extension>[wispArrivals()]);
      view.dispatch(heard(before.length, said));
      await tester.pump();
      expect(waiting(view), isNotEmpty);
      expect(layoutOf(view), expected, reason: 'waiting');
      await advance(tester, 180, step: 20);
      expect(wearing(view), isNotEmpty);
      expect(layoutOf(view), expected, reason: 'mid-arc');
      expect(await pixels(tester), isNot(still), reason: 'the words are in smoke');
      await advance(tester, 3000);
      expect(moving(view.state), isEmpty);
      await tester.pump();
      expect(layoutOf(view), expected, reason: 'settled');
      // And the settled page is the plain page, pixel for pixel.
      expect(await pixels(tester), still);
      await done(tester);
    });

    testWidgets('draws a letter crisp and in place for the last tenth of its arc', (tester) async {
      const doc = 'Already said. milk';
      final plain = await pumpEditor(tester, doc, size: const Size(390, 120));
      final still = await pixels(tester);
      await done(tester);
      final view = await pumpEditor(tester, 'Already said. ', more: <Extension>[wispArrivals()], size: const Size(390, 120));
      view.dispatch(heard(14, 'milk'));
      await tester.pump();
      final word = moving(view.state).single;
      clock = word.at + word.dur * 0.95;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(wearing(view), isNotEmpty, reason: 'still marked');
      expect(await pixels(tester), still);
      expect(plain.state.doc.toString(), doc);
      await done(tester);
    });
  });
}

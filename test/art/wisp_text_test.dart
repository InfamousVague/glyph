import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

/// Words from smoke, as the screen sees them: the letters the engine lays out, which of them are waiting, arriving
/// through a smoke of their own, leaving, or set, and when it says the text has settled. Case for case with the web
/// app's art/WispText.test.tsx. What the plan is - which words stay, move or go, and when each letter is due - is
/// test/art/wisp_test.dart; this is the widget and the clock that carry it out.
///
/// The clock is the test's: a frame is sixteen milliseconds of nobody's time. Frames are played one at a time, as a
/// phone plays them, since the engine takes a long gap between two for the app having been away.
void main() {
  const style = TextStyle(fontSize: 20, height: 1.2, color: Color(0xFFEEEEEE));

  Widget host(Widget child, {bool reduced = false, double width = 400}) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduced, devicePixelRatio: 2),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(style: style, child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: child))),
        ),
      );

  /// The box the letters are laid out and drawn in.
  final letterBox = find.descendant(of: find.byType(WispText), matching: find.byWidgetPredicate((widget) => widget is LeafRenderObjectWidget));
  RenderWispText boxOf(WidgetTester tester) => tester.renderObject<RenderWispText>(letterBox);

  WispEngine engineOf(WidgetTester tester) => tester.state<WispTextState>(find.byType(WispText)).engine;
  List<WispLetter> letters(WidgetTester tester) => engineOf(tester).letters.expand((word) => word).toList();
  String drawn(WidgetTester tester) => letters(tester).where((l) => !l.hidden).map((l) => l.ch).join();
  bool bending(WispLetter letter) => letter.run != null;

  /// Runs the animation clock on by [ms], a frame at a time.
  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('types its first text in a letter at a time, each bent by a smoke of its own until it sets', (tester) async {
    await tester.runAsync(() => WispKit.load(seeds: [for (var slot = 0; slot < 8; slot++) wispSlotSeed(slot)]));
    final settled = <String>[];
    await tester.pumpWidget(host(WispText('Hello there', pace: 14, onSettled: settled.add, random: math.Random(1))));
    // The whole text is there for a screen reader from the start.
    expect(tester.getSemantics(letterBox).label, 'Hello there');
    expect(tester.state<WispTextState>(find.byType(WispText)).typing, isTrue);
    expect(letters(tester), hasLength(10));
    expect(drawn(tester).length, lessThan(3));

    await run(tester, 300);
    final partway = drawn(tester);
    expect(partway.length, greaterThan(1));
    expect(partway.length, lessThan(10));
    expect(letters(tester).any(bending), isTrue);
    // Two letters bending at once never share a smoke: sharing one made both flicker.
    final slots = letters(tester).where(bending).map((l) => l.run!.slot).toList();
    expect(slots.toSet().length, slots.length);
    // And each is drawn through a picture of itself, by the shader.
    expect(letters(tester).where(bending).any((l) => l.glyph != null), isTrue);
    expect(settled, isEmpty);

    await run(tester, 5000);
    expect(drawn(tester), 'Hellothere');
    expect(letters(tester).any(bending), isFalse);
    expect(letters(tester).any((l) => l.glyph != null), isFalse);
    expect(settled, ['Hello there']);
    expect(tester.state<WispTextState>(find.byType(WispText)).typing, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swaps only the words that changed', (tester) async {
    final settled = <String>[];
    await tester.pumpWidget(host(WispText('Hold. Talk. Done.', onSettled: settled.add, random: math.Random(2))));
    await run(tester, 5000);
    await tester.pumpWidget(host(WispText('Hold. Talk. Write.', onSettled: settled.add, random: math.Random(2))));
    // The word going is untyped first, while the two that stay never move.
    await run(tester, 40);
    expect(letters(tester).take(9).any(bending), isFalse);
    expect(letters(tester).skip(9).any(bending), isTrue);
    for (var t = 0; t < 3000; t += 50) {
      await run(tester, 50);
      expect(letters(tester).take(9).every((l) => !l.hidden && !bending(l)), isTrue);
    }
    expect(drawn(tester), 'Hold.Talk.Write.');
    expect(settled.last, 'Hold. Talk. Write.');
  });

  testWidgets('shows a text at rest when asked to be still, and still types the next one', (tester) async {
    final settled = <String>[];
    await tester.pumpWidget(host(WispText('Welcome', still: true, onSettled: settled.add)));
    expect(drawn(tester), 'Welcome');
    expect(settled, ['Welcome']);
    await tester.pumpWidget(host(WispText('Welcome back', still: true, onSettled: settled.add)));
    var bent = false;
    for (var t = 0; t < 1000 && !bent; t += 16) {
      await run(tester, 16);
      bent = letters(tester).any(bending);
    }
    expect(bent, isTrue);
    await run(tester, 5000);
    expect(drawn(tester), 'Welcomeback');
    expect(settled.last, 'Welcome back');
  });

  testWidgets('lands at once with reduced motion, and fades a change in whole', (tester) async {
    final settled = <String>[];
    await tester.pumpWidget(host(WispText('Not yet', onSettled: settled.add), reduced: true));
    expect(drawn(tester), 'Notyet');
    expect(letters(tester).any(bending), isFalse);
    expect(settled, ['Not yet']);
    double opacity() => tester.widget<FadeTransition>(find.descendant(of: find.byType(WispText), matching: find.byType(FadeTransition))).opacity.value;
    expect(opacity(), 1);
    await tester.pumpWidget(host(WispText('Now', onSettled: settled.add), reduced: true));
    expect(drawn(tester), 'Now');
    expect(settled.last, 'Now');
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 220));
    expect(opacity(), 1);
  });

  testWidgets('keeps no more than 48 smokes however fast the letters come', (tester) async {
    await tester.pumpWidget(host(WispText(List.filled(40, 'smoke').join(' '), pace: 2000)));
    var most = 0;
    for (var t = 0; t < 1500; t += 16) {
      await run(tester, 16);
      most = math.max(most, engineOf(tester).poolSize);
    }
    expect(most, wispPoolMax);
    await run(tester, 5000);
    expect(letters(tester).every((l) => !l.hidden && !bending(l)), isTrue);
  });

  testWidgets('lands the unseen tail at once when the box clips it, rather than typing on for nobody', (tester) async {
    final settled = <String>[];
    const long = 'A title that runs on well past the two lines its card has room for';
    // A title clamped to its box: what it holds is shorter than what it is asked to show.
    await tester.pumpWidget(host(WispText(long, pace: 14, maxLines: 1, onSettled: settled.add), width: 120));
    expect(boxOf(tester).clipped, isTrue);
    // One letter's setting later, and nowhere near the seconds the whole title would take at this pace.
    await run(tester, 600);
    expect(settled, [long]);
    expect(letters(tester).every((l) => !l.hidden && !bending(l)), isTrue);
  });

  testWidgets('takes what it holds away when it goes, and leaves nothing moving', (tester) async {
    await tester.runAsync(() => WispKit.load(seeds: [for (var slot = 0; slot < 8; slot++) wispSlotSeed(slot)]));
    await tester.pumpWidget(host(const WispText('Gone soon')));
    await run(tester, 100);
    final held = letters(tester).where((l) => l.glyph != null).toList();
    expect(held, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    // The pictures of the letters in motion are let go, and nothing is left on the clock to run against a widget
    // that is gone (the binding itself fails a test that leaves a ticker running).
    expect(held.every((l) => l.glyph == null), isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('lays words out as the page does: letters in boxes of their own, lines broken at gaps and line feeds', (tester) async {
    // The test's own face draws every letter a square of its size, 20px here: eleven letters and a space to a line.
    await tester.pumpWidget(host(const WispText('Hold. Talk.\nDone and dusted.', still: true), width: 230));
    final box = boxOf(tester);
    final rects = box.debugLetterRects;
    expect(rects, hasLength(24));
    // "Hold." and "Talk." share the first line; the line feed starts another; "dusted." does not fit beside "and".
    final lines = rects.map((r) => r.top).toSet().toList()..sort();
    expect(lines, hasLength(3));
    expect(rects[0].top, lines[0]);
    expect(rects[9].top, lines[0]);
    expect(rects[10].top, lines[1]);
    expect(rects[16].top, lines[1]);
    expect(rects[17].top, lines[2]);
    // Along a word each letter starts where the last one ended, and a gap is a space wide.
    for (var i = 1; i < 5; i++) {
      expect(rects[i].left, closeTo(rects[i - 1].right, 1e-6));
    }
    expect(rects[5].left, closeTo(rects[4].right + 20, 1e-6));
    expect(box.size.height, closeTo(3 * 24, 0.5));
    expect(box.clipped, isFalse);
  });

  testWidgets('centres its lines when asked', (tester) async {
    await tester.pumpWidget(host(const WispText('Hi\nthere', still: true, textAlign: TextAlign.center)));
    final box = boxOf(tester);
    final rects = box.debugLetterRects;
    final first = rects[0].left + (rects[1].right - rects[0].left) / 2;
    final second = rects[2].left + (rects[6].right - rects[2].left) / 2;
    expect(first, closeTo(second, 1e-6));
    expect(rects[0].left, greaterThan(0));
  });
}

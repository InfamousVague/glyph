import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/scene/hot_phone.dart';
import 'package:ghost_md/scene/steps.dart';
import 'package:glacier/glacier.dart';

import 'scene_support.dart';

/// The phone drawn: its pins are the cores and light by the busy figure, its rings wear their number, the column is
/// there, the mark is the step's, the case is the faint ink, and nothing but what is painted changes as it warms and
/// glows. The cases of `src/app/scene/HotPhone.test.tsx`, by name. Where the page's tests read an element's
/// attributes, these read the geometry the painter draws ([phonePins], [ringDots], [columnDots]) and the painter's
/// own fields.

Widget phone({Warmth warmth = Warmth.cold, int glowStep = 0, int litPins = 0, int pins = 8, StepId? step = StepId.listen, bool still = false}) =>
    Center(child: SizedBox(width: 240, height: 544, child: HotPhone(warmth: warmth, glowStep: glowStep, litPins: litPins, pins: pins, step: step, still: still)));

HotPhonePainter painter(WidgetTester tester, [int which = 0]) =>
    tester.widgetList<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is HotPhonePainter)).elementAt(which).painter! as HotPhonePainter;

HotPhoneMarkPainter? mark(WidgetTester tester) {
  final found = tester.widgetList<CustomPaint>(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is HotPhoneMarkPainter));
  return found.isEmpty ? null : found.first.painter! as HotPhoneMarkPainter;
}

void main() {
  setUpAll(loadAppFonts);

  group('the phone', () {
    testWidgets('has a pin a core, lit by the busy figure, top and bottom in turn', (tester) async {
      await show(tester, phone(pins: 8, litPins: 6));
      expect(painter(tester).pins, 8);
      expect(painter(tester).litPins, 6);
      final pins = phonePins(8, 6);
      expect(pins.length, 8);
      expect(pins.where((pin) => pin.lit).length, 6);
      // The unlit two are the last of each edge.
      final tops = pins.where((pin) => pin.y == 206).toList();
      final bottoms = pins.where((pin) => pin.y == 282).toList();
      expect(tops.length, 4);
      expect(bottoms.length, 4);
      expect(tops.where((pin) => pin.lit).length, 3);
      expect(bottoms.where((pin) => pin.lit).length, 3);
      expect(tops.last.lit, isFalse);
      expect(bottoms.last.lit, isFalse);
      // A lit pin is filled with the ink and an unlit one with paper: the painter has both from the theme.
      final t = tester.element(find.byType(HotPhone)).tokens;
      expect(painter(tester).ink, t.color('app-ink'));
      expect(painter(tester).paper, t.color('app-paper'));
      await away(tester);
    });

    testWidgets('draws five rings, each wearing its number, and the column above the case', (tester) async {
      await show(tester, phone());
      expect(painter(tester).rings.length, 5);
      expect([for (var n = 1; n <= 5; n += 1) ringDots(n).length], [16, 20, 26, 32, 40]);
      // Ring n is there once the glow reaches it.
      expect([for (var n = 1; n <= 5; n += 1) ringOpacity(3, n)], [1, 1, 1, 0, 0]);
      final column = columnDots();
      expect(column.length, 22);
      // Above the phone: every dot's y is under the case's top.
      for (final dot in column) {
        expect(dot.at.dy, lessThan(6));
      }
      expect(phoneViewBox, const Rect.fromLTWH(0, -64, 240, 544));
      await away(tester);
    });

    testWidgets('wears the glow step and the warmth as its own attributes', (tester) async {
      await show(tester, phone(glowStep: 3, warmth: Warmth.hot));
      final drawn = tester.widget<HotPhone>(find.byType(HotPhone));
      expect(drawn.glowStep, 3);
      expect(drawn.warmth, Warmth.hot);
      // And draws them: three rings, the whole column, the hatch all ink.
      expect(painter(tester).rings, [1, 1, 1, 0, 0]);
      expect(painter(tester).column, 1);
      expect(painter(tester).core, 1);
      await away(tester);
    });

    testWidgets('draws the working step’s mark large, and swaps it with the step as a new node, so its fade plays again', (tester) async {
      await show(tester, phone(step: StepId.listen));
      expect(mark(tester)?.step, StepId.listen);
      await tester.pump(const Duration(milliseconds: 250));
      expect(mark(tester)?.opacity, 1);
      await rerender(tester, phone(step: StepId.think));
      expect(mark(tester)?.step, StepId.think);
      // A new node: its fade starts again from nothing, and is whole 200 ms on.
      expect(mark(tester)!.opacity, lessThan(0.2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(mark(tester)!.opacity, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 110));
      expect(mark(tester)?.opacity, 1);
      await rerender(tester, phone(step: null));
      expect(mark(tester), isNull);
      await away(tester);
    });

    testWidgets('draws the case and the rings in the third ink and the die in full ink over paper', (tester) async {
      await show(tester, phone());
      final t = tester.element(find.byType(HotPhone)).tokens;
      expect(painter(tester).ink3, t.color('app-ink-3'));
      expect(painter(tester).ink, t.color('app-ink'));
      expect(painter(tester).paper, t.color('app-paper'));
      // A cold die's hatch is a quarter there.
      expect(painter(tester).core, 0.25);
      expect(painter(tester).column, 0);
      await away(tester);
    });

    testWidgets('changes nothing but attributes between glow steps and warmths', (tester) async {
      await show(tester, phone(glowStep: 0, warmth: Warmth.cold, litPins: 0));
      int count() => find.descendant(of: find.byType(HotPhone), matching: find.byWidgetPredicate((_) => true)).evaluate().length;
      final was = count();
      await rerender(tester, phone(glowStep: 5, warmth: Warmth.hot, litPins: 8));
      expect(count(), was);
      // The transition: 600 ms on the kit's ease-out, part of the way at 100 ms and there by the end.
      await tester.pump(const Duration(milliseconds: 100));
      expect(painter(tester).rings.last, inExclusiveRange(0, 1));
      expect(painter(tester).core, inExclusiveRange(0.25, 1));
      await tester.pump(const Duration(milliseconds: 520));
      expect(painter(tester).rings, [1, 1, 1, 1, 1]);
      expect(painter(tester).core, 1);
      // Reduced motion steps.
      await rerender(tester, phone(glowStep: 2, warmth: Warmth.warm, litPins: 3, still: true));
      expect(count(), was);
      expect(tester.widget<HotPhone>(find.byType(HotPhone)).still, isTrue);
      expect(painter(tester).rings, [1, 1, 0, 0, 0]);
      expect(painter(tester).core, 0.55);
      expect(painter(tester).column, 0.5);
      await away(tester);
    });

    testWidgets('gives two phones on one page their own hatch and clip', (tester) async {
      // A painter has no ids to share: the hatch and the clip are drawn, each phone its own. What is left to hold is
      // that two phones side by side are two drawings, each with its own warmth.
      await show(tester, Row(children: [Expanded(child: phone(warmth: Warmth.hot)), Expanded(child: phone())]));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(HotPhone), findsNWidgets(2));
      expect(painter(tester, 0).core, 1);
      expect(painter(tester, 1).core, 0.25);
      await away(tester);
    });
  });
}

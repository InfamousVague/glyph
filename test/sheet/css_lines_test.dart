// A line as tall as its stylesheet says (lib/sheet/css.dart `CssLines`, lib/home/home_parts.dart's own) stands on the
// page's baseline on a phone. Held by the page itself.
//
// The page: the Tauri app's WebView (Chrome 133) on an emulator at 1248 x 1972 and 2.625, a notebook's index,
// 2026-10-09. `.chapterTitle` is Inter at 17.6612px on a line of 26.4918 (`line-height: 1.5`): its box is 69.53
// device pixels tall, and a Range over its words (the face's content area) is 56.00 tall and starts 6.00 under the
// box's top, half the leading floored; of the 56 the ascent is 44 (44.9 and 11.2 round to 45 and 11, and the descent
// rounded down takes one from the ascent). So the baseline is 50 device pixels under the line's top, where the
// engine's own is 51.6 and the middle of the page's line a further 0.6: the title stood three device pixels low
// beside the page.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/home/home_parts.dart' as home;
import 'package:ghost_md/sheet/css.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  const ratio = 2.625;
  const size = 17.6612, line = 1.5 * size;

  Future<void> pump(WidgetTester tester, double measuredAt, Widget Function(Tokens t) build) => pumpApp(
        tester,
        size: const Size(1248 / ratio, 1972 / ratio),
        ratio: ratio,
        measuredAt: measuredAt,
        home: Builder(builder: (context) => Align(alignment: Alignment.topLeft, child: build(context.tokens))),
      );

  /// The first baseline of the one paragraph on the page under the top of [lines], in device pixels.
  double baselineUnder(WidgetTester tester, Finder lines) {
    final box = tester.renderObject<RenderBox>(lines);
    final words = tester.renderObject<RenderParagraph>(find.byType(RichText));
    final painter = TextPainter(text: words.text, textDirection: TextDirection.ltr)..layout();
    // Where the engine draws the first line's words: its ascent under the paragraph's top.
    final drawn = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.dispose();
    return (words.localToGlobal(Offset.zero).dy - box.localToGlobal(Offset.zero).dy + drawn) * ratio;
  }

  testWidgets('a line with a height of its own stands on the page’s baseline on a phone', (tester) async {
    await pump(tester, ratio, (t) => cssLines('Plan the first release', t.textAt(size, height: 1.5)));
    expect(tester.getSize(find.byType(CssLines)).height * ratio, closeTo(69.53, 0.02), reason: 'the line, to the fraction');
    expect(baselineUnder(tester, find.byType(CssLines)), closeTo(50, 0.01), reason: 'a content area of 56 starting 6 under the top, 44 of it over the baseline');
    debugDisableShadows = true;
  });

  testWidgets('the home page’s own lines stand on it too, unless told where', (tester) async {
    await pump(tester, ratio, (t) => home.CssLines(lineHeight: line, child: Text('Plan the first release', style: t.textAt(size, height: 1.5))));
    expect(baselineUnder(tester, find.byType(home.CssLines)), closeTo(50, 0.01));
    await pump(tester, ratio, (t) => home.CssLines(lineHeight: line, above: 20, child: Text('Plan the first release', style: t.textAt(size, height: 1.5))));
    expect(baselineUnder(tester, find.byType(home.CssLines)), closeTo(20 * ratio, 0.01), reason: 'a caller’s own baseline is kept');
    debugDisableShadows = true;
  });

  testWidgets('at a desktop’s ratio, where the tests’ rectangles were measured, the words stay in the middle of their line', (tester) async {
    await pump(tester, 1, (t) => cssLines('Plan the first release', t.textAt(size, height: 1.5)));
    final box = tester.renderObject<RenderBox>(find.byType(CssLines));
    final words = tester.renderObject<RenderParagraph>(find.byType(RichText));
    expect(words.localToGlobal(Offset.zero).dy - box.localToGlobal(Offset.zero).dy, closeTo((box.size.height - words.size.height) / 2, 1e-6));
    debugDisableShadows = true;
  });
}

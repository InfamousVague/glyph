import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';

import 'support/pictures.dart';

/// Which shapes of an icon wear the wash, and the icons drawn: the web app's art/iconWash.test.ts for the rule, and
/// the table made from it (lib/art/lucide.g.dart, which tool/lucide.dart holds to the page's own iconWash.css rule by
/// rule before it writes a line).
void main() {
  IconShape shape(String tag, Map<String, Object> attrs) => IconShape(tag, {for (final entry in attrs.entries) entry.key: '${entry.value}'});

  group('an icon\'s body', () {
    test('is its largest closed shape, and an open path is never one', () {
      // The mic: a stand, the cup round the capsule (open), and the capsule.
      final mic = [
        shape('path', {'d': 'M12 19v3'}),
        shape('path', {'d': 'M19 10v2a7 7 0 0 1-14 0v-2'}),
        shape('rect', {'x': 9, 'y': 2, 'width': 6, 'height': 13, 'rx': 3}),
      ];
      expect(bodiesOf(mic), [2]);
    });

    test('leaves what is inside the body a stroke: a cog\'s hole, a tick in a circle', () {
      final inCircle = [
        shape('circle', {'cx': 12, 'cy': 12, 'r': 10}),
        shape('path', {'d': 'm9 12 2 2 4-4'}),
        shape('circle', {'cx': 12, 'cy': 12, 'r': 3}),
      ];
      expect(bodiesOf(inCircle), [0]);
    });

    test('takes a second shape that is clear of the first and of some size, and never a dot', () {
      final two = [
        shape('rect', {'x': 2, 'y': 2, 'width': 8, 'height': 8}),
        shape('rect', {'x': 14, 'y': 14, 'width': 8, 'height': 8}),
        shape('circle', {'cx': 18, 'cy': 5, 'r': 1}),
      ];
      expect(bodiesOf(two), [0, 1]);
    });

    test('has none in an icon of lines alone', () {
      expect(bodiesOf([shape('path', {'d': 'M5 12h14'}), shape('path', {'d': 'm12 5 7 7-7 7'})]), isEmpty);
    });

    test('knows a path that comes back to its start, by a z or by arriving there', () {
      expect(walkPath('M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z').closed, isTrue);
      // The bell: no z, but its last curve ends where it began.
      expect(walkPath('M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326').closed, isTrue);
      expect(walkPath('M19 10v2a7 7 0 0 1-14 0v-2').closed, isFalse);
      // Two lines in one path are not one shape.
      expect(walkPath('M4 4h4v4H4zM14 14h4v4h-4z').closed, isFalse);
      // An arc's flags set against the next number.
      expect(walkPath('M2 12a10 10 0 1020 0 10 10 0 10-20 0').closed, isTrue);
    });
  });

  group('the kit\'s icons, as made', () {
    test('wash the ones that were hollow, each by its body', () {
      expect(Lucide.mic.wash, [2]);
      expect(Lucide.trash2.wash, [2, 4]);
      expect(Lucide.all['settings']!.wash, [0]);
      expect(Lucide.search.wash, [1]);
      for (final name in ['mic', 'bell', 'file-text', 'settings', 'search', 'folder', 'lock', 'image', 'copy', 'palette', 'trash', 'flag']) {
        expect(Lucide.all[name]!.wash, isNotEmpty, reason: name);
      }
      // And never an icon of lines alone.
      for (final name in ['arrow-left', 'check', 'x', 'plus', 'chevron-down']) {
        expect(Lucide.all[name]!.wash, isEmpty, reason: name);
      }
    });

    test('wash the few that are one closed silhouette whole', () {
      for (final name in wholeWashed) {
        final icon = Lucide.all[name];
        if (icon == null) continue;
        expect(icon.wash, [for (var i = 0; i < icon.shapes.length; i++) i], reason: name);
      }
      expect(Lucide.all['bookmark'], isNotNull);
    });

    test('are under the name the web app imports them by, and lucide\'s own', () {
      expect(identical(Lucide.trash2, Lucide.trash), isTrue);
      expect(Lucide.squarePen.name, 'square-pen');
      expect(Lucide.all.length, greaterThan(200));
    });

    test('answer to the other names lucide keeps for them, so a mark that names its icon by a word has it', () {
      // `waves` is one line handing on `waves-horizontal`: Wave's icon on the Style page and in the +'s list.
      expect(identical(Lucide.all['waves'], Lucide.all['waves-horizontal']), isTrue);
      expect(Lucide.all['waves']!.name, 'waves-horizontal');
      expect(identical(Lucide.all['history'], Lucide.history), isTrue);
    });

    test('are paths the app can draw, every shape of every one, inside the 24 grid', () {
      for (final icon in Lucide.all.values) {
        for (final d in icon.shapes) {
          // Walked along its own line: a path's box takes in the handles of its curves, which lie outside it.
          for (final piece in parseSvgPath(d).computeMetrics()) {
            for (var at = 0.0; at <= piece.length; at += 0.5) {
              final point = piece.getTangentForOffset(at)!.position;
              expect(point.dx, inInclusiveRange(-0.01, 24.01), reason: '${icon.name}: $d');
              expect(point.dy, inInclusiveRange(-0.01, 24.01), reason: '${icon.name}: $d');
            }
          }
        }
      }
    });

    test('turn a circle, a box with round corners and a line into the outline lucide\'s own element draws', () {
      // The search's lens: cx 11, cy 11, r 8.
      final lens = parseSvgPath(Lucide.search.shapes[1]);
      expect(lens.contains(const Offset(3.2, 11)), isTrue);
      expect(lens.contains(const Offset(2.8, 11)), isFalse);
      expect(lens.contains(const Offset(11, 18.8)), isTrue);
      expect(lens.contains(const Offset(16.8, 16.8)), isFalse);
      // The mic's capsule: a box 6 by 13 with its ends rounded right over.
      final capsule = parseSvgPath(Lucide.mic.shapes[2]);
      expect(capsule.contains(const Offset(12, 2.2)), isTrue);
      expect(capsule.contains(const Offset(12, 14.8)), isTrue);
      expect(capsule.contains(const Offset(12, 15.2)), isFalse);
      expect(capsule.contains(const Offset(9.2, 2.2)), isFalse);
      expect(capsule.contains(const Offset(12, 8)), isTrue);
    });
  });

  group('an SVG path', () {
    test('reads every command, relative and absolute, and flags set against a number', () {
      expect(parseSvgPath('M4 4h6.5v6.5H4z').getBounds(), const Rect.fromLTRB(4, 4, 10.5, 10.5));
      final ring = parseSvgPath('M2 12a10 10 0 1020 0 10 10 0 10-20 0');
      expect(ring.contains(const Offset(12, 2.2)), isTrue);
      expect(ring.contains(const Offset(12, 21.8)), isTrue);
      expect(ring.contains(const Offset(3.5, 3.5)), isFalse);
      expect(parseSvgPath('M0 0C0 10 10 10 10 0S20-10 20 0').getBounds().right, closeTo(20, 1e-6));
      expect(parseSvgPath('M0 0q5 10 10 0t10 0').getBounds().right, closeTo(20, 1e-6));
      expect(parseSvgPath('m1 1 2 2-.5.5').getBounds(), const Rect.fromLTRB(1, 1, 3, 3.5));
      expect(() => parseSvgPath('4 4h2'), throwsFormatException);
    });
  });

  group('the app\'s own icons', () {
    test('are every one the web app exports, each with its body where it has one', () {
      expect(AppIcons.all.keys, containsAll(['ArrowLeft', 'ArrowRight', 'Cog', 'Plus', 'Magnifier', 'Pin', 'Cassette', 'TickBox', 'Book', 'Notebook', 'Clock', 'Grid', 'ArchiveBox', 'Bin', 'Workspace', 'Board', 'Locate']));
      // Lines alone have nothing to fill.
      expect(AppIcons.arrowLeft.body, isNull);
      expect(AppIcons.plus.body, isNull);
      expect(AppIcons.magnifier.body, 'M10.5 18a7.5 7.5 0 1 1 0-15a7.5 7.5 0 1 1 0 15Z');
      for (final icon in AppIcons.all.values) {
        parseSvgPath(icon.d);
        if (icon.body != null) parseSvgPath(icon.body!);
      }
    });

    test('work the cog out from its radii: eight even teeth round a ring, and the hole in the middle', () {
      final cog = AppIcons.cog.d;
      expect('L'.allMatches(cog).length, 8 * 4 - 1);
      expect(cog, endsWith('ZM15 12a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z'));
      // The tooth pointing along +x: its shoulders at the outer radius.
      expect(cog, startsWith('M19.43 10.40L21.93 10.82L21.93 13.18L19.43 13.60L'));
      final path = Path.from(parseSvgPath(cog))..fillType = PathFillType.evenOdd;
      // The body is washed and the hole stays clear.
      expect(path.contains(const Offset(12, 12)), isFalse);
      expect(path.contains(const Offset(12, 6)), isTrue);
    });

    /// What an icon's painter lays on a canvas 96 pixels square, as pixels.
    Future<Pixels> draw(WidgetTester tester, Widget icon) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(alignment: Alignment.topLeft, child: RepaintBoundary(key: key, child: DefaultTextStyle(style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 48), child: icon))),
        ),
      );
      return capture(tester, key, ratio: 2);
    }

    int alphaAt(Pixels pixels, double x, double y) => pixels.data[((y * pixels.height / 24).floor() * pixels.width + (x * pixels.width / 24).floor()) * 4 + 3];

    testWidgets('are drawn at the text\'s size in the text\'s colour, a line of ink over a third of it', (tester) async {
      final washed = await draw(tester, DrawnIconView(AppIcons.tickBox));
      // 1em, at two pixels to the logical one.
      expect((washed.width, washed.height), (96, 96));
      // Inside the box, clear of the tick: the wash, a third of the ink.
      expect(alphaAt(washed, 16, 16.5), closeTo(255 * 0.33, 3));
      // On the box's own line: the ink whole.
      expect(alphaAt(washed, 12, 4.5), 255);
      // Outside it: nothing.
      expect(alphaAt(washed, 1.5, 1.5), 0);
      final plain = await draw(tester, DrawnIconView(AppIcons.tickBox, wash: false));
      expect(alphaAt(plain, 16, 16.5), 0);
      expect(alphaAt(plain, 12, 4.5), 255);
    });

    testWidgets('the kit\'s are drawn at the size and stroke asked, the stroke growing with the size', (tester) async {
      final thin = await draw(tester, const AppIcon(Lucide.square, size: 48, strokeWidth: 2));
      final thick = await draw(tester, const AppIcon(Lucide.square, size: 48, strokeWidth: 4));
      expect((thin.width, thin.height), (96, 96));
      // The square's edge is at 3 of 24: a stroke of 2 reaches 2 to 4, a stroke of 4 reaches 1 to 5.
      expect(alphaAt(thin, 1.5, 12), 0);
      expect(alphaAt(thick, 1.5, 12), 255);
      expect(alphaAt(thin, 3, 12), 255);
      // Washed whole, as the page washes the square.
      expect(alphaAt(thin, 12, 12), closeTo(255 * 0.33, 3));
      final hollow = await draw(tester, const AppIcon(Lucide.square, size: 48, wash: false));
      expect(alphaAt(hollow, 12, 12), 0);
    });

    testWidgets('take an icon theme\'s colour where one is set, and the text\'s where none is', (tester) async {
      Future<int> red(Widget icon) async {
        final pixels = await draw(tester, icon);
        return pixels.data[((4.5 * 4).floor() * pixels.width + 48) * 4];
      }

      expect(await red(DrawnIconView(AppIcons.tickBox)), 255);
      expect(await red(IconTheme(data: const IconThemeData(color: Color(0xFF00FF00)), child: DrawnIconView(AppIcons.tickBox, size: 48))), 0);
    });

    testWidgets('the house, the pin on a map and an icon in a line of words all draw', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 20),
            child: Column(
              children: [
                const HouseIcon(),
                const PlaceMark(color: Color(0xFFFF0000)),
                Text.rich(TextSpan(children: [DrawnIconView.span(AppIcons.pin, em: 20), const TextSpan(text: ' Pinned')])),
                const TipsShape(size: 60),
              ],
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(HouseIcon)), const Size(20, 20));
      expect(tester.getSize(find.byType(DrawnIconView)), const Size(20, 20));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('a drawing\'s paths', () {
    test('are parsed once for their string, their even-odd selves made once, and no more kept than the store holds', () {
      const d = 'M2 2 L20 2 L20 20 L2 20 Z M8 8 L14 8 L14 14 L8 14 Z';
      final plain = svgPath(d), holed = svgPath(d, evenOdd: true);
      expect(identical(svgPath(d), plain), isTrue);
      expect(identical(svgPath(d, evenOdd: true), holed), isTrue);
      expect(identical(plain, holed), isFalse);
      expect(plain.fillType, ui.PathFillType.nonZero);
      expect(holed.fillType, ui.PathFillType.evenOdd);
      // The hole: inside the inner square, the even-odd path is clear.
      expect(plain.contains(const Offset(11, 11)), isTrue);
      expect(holed.contains(const Offset(11, 11)), isFalse);
      expect(holed.contains(const Offset(4, 4)), isTrue);

      // A caller that writes a path out afresh for every place it draws: what is kept stops growing.
      for (var i = 0; i < 6000; i++) {
        svgPath('M$i 0 L${i + 1} 1');
      }
      expect(debugSvgPathsKept, lessThanOrEqualTo(2 * 4096));
      // A path dropped on the way is parsed again and is the same shape.
      expect(svgPath(d).getBounds(), plain.getBounds());
    });

    test('a painter says to paint again only when what it draws has changed', () {
      const a = DrawnIconPainter(strokes: ['M0 0 L1 1'], washed: ['M0 0 L1 1'], color: Color(0xFF112233), strokeWidth: 2);
      // The same icon built again: other lists, the same strings.
      final again = DrawnIconPainter(strokes: ['M0 0 L1 1'.toString()], washed: [...a.washed], color: const Color(0xFF112233), strokeWidth: 2);
      expect(again.shouldRepaint(a), isFalse);
      expect(const DrawnIconPainter(strokes: ['M0 0 L1 1'], washed: ['M0 0 L1 1'], color: Color(0xFF112234), strokeWidth: 2).shouldRepaint(a), isTrue);
      expect(const DrawnIconPainter(strokes: ['M0 0 L1 1'], washed: ['M0 0 L1 1'], color: Color(0xFF112233), strokeWidth: 2.1).shouldRepaint(a), isTrue);
      expect(const DrawnIconPainter(strokes: ['M0 0 L2 2'], washed: ['M0 0 L1 1'], color: Color(0xFF112233), strokeWidth: 2).shouldRepaint(a), isTrue);
      expect(const DrawnIconPainter(strokes: ['M0 0 L1 1'], washed: [], color: Color(0xFF112233), strokeWidth: 2).shouldRepaint(a), isTrue);
      expect(const DrawnIconPainter(strokes: ['M0 0 L1 1'], washed: ['M0 0 L1 1'], color: Color(0xFF112233), strokeWidth: 2, evenOdd: true).shouldRepaint(a), isTrue);
      expect(const DrawnIconPainter(strokes: ['M0 0 L1 1'], washed: ['M0 0 L1 1'], color: Color(0xFF112233), strokeWidth: 2, viewBox: 20).shouldRepaint(a), isTrue);
    });
  });

  group('the lid', () {
    test('lifts, hangs there a moment, and settles with a little bounce', () {
      expect(TipsShape.lidAt(0).move, Offset.zero);
      expect(TipsShape.lidAt(0.1).turn, 0);
      expect(TipsShape.lidAt(0.34).move, const Offset(-3, -14));
      expect(TipsShape.lidAt(0.5).turn, -16);
      expect(TipsShape.lidAt(0.74).move, const Offset(0, 2));
      expect(TipsShape.lidAt(0.9).move, Offset.zero);
      // On its way up, part of the way.
      final rising = TipsShape.lidAt(0.27);
      expect(rising.move.dy, inExclusiveRange(-14, 0));
      expect(rising.turn, inExclusiveRange(-16, 0));
    });

    testWidgets('stands still in its finished pose with reduced motion', (tester) async {
      await tester.pumpWidget(const MediaQuery(data: MediaQueryData(disableAnimations: true), child: Directionality(textDirection: ui.TextDirection.ltr, child: TipsShape())));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const MediaQuery(data: MediaQueryData(), child: Directionality(textDirection: ui.TextDirection.ltr, child: TipsShape())));
      expect(tester.binding.transientCallbackCount, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}

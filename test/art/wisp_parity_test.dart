import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/dock_smoke.dart';
import 'package:ghost_md/art/wisp_edge.dart';
import 'package:ghost_md/art/wisp_foot.dart';
import 'package:ghost_md/art/wisp_sides.dart';
import 'package:ghost_md/art/wisp_text.dart';
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/art/wisp_mask.dart';
import 'package:ghost_md/art/wisp_strips.dart';

import 'support/pictures.dart';

/// The shaders held to the web app's own filters, drawn by Chromium (tool/wisp_reference.mjs wrote
/// test/art/reference/web-*.png and the numbers each was drawn with, cases.json). Each case draws the same card
/// through the Dart port's numbers and the fragment shaders, and is compared with the web's picture on the dark paper.
///
/// A number here is a guard, not a judgement: the smoke is a texture, and two smokes can score alike and look
/// nothing alike (docs/DESIGN.md §55 has how that was learnt). So every case also writes
/// `test/art/shots/parity-<name>.png` - the web's picture, this one, and their difference four times brighter - and
/// those are what was looked at. To keep the numbers honest each test also draws the case wrong on purpose (the
/// noise twice as fine) and holds that it scores worse.
const paper = 0x0d0d0d;

/// The most each case's mean difference may be, of 255: two or three times what it measured when the pictures were
/// last looked at, which leaves room for another engine's blur and none for another cloud.
const limits = {
  'top': 0.6,
  'bare': 0.4,
  'foot': 0.35,
  'foot-moved': 0.35,
  'lane': 0.25,
  'lane-short': 1.1,
  'sides': 0.2,
  'sides-start': 0.2,
  'letter': 0.3,
  'letter-bent': 0.3,
};
const cardSize = Size(390, 420);

void main() {
  late Map<String, dynamic> cases;
  late ui.Image card;

  setUpAll(() {
    cases = (jsonDecode(File('test/art/reference/cases.json').readAsStringSync()) as Map<String, dynamic>)['cases'] as Map<String, dynamic>;
  });

  Future<void> ready(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1400, 1800);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await WispKit.load(seeds: [3, 5, 8]);
      card = await decodePng('test/art/reference/card.png');
    });
  }

  /// The card behind a window of [size] onto it at [from], drawn through [strips].
  Future<Pixels> draw(WidgetTester tester, List<WispStrip> strips, {Size size = cardSize, Offset from = Offset.zero}) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox.fromSize(
              size: size,
              child: WispStrips(
                strips: strips,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: cardSize.width,
                    maxWidth: cardSize.width,
                    minHeight: cardSize.height,
                    maxHeight: cardSize.height,
                    child: Transform.translate(offset: -from, child: RawImage(image: card, width: cardSize.width, height: cardSize.height, fit: BoxFit.fill)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return capture(tester, key);
  }

  /// Holds [mine] to the web's picture of [name], writes the two side by side, and answers how far apart they are;
  /// [wrong] is the case drawn wrong on purpose, which must be further off.
  Future<Apart> compare(WidgetTester tester, String name, Pixels mine, {Pixels? wrong, int ground = paper}) async {
    return (await tester.runAsync(() async {
      final web = await readPng('test/art/reference/web-$name.png');
      final a = web.on(ground), b = mine.on(ground);
      final score = apart(a, b);
      await writePng('test/art/shots/parity-$name.png', beside([a, b, difference(a, b)]));
      final off = wrong == null ? null : apart(a, wrong.on(ground));
      // ignore: avoid_print
      print('$name: $score${off == null ? '' : '   (drawn wrong: $off)'}');
      if (off != null) expect(off.mean, greaterThan(score.mean * 1.15), reason: '$name drawn wrong should be further from the web than drawn right');
      final limit = limits[name];
      if (limit != null) expect(score.mean, lessThan(limit), reason: '$name has moved away from the web\'s picture');
      return score;
    }))!;
  }

  WispDriftAt driftOf(Map<String, dynamic> c) {
    final f = (c['frequency'] as String).split(' ').map(double.parse).toList();
    return WispDriftAt(Offset(f[0], f[1]), Offset(double.parse(c['dx'] as String), double.parse(c['dy'] as String)));
  }

  for (final name in ['top', 'bare']) {
    testWidgets('the page\'s top band: $name', (tester) async {
      await ready(tester);
      final c = cases[name] as Map<String, dynamic>;
      final under = (c['under'] as num).toDouble();
      final fade = wispEdgeFade(height: cardSize.height, topFade: (c['topFade'] as num).toDouble());
      List<WispStrip> strips(WispDriftAt at) => [
            WispSmokeStrip(
              rect: Rect.fromLTRB(0, 0, cardSize.width, under + wispEdgeDrop + wispEdgeReach),
              smoke: wispTopSmoke(under: under, at: at, fade: fade),
              within: wispTopWithin(under),
            ),
          ];
      final at = driftOf(c);
      final mine = await draw(tester, strips(at));
      final wrong = await draw(tester, strips(WispDriftAt(at.frequency * 2, at.slide)));
      await compare(tester, name, mine, wrong: wrong);
    });
  }

  for (final name in ['foot', 'foot-moved']) {
    testWidgets('the page\'s foot: $name', (tester) async {
      await ready(tester);
      final c = cases[name] as Map<String, dynamic>;
      final fade = wispEdgeFade(height: cardSize.height, footFade: (c['footFade'] as num).toDouble());
      List<WispStrip> strips(WispDriftAt at) {
        final within = wispFootWithin(cardSize.height);
        return [WispSmokeStrip(rect: Rect.fromLTRB(0, within.top, cardSize.width, cardSize.height), smoke: wispFootSmoke(height: cardSize.height, at: at, fade: fade), within: within)];
      }

      final at = driftOf(c);
      final mine = await draw(tester, strips(at));
      final wrong = await draw(tester, strips(WispDriftAt(at.frequency * 2, at.slide)));
      await compare(tester, name, mine, wrong: wrong);
    });
  }

  // The boxed wisps. Each is also drawn with the throw the web app means rather than the one Chromium gives it
  // (wisp_box.dart `boxBend`), which is the "wrong" these are held against: the port draws what the phone draws.
  for (final name in ['lane', 'lane-short']) {
    testWidgets('a board lane\'s foot: $name', (tester) async {
      await ready(tester);
      final c = cases[name] as Map<String, dynamic>;
      final size = Size((c['width'] as num).toDouble(), (c['height'] as num).toDouble());
      expect(wispFootFade(size.height), closeTo((c['fade'] as num).toDouble(), 1e-9));
      List<WispStrip> strips(WispSmoke smoke) {
        final within = wispFootLaneWithin(size.height, size.width);
        return [WispSmokeStrip(rect: Rect.fromLTRB(0, within.top < 0 ? 0 : within.top, size.width, size.height), smoke: smoke, within: within)];
      }

      final smoke = wispFoot(size.height, size.width, ratio: 2)!;
      final mine = await draw(tester, strips(smoke), size: size);
      final meant = await draw(tester, strips(smoke.copyWith(bend: 28)), size: size);
      final fine = await draw(tester, strips(smoke.copyWith(frequency: smoke.frequency * 2)), size: size);
      await compare(tester, name, mine, wrong: fine);
      final web = (await tester.runAsync(() => readPng('test/art/reference/web-$name.png')))!.on(paper);
      final asMeant = apart(web, meant.on(paper));
      // ignore: avoid_print
      print('$name with the throw the web app means: $asMeant');
      expect(asMeant.mean, greaterThan(apart(web, mine.on(paper)).mean * 1.25));
    });
  }

  for (final name in ['sides', 'sides-start']) {
    testWidgets('the tab row\'s ends: $name', (tester) async {
      await ready(tester);
      final c = cases[name] as Map<String, dynamic>;
      final size = Size((c['width'] as num).toDouble(), (c['height'] as num).toDouble());
      final from = Offset(0, (c['cardY'] as num).toDouble());
      List<WispStrip> strips(WispSmoke smoke) => [WispSmokeStrip(rect: Offset.zero & size, smoke: smoke, within: wispSidesWithin(size.width, size.height))];
      final smoke = wispSides(size.width, size.height, c['start'] as bool, c['end'] as bool, ratio: 2)!;
      final mine = await draw(tester, strips(smoke), size: size, from: from);
      final meant = await draw(tester, strips(smoke.copyWith(bend: 14)), size: size, from: from);
      final fine = await draw(tester, strips(smoke.copyWith(frequency: smoke.frequency * 2)), size: size, from: from);
      await compare(tester, name, mine, wrong: fine);
      final web = (await tester.runAsync(() => readPng('test/art/reference/web-$name.png')))!.on(paper);
      final asMeant = apart(web, meant.on(paper));
      // ignore: avoid_print
      print('$name with the throw the web app means: $asMeant');
      expect(asMeant.mean, greaterThan(apart(web, mine.on(paper)).mean * 1.25));
    });
  }

  // A letter of WispText part way through setting, and at the start of its arrival with the blur taken off so the
  // bend alone is seen. The letter is a square of the card, as it is in the web's picture.
  for (final name in ['letter', 'letter-bent']) {
    testWidgets('a letter in its smoke: $name', (tester) async {
      await ready(tester);
      final c = cases[name] as Map<String, dynamic>;
      final box = Size((c['width'] as num).toDouble(), (c['height'] as num).toDouble());
      final seed = c['seed'] as int;
      final glyph = (await tester.runAsync(() async {
        final all = await pixelsOf(card);
        return imageOf(all.crop(((c['cardX'] as num) * 2).round(), ((c['cardY'] as num) * 2).round(), (box.width * 2).round(), (box.height * 2).round()));
      }))!;
      Future<Pixels> letter(Offset frequency) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: CustomPaint(
                size: Size(7 * box.width, 4 * box.height),
                painter: _Letter(
                  (canvas) {
                    canvas.translate(3 * box.width, 1.5 * box.height);
                    final kit = WispKit.maybe!;
                    paintWispLetter(
                      canvas,
                      kit: kit,
                      table: kit.tableNow(seed)!,
                      glyph: glyph,
                      glyphRect: Offset.zero & box,
                      box: box,
                      smoke: WispSmoke.flat(seed: seed, frequency: frequency, bend: (c['bend'] as num).toDouble(), blur: (c['blur'] as num).toDouble()),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        return capture(tester, key);
      }

      final mine = await letter(wispLetterFrequency);
      final wrong = await letter(wispLetterFrequency * 2);
      await compare(tester, name, mine, wrong: wrong);
    });
  }

  // The pictures the web app makes once and keeps: the mask's two bands and the dock's tile, worked out here in Dart
  // where the page lets the engine draw an SVG. Ink on white, since the ink's alpha is the whole of each.
  const white = 0xffffff;
  Pixels inkOf(List<int> pixels, int width, int height) => Pixels(width, height, pixels is Uint8List ? pixels : Uint8List.fromList(pixels));

  testWidgets('the mask\'s bands', (tester) async {
    await ready(tester);
    for (final foot in [false, true]) {
      final name = foot ? 'mask-foot' : 'mask-top';
      final mine = inkOf(wispMaskPixels(foot: foot), 1024, 512);
      // Wrong on purpose: the other band, which has the same noise under another ramp.
      final wrong = inkOf(wispMaskPixels(foot: !foot), 1024, 512);
      final score = await compare(tester, name, mine, wrong: wrong, ground: white);
      expect(score.mean, lessThan(1.5), reason: name);
    }
  });

  testWidgets('the dock\'s tile of smoke, its core and its ramp', (tester) async {
    await ready(tester);
    final tile = inkOf(dockSmokeTilePixels(), 512, 512);
    final score = await compare(tester, 'dock-tile', tile, ground: white);
    expect(score.mean, lessThan(1.5));

    for (final (name, shape) in [('dock-core', dockSmokeCore(240, 150)), ('dock-ramp', dockSmokeRamp(240, 150))]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: ClipRect(child: CustomPaint(size: const Size(240, 150), painter: _Letter((canvas) => paintDockPill(canvas, shape)))),
          ),
        ),
      );
      final pill = await compare(tester, name, await capture(tester, key), ground: white);
      expect(pill.mean, lessThan(2.5), reason: name);
    }
  });

  // The halo's backdrop bent, with no mask and no wash, as Chromium draws `backdrop-filter: url(#dockWisp)` over the
  // card on the dark paper.
  testWidgets('the dock\'s halo bending what is behind it', (tester) async {
    await ready(tester);
    final halo = (cases['dock-bend'] as Map<String, dynamic>)['halo'] as Map<String, dynamic>;
    final rect = Rect.fromLTWH((halo['x'] as num).toDouble(), (halo['y'] as num).toDouble(), (halo['width'] as num).toDouble(), (halo['height'] as num).toDouble());
    final mine = await draw(tester, [_Backdrop(rect, wispBaseFrequency)]);
    final wrong = await draw(tester, [_Backdrop(rect, wispBaseFrequency * 2)]);
    final score = await compare(tester, 'dock-bend', mine, wrong: wrong);
    expect(score.mean, lessThan(1.5));
  });
}

class _Backdrop extends WispStrip {
  const _Backdrop(this.rect, this.frequency);

  @override
  final Rect rect;
  final Offset frequency;

  @override
  double get reach => 24;

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    canvas.save();
    canvas.clipRect(at);
    paintDockBackdrop(canvas, at: at, halo: rect, view: view, viewRect: viewRect, ratio: ratio, bends: true, frequency: frequency);
    canvas.restore();
  }
}

class _Letter extends CustomPainter {
  _Letter(this.draw);
  final void Function(Canvas canvas) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas);

  @override
  bool shouldRepaint(_Letter old) => true;
}

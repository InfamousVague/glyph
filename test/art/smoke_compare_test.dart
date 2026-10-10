import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/dock_smoke.dart';
import 'package:ghost_md/art/wisp_edge.dart';
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/art/wisp_settings.dart';
import 'package:ghost_md/art/wisp_strips.dart';

import 'support/pictures.dart';

/// The smoke as it is drawn (one pass over the strip, its soft half made small: lib/art/wisp_smoke.dart
/// `paintWispSmoke`) beside the smoke it is held to (three passes at the screen's size, `paintWispSmokeExact`), over
/// a page of words at a phone's own ratio, at rest and scrolled, still and drifted.
///
/// The pictures are what is judged: `build/smoke-compare/<case>.png` has the old drawing, the new, and their
/// difference four times brighter, one above the next, and `<case>-near.png` a part of each three times its size.
/// The smoke was chosen by eye, and a number cannot tell a soft cloud from fine static (docs/DESIGN.md §55 of the
/// web app), so the numbers here are a guard on the pictures having been looked at, not the judgement: they hold
/// that the two drawings stay as near as they were when they were.
const _ratio = 2.625;
const _view = Size(390, 420);
const _under = 56.0;

Future<void> _fonts() async {
  String? family;
  final faces = <String, List<String>>{};
  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    final name = RegExp(r'^\s*- family:\s*(.+)$').firstMatch(line);
    final asset = RegExp(r'^\s*- asset:\s*(.+)$').firstMatch(line);
    if (name != null) family = name.group(1)!.trim();
    if (asset != null && family != null) faces.putIfAbsent(family, () => []).add(asset.group(1)!.trim());
  }
  for (final entry in faces.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      loader.addFont(File(file).readAsBytes().then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
  }
}

/// A page such as a note is: a name, sections, paragraphs, a list, a card with a border, a block of colour where a
/// picture would be, and small print.
Widget _page(Color ink, Color paper) {
  TextStyle face(double size, {FontWeight weight = FontWeight.w400, double alpha = 1}) =>
      TextStyle(
        fontFamily: 'Inter Variable',
        fontSize: size,
        height: 1.5,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        color: ink.withValues(alpha: alpha),
        decoration: TextDecoration.none,
      );
  const words = 'A note is plain Markdown: words with a few marks around them. Type a mark, or say its word while recording, and it is drawn. The marks stay on the page, a little dimmed.';
  Widget section(int n) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n == 0 ? 'How to format a note' : 'Again, part ${n + 1}', style: face(n == 0 ? 28 : 21, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(words, style: face(16)),
          const SizedBox(height: 10),
          for (final item in const ['Milk, and oat if they have it', 'Book the cabin for Saturday', 'Call Sam about the deposit'])
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $item', style: face(16))),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: ink.withValues(alpha: 0.28)), borderRadius: BorderRadius.circular(12), color: ink.withValues(alpha: 0.05)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekend trip', style: face(16, weight: FontWeight.w600)),
                  Text('The cabin key is under the third stone. Saturday the lake, Sunday the long walk if it is dry.', style: face(13, alpha: 0.7)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 54, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), gradient: const LinearGradient(colors: [Color(0xFF3C6E71), Color(0xFFD9A441), Color(0xFFB5523B)]))),
          const SizedBox(height: 6),
          Text('3 of 8 done · edited 4 minutes ago · #cabin', style: face(12, alpha: 0.6)),
          const SizedBox(height: 18),
        ],
      );
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var n = 0; n < 4; n++) section(n)]),
  );
}

/// The strips a page wears on a phone at this scroll and this place in its drift, as lib/art/wisp_edge.dart lays
/// them: the top band under a header [under] tall (none: the view fades over [safeTop] and 8px more), and the foot.
List<WispStrip> _strips({required double under, required WispDriftAt at, bool top = true, double safeTop = 36}) {
  final width = _view.width, height = _view.height;
  final drop = under > 0 ? wispEdgeDrop : 0.0;
  final topFade = !top || under > 0 ? 0.0 : safeTop + 8;
  final fade = wispEdgeFade(height: height, topFade: topFade, footFade: wispFootFadeSmoke);
  final within = wispFootWithin(height);
  return [
    if (top)
      ...wispSmokeStrips(
        rect: Rect.fromLTRB(0, 0, width, under + drop + wispEdgeReach > topFade ? under + drop + wispEdgeReach : topFade),
        smoke: wispTopSmoke(under: under, at: at, fade: fade),
        within: wispTopWithin(under),
      ),
    ...wispSmokeStrips(rect: Rect.fromLTRB(0, within.top, width, height), smoke: wispFootSmoke(height: height, at: at, fade: fade), within: within),
  ];
}

/// [pixels] three times their size, each one a square: for looking at a part closely.
Pixels _thrice(Pixels pixels) {
  const by = 3;
  final out = Uint8List(pixels.width * by * pixels.height * by * 4);
  for (var y = 0; y < pixels.height * by; y++) {
    for (var x = 0; x < pixels.width * by; x++) {
      final from = ((y ~/ by) * pixels.width + (x ~/ by)) * 4, to = (y * pixels.width * by + x) * 4;
      out.setRange(to, to + 4, pixels.data, from);
    }
  }
  return Pixels(pixels.width * by, pixels.height * by, out);
}

/// [pictures] one above the next, with a gap between.
Pixels _stacked(List<Pixels> pictures, {int gap = 6}) {
  final width = pictures.map((p) => p.width).reduce((a, b) => a > b ? a : b);
  final height = pictures.fold<int>(0, (sum, p) => sum + p.height) + gap * (pictures.length - 1);
  final out = Uint8List(width * height * 4);
  for (var i = 0; i < out.length; i += 4) {
    out[i] = 255;
    out[i + 2] = 255;
    out[i + 3] = 255;
  }
  var y = 0;
  for (final p in pictures) {
    for (var row = 0; row < p.height; row++) {
      out.setRange(((y + row) * width) * 4, ((y + row) * width + p.width) * 4, p.data, row * p.width * 4);
    }
    y += p.height + gap;
  }
  return Pixels(width, height, out);
}

const dark = (Color(0xFFE8E6E3), Color(0xFF0D0D0D)), light = (Color(0xFF1B1B1A), Color(0xFFF6F4EF));

void main() {
  setUpAll(_fonts);

  Future<Pixels> draw(WidgetTester tester, List<WispStrip> strips, double scroll, Color ink, Color paper, {required bool exact}) async {
    debugWispQuick = !exact;
    addTearDown(() => debugWispQuick = null);
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: paper,
              child: SizedBox.fromSize(
                size: _view,
                child: WispStrips(
                  // A new list each time, so the strips are drawn again for the other drawing.
                  strips: [...strips],
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: _view.width,
                      maxWidth: _view.width,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: Transform.translate(offset: Offset(0, _under - scroll), child: _page(ink, paper)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final strip = tester.renderObject<RenderWispStrips>(find.byType(WispStrips));
    expect(strip.debugPainted, hasLength(strips.length), reason: 'the kit was not ready, and no smoke was drawn');
    final pixels = await capture(tester, key, ratio: _ratio);
    debugWispQuick = null;
    return pixels;
  }

  final cases = <String, ({double scroll, WispDriftAt at, double under, (Color, Color) look})>{
    'rest': (scroll: 0, at: WispDriftAt.rest, under: _under, look: dark),
    'scrolled': (scroll: 37.4, at: WispDriftAt.rest, under: _under, look: dark),
    'drift-a': (scroll: 211.7, at: WispDriftAt.at(1800), under: _under, look: dark),
    'drift-b': (scroll: 96.2, at: WispDriftAt.at(5200), under: _under, look: dark),
    'light': (scroll: 142, at: WispDriftAt.at(3100), under: _under, look: light),
    'no-header': (scroll: 60.5, at: WispDriftAt.at(900), under: 0, look: dark),
  };

  // The dock's halo on a phone, where it bends what scrolls behind it: the three layers the stylesheet composes
  // beside the one pass (lib/art/dock_smoke.dart), at rest and with the tile slid by the page's drift.
  for (final (name, slide, frequency) in [('dock', Offset.zero, wispBaseFrequency), ('dock-slid', const Offset(3.2, 14.6), const Offset(0.0203, 0.0667))]) {
    testWidgets('the dock\'s halo, one pass beside its layers: $name', (tester) async {
      tester.view.devicePixelRatio = _ratio;
      tester.view.physicalSize = _view * _ratio;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await WispKit.load(seeds: [3]);
        await dockSmokeTile();
      });
      // A dock of three buttons at the foot of the page, as the home page stands it.
      const dock = Rect.fromLTWH(155, 300, 80, 64);
      List<WispStrip> strips() => [DockHaloStrip(rect: dock.inflate(dockSmokeReach), ground: dark.$2, bends: true, frequency: frequency, slide: slide, tile: dockSmokeTileNow())];
      final was = await draw(tester, strips(), 118.3, dark.$1, dark.$2, exact: true);
      final now = await draw(tester, strips(), 118.3, dark.$1, dark.$2, exact: false);
      final plain = await draw(tester, const [], 118.3, dark.$1, dark.$2, exact: false);
      await tester.runAsync(() async {
        final box = dock.inflate(dockSmokeReach + 6);
        Pixels cut(Pixels from) => from.crop((box.left * _ratio).round(), (box.top * _ratio).round(), (box.width * _ratio).round(), ((_view.height - box.top) * _ratio).round());
        final a = cut(was), b = cut(now);
        await writePng('build/smoke-compare/$name.png', beside([a, b, difference(a, b)]));
        final score = apart(a, b), smoke = apart(a, cut(plain));
        // ignore: avoid_print
        print('$name: the two drawings $score   (the halo itself, against none: $smoke)');
        expect(smoke.mean, greaterThan(1), reason: 'no halo was drawn: nothing was compared');
        expect(score.mean, lessThan(smoke.mean * 0.2), reason: 'the one-pass halo has moved away from the layered one');
      });
    });
  }

  for (final entry in cases.entries) {
    testWidgets('one pass beside three: ${entry.key}', (tester) async {
      tester.view.devicePixelRatio = _ratio;
      tester.view.physicalSize = _view * _ratio;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => WispKit.load(seeds: [3]));
      final c = entry.value;
      // Laid out for each drawing: the quick way cuts a strip to what the smoke touches.
      List<WispStrip> strips(bool exact) {
        debugWispQuick = !exact;
        final laid = _strips(under: c.under, at: c.at);
        debugWispQuick = null;
        return laid;
      }

      final was = await draw(tester, strips(true), c.scroll, c.look.$1, c.look.$2, exact: true);
      final now = await draw(tester, strips(false), c.scroll, c.look.$1, c.look.$2, exact: false);
      final plain = await draw(tester, const [], c.scroll, c.look.$1, c.look.$2, exact: false);
      await tester.runAsync(() async {
        final wide = was.width;
        // The top band and the foot's, each a strip of the picture.
        final topRows = ((c.under + wispEdgeDrop + wispEdgeBand + wispEdgeSoft * 4) * _ratio).round();
        final footRows = ((wispEdgeFootLift + wispEdgeFootBand + wispEdgeFootSoft * 4) * _ratio).round();
        for (final (part, top, rows) in [('top', 0, topRows), ('foot', was.height - footRows, footRows)]) {
          final a = was.crop(0, top, wide, rows), b = now.crop(0, top, wide, rows);
          await writePng('build/smoke-compare/${entry.key}-$part.png', _stacked([a, b, difference(a, b)]));
          // A part of it close: a third of the width, from the left margin, where the band is strong.
          final nearTop = part == 'top' ? ((c.under) * _ratio).round() : rows ~/ 3;
          final nearRows = (40 * _ratio).round(), nearWide = (130 * _ratio).round();
          final left = (16 * _ratio).round();
          final na = a.crop(left, nearTop, nearWide, nearRows), nb = b.crop(left, nearTop, nearWide, nearRows);
          await writePng('build/smoke-compare/${entry.key}-$part-near.png', _stacked([_thrice(na), _thrice(nb)]));
          final score = apart(a, b);
          // How much smoke there is at all: the old drawing against the page with none.
          final smoke = apart(a, plain.crop(0, top, wide, rows));
          // ignore: avoid_print
          print('${entry.key} $part: the two drawings $score   (the smoke itself, against none: $smoke)');
          expect(smoke.mean, greaterThan(1), reason: 'no smoke was drawn in ${entry.key} $part: nothing was compared');
          expect(score.mean, lessThan(smoke.mean * 0.2), reason: '${entry.key} $part: the one-pass smoke has moved away from the three-pass one');
        }
      });
    });
  }
}

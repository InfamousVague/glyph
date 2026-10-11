import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/wisp_edge.dart';
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/art/wisp_settings.dart';
import 'package:ghost_md/art/wisp_smoke.dart';
import 'package:ghost_md/art/wisp_strips.dart';

import 'support/pictures.dart';

/// The program a strip is read off the backdrop with (shaders/wisp_back.frag, measuring only), drawn here as an
/// ordinary paint over a picture of a screen, since this engine cannot filter a backdrop with a program: that it
/// bends the view where the smoke drawn through pictures bends it, the view standing anywhere on the screen.
///
/// `build/smoke-compare/back/<case>.png` has the smoke as drawn, the program's, and the page with no smoke.
const _ratio = 2.0;
const _screen = Size(400, 300);
const _viewAt = Offset(24, 40);
const _view = Size(320, 240);
const _paper = Color(0xFF0D0D0D);

class _Marks extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = const Color(0xFFE8E6E3);
    for (var y = 6.0; y < size.height; y += 14) {
      for (var x = 8.0; x < size.width - 20; x += 46) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 34, 5), const Radius.circular(2)), ink);
      }
    }
    canvas.drawRect(Rect.fromLTWH(40, 30, 90, 40), Paint()..color = const Color(0xFF3C6E71));
    canvas.drawRect(Rect.fromLTWH(180, size.height - 60, 100, 44), Paint()..color = const Color(0xFFB5523B));
  }

  @override
  bool shouldRepaint(_Marks old) => false;
}

void main() {
  testWidgets('the backdrop program bends a strip as the pictures do, the view standing off the screen\'s corner', (tester) async {
    tester.view.devicePixelRatio = _ratio;
    tester.view.physicalSize = _screen * _ratio;
    addTearDown(tester.view.reset);
    debugWispQuick = true;
    addTearDown(() => debugWispQuick = null);
    final kit = (await tester.runAsync(() => WispKit.load(seeds: [3])))!;

    const under = 30.0;
    final at = WispDriftAt.at(1800);
    final fade = wispEdgeFade(height: _view.height, footFade: wispFootFadeSmoke);
    final within = wispFootWithin(_view.height);
    final strips = <WispStrip>[
      ...wispSmokeStrips(rect: Rect.fromLTRB(0, 0, _view.width, under + wispEdgeDrop + wispEdgeReach), smoke: wispTopSmoke(under: under, at: at, fade: fade), within: wispTopWithin(under), paper: _paper),
      ...wispSmokeStrips(rect: Rect.fromLTRB(0, within.top, _view.width, _view.height), smoke: wispFootSmoke(height: _view.height, at: at, fade: fade), within: within, paper: _paper),
    ];

    final key = GlobalKey();
    Future<Pixels> screen(bool smoked) async {
      final page = ClipRect(child: CustomPaint(painter: _Marks(), size: _view));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: _paper,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: _viewAt.dx, top: _viewAt.dy),
                  child: SizedBox.fromSize(size: _view, child: smoked ? WispStrips(strips: [...strips], child: page) : page),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return capture(tester, key, ratio: _ratio);
    }

    final smoked = await screen(true), bare = await screen(false);
    final backdrop = (await tester.runAsync(() => imageOf(bare)))!;

    // The program over each strip, the screen's own pixels under it.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(backdrop, Offset.zero, Paint());
    final parts = <Rect>[];
    for (final strip in strips.cast<WispSmokeStrip>()) {
      final shader = wispBack(kit: kit, at: strip.rect, smoke: strip.smoke, within: strip.within, viewAt: _viewAt, ratio: _ratio, paper: _paper)!;
      // What the engine sets for a filter: the backdrop and its size.
      shader
        ..setFloat(0, backdrop.width.toDouble())
        ..setFloat(1, backdrop.height.toDouble())
        ..setImageSampler(0, backdrop);
      final part = Rect.fromLTRB(
        ((strip.rect.left + _viewAt.dx) * _ratio).floorToDouble(),
        ((strip.rect.top + _viewAt.dy) * _ratio).floorToDouble(),
        ((strip.rect.right + _viewAt.dx) * _ratio).ceilToDouble(),
        ((strip.rect.bottom + _viewAt.dy) * _ratio).ceilToDouble(),
      );
      parts.add(part);
      canvas.drawRect(part, Paint()..shader = shader..blendMode = BlendMode.src);
    }
    final picture = recorder.endRecording();
    final read = (await tester.runAsync(() async => pixelsOf(await picture.toImage(backdrop.width, backdrop.height))))!;

    await tester.runAsync(() => writePng('build/smoke-compare/back/strips.png', beside([smoked, read, bare])));

    for (final part in parts) {
      Pixels cut(Pixels from) => from.crop(part.left.round(), part.top.round(), part.width.round(), part.height.round());
      final program = apart(cut(read), cut(smoked)), none = apart(cut(bare), cut(smoked));
      // ignore: avoid_print
      print('strip $part: the program is $program from the smoke; no smoke at all is $none');
      // The soft half is not in the program, so it is not the smoke; it is far nearer it than a page left alone.
      expect(program.mean, lessThan(none.mean * 0.6));
    }
  });

  testWidgets('the program a view\'s layers go through bends both strips as the pictures do, and keeps clear clear', (tester) async {
    tester.view.devicePixelRatio = _ratio;
    tester.view.physicalSize = _screen * _ratio;
    addTearDown(tester.view.reset);
    debugWispQuick = true;
    addTearDown(() => debugWispQuick = null);
    final kit = (await tester.runAsync(() => WispKit.load(seeds: [3])))!;

    const under = 30.0;
    final at = WispDriftAt.at(1800);
    final fade = wispEdgeFade(height: _view.height, footFade: wispFootFadeSmoke);
    final within = wispFootWithin(_view.height);
    final strips = <WispStrip>[
      ...wispSmokeStrips(rect: Rect.fromLTRB(0, 0, _view.width, under + wispEdgeDrop + wispEdgeReach), smoke: wispTopSmoke(under: under, at: at, fade: fade), within: wispTopWithin(under)),
      ...wispSmokeStrips(rect: Rect.fromLTRB(0, within.top, _view.width, _view.height), smoke: wispFootSmoke(height: _view.height, at: at, fade: fade), within: within),
    ];

    // The view alone, on nothing: what the filter is handed, and what the smoke is laid on.
    final key = GlobalKey();
    Future<Pixels> view(bool smoked) async {
      final page = ClipRect(child: CustomPaint(painter: _Marks(), size: _view));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: key, child: SizedBox.fromSize(size: _view, child: smoked ? WispStrips(strips: [...strips], child: page) : page)),
          ),
        ),
      );
      await tester.pump();
      return capture(tester, key, ratio: _ratio);
    }

    final smoked = await view(true), bare = await view(false);
    // The engine's pictures have their colour multiplied by their alpha, and these pixels have not.
    final multiplied = Uint8List.fromList(bare.data);
    for (var i = 0; i < multiplied.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        multiplied[i + c] = (multiplied[i + c] * multiplied[i + 3] / 255).round();
      }
    }
    final source = (await tester.runAsync(() => imageOf(Pixels(bare.width, bare.height, multiplied))))!;
    final shader = wispThrough(
      kit: kit,
      corner: Offset.zero,
      ratio: _ratio,
      smokes: [for (final strip in strips.cast<WispSmokeStrip>()) (at: strip.rect, smoke: strip.smoke, within: strip.within)],
    )!;
    shader
      ..setFloat(0, source.width.toDouble())
      ..setFloat(1, source.height.toDouble())
      ..setImageSampler(0, source);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Offset.zero & Size(source.width.toDouble(), source.height.toDouble()), Paint()..shader = shader..blendMode = BlendMode.src);
    final picture = recorder.endRecording();
    final read = (await tester.runAsync(() async => pixelsOf(await picture.toImage(source.width, source.height))))!;

    // As the eye has them, on the page's paper: a clear pixel's colour is nothing to compare.
    const ground = 0x0D0D0D;
    final smokedOn = smoked.on(ground), readOn = read.on(ground), bareOn = bare.on(ground);
    await tester.runAsync(() => writePng('build/smoke-compare/back/through.png', beside([smokedOn, readOn, bareOn])));

    final program = apart(readOn, smokedOn), none = apart(bareOn, smokedOn);
    // ignore: avoid_print
    print('the view: the program is $program from the smoke; no smoke at all is $none');
    expect(program.mean, lessThan(none.mean * 0.6));
    // Between the strips the view is passed as it came.
    final mid = (_view.height * _ratio / 2).round();
    expect(apart(readOn.crop(0, mid - 20, read.width, 40), bareOn.crop(0, mid - 20, bare.width, 40)).worst, lessThanOrEqualTo(1));
  });
}

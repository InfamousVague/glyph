// The effects as a page that moves draws them, beside the same page drawn once.
//
// A letter in an effect drawn by itself is a layer and a blur or two (lib/editor/marks/text_effects.dart). While
// frames follow one another the same letters are laid down from what is kept of them: a haunting's blur and a
// shimmer's glow from pictures kept (lib/art/wisp_kept.dart). The sheet every bent letter was laid from went with the
// smoke (2026-10-24): a heated letter is its own layer on every frame, and a spoiler's is a blur. This draws the marks' note with its clock held, once (frames a quarter
// of a second apart: each letter by itself) and then on frames sixteen milliseconds apart, and holds the second to
// the first.
//
// The pictures are what is judged: build/smoke-compare/effects-<name>.png has the page drawn once, the page that
// moves, and their difference four times brighter, and was looked at. The number is a guard on that.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/wisp_kept.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/state/state.dart' show Extension;

import '../../support/render.dart';
import 'support.dart';

Future<({int width, int height, Uint8List data})> _picture(WidgetTester tester) async {
  final boundary = tester.allRenderObjects.whereType<RenderRepaintBoundary>().first;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return (width: image.width, height: image.height, data: data!.buffer.asUint8List());
  }))!;
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(() {
    debugWispQuick = null;
    WispKept.clear();
  });

  // Each as it stands, and the dark one again scrolled to between two of the screen's pixels (37.3 logical pixels
  // is 74.6 of the picture's): a picture laid between pixels is read between its own and comes out soft, and a
  // page at rest after a fling stands wherever the fling left it.
  for (final (name, scrolled) in const <(String, double)>[('marks-dark-at-0', 0), ('marks-at-0_7', 0), ('marks-at-1_9', 0), ('marks-dark-at-0', 37.3)]) {
    testWidgets('$name${scrolled > 0 ? ', scrolled $scrolled' : ''}: a page that moves is the page drawn once', (tester) async {
      final fixture = Measured.read('marks', name);
      MarkClock.hold = (fixture.json['at'] as num).toDouble();
      addTearDown(() => MarkClock.hold = null);
      debugWispQuick = true;
      await pumpMeasured(tester, fixture, formats: marks, more: <Extension>[markExtensions(marks)], shaders: true);
      if (scrolled > 0) {
        // A window shorter than the note, so it scrolls.
        tester.view.physicalSize = Size(tester.view.physicalSize.width, 500);
        await tester.pump(const Duration(milliseconds: 250));
        final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
        expect(position.maxScrollExtent, greaterThan(scrolled));
        position.jumpTo(scrolled);
        await tester.pump(const Duration(milliseconds: 250));
        expect(position.pixels, scrolled);
      }

      // Drawn once: frames far apart, so nothing is kept and each letter is its own layers.
      await tester.pump(const Duration(milliseconds: 250));
      WispKept.debugLaid = 0;
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(WispKept.debugLaid, 0);
      final once = await _picture(tester);

      // And moving: the marks' own clock has each line with a moving letter painted on every frame.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(WispKept.debugLaid, greaterThan(0), reason: 'no kept picture was laid: nothing was compared');
      final moving = await _picture(tester);

      expect((moving.width, moving.height), (once.width, once.height));
      var total = 0, worst = 0, differing = 0;
      final shown = Uint8List(once.width * (once.height * 3 + 16) * 4);
      for (var i = 0; i < shown.length; i += 4) {
        shown[i] = 255;
        shown[i + 2] = 255;
        shown[i + 3] = 255;
      }
      final row = once.width * 4, below = (once.height + 8) * row, under = 2 * (once.height + 8) * row;
      for (var i = 0; i < once.data.length; i += 4) {
        var most = 0;
        for (var c = 0; c < 3; c++) {
          final d = (once.data[i + c] - moving.data[i + c]).abs();
          total += d;
          if (d > most) most = d;
          shown[i + c] = once.data[i + c];
          shown[below + i + c] = moving.data[i + c];
          shown[under + i + c] = d * 4 > 255 ? 255 : d * 4;
        }
        shown[i + 3] = 255;
        shown[below + i + 3] = 255;
        shown[under + i + 3] = 255;
        if (most > 0) differing += 1;
        if (most > worst) worst = most;
      }
      await tester.runAsync(() async {
        final buffer = await ui.ImmutableBuffer.fromUint8List(shown);
        final descriptor = ui.ImageDescriptor.raw(buffer, width: once.width, height: once.height * 3 + 16, pixelFormat: ui.PixelFormat.rgba8888);
        final image = (await (await descriptor.instantiateCodec()).getNextFrame()).image;
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('build/smoke-compare/effects-$name${scrolled > 0 ? '-scrolled' : ''}.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
      // How sharp each picture is: the squares of the steps from one pixel to the next along every row. A letter
      // laid between the screen's pixels is read between its own, its edges spread over two pixels where they were
      // one, and this falls: over the whole of these pages, to 0.971 to 0.980 of the page drawn once when the
      // effects' letters were laid that way on purpose, where it is 0.993 to 0.996 as they are laid. (A plain sum
      // of the steps does not move at all, since a spread edge climbs as far.)
      double sharpness(Uint8List data) {
        var sum = 0.0;
        for (var i = 0; i + 4 < data.length; i += 4) {
          final step = (data[i + 4] - data[i]).toDouble();
          sum += step * step;
        }
        return sum;
      }

      final sharp = sharpness(moving.data) / sharpness(once.data);
      final mean = total / (once.data.length / 4 * 3);
      // ignore: avoid_print
      print('$name${scrolled > 0 ? ' scrolled $scrolled' : ''}: the page that moves against the page drawn once: mean ${mean.toStringAsFixed(3)} of 255, $differing pixels differ, worst $worst, as sharp by ${sharp.toStringAsFixed(4)}; laid ${WispKept.debugLaid} kept');
      expect(sharp, greaterThan(0.985), reason: 'the page that moves is softer than the page drawn once: something is laid between the screen\'s pixels');
      expect(mean, lessThan(0.25), reason: 'the letters laid down from what is kept have moved away from the letters drawn by themselves');
      // As a picture's test ends (test/support/render.dart `shot`): the shadows' switch back, and the page taken down.
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}

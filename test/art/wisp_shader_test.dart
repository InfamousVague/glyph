import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/turbulence.dart';
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/art/wisp_smoke.dart';

/// The fragment shader's noise held to the Dart port of `feTurbulence` (which test/art/turbulence_test.dart holds to
/// Chromium's own pixels): a picture whose colour says where each pixel came from is bent by the shader, and every
/// pixel must have come from where the specification's noise would throw it.
Future<ui.Image> _image(Uint8List pixels, int width, int height) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// 256 by 256, red the column and green the row.
Future<ui.Image> _whereFrom() {
  final pixels = Uint8List(256 * 256 * 4);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      final at = (y * 256 + x) * 4;
      pixels[at] = x;
      pixels[at + 1] = y;
      pixels[at + 3] = 255;
    }
  }
  return _image(pixels, 256, 256);
}

void main() {
  testWidgets('the shader throws each pixel where feTurbulence says', (tester) async {
    await tester.runAsync(() async {
      for (final (seed, frequency) in [(3, const Offset(0.018, 0.06)), (5, const Offset(0.07, 0.035)), (8, const Offset(0.018, 0.06))]) {
        final kit = await WispKit.load(seeds: [seed]);
        final source = await _whereFrom();
        const bend = 120.0;
        const bentRect = Rect.fromLTWH(64, 64, 128, 128);
        final smoke = WispSmoke.flat(seed: seed, frequency: frequency, bend: bend, blur: 0);
        final bent = wispBent(kit: kit, table: kit.tableNow(seed)!, source: source, sourceRect: const Rect.fromLTWH(0, 0, 256, 256), bentRect: bentRect, ratio: 1, smoke: smoke);
        final data = (await bent.toByteData())!;
        final noise = Turbulence(seed);
        var exact = 0, near = 0, total = 0;
        for (var py = 0; py < 128; py++) {
          for (var px = 0; px < 128; px++) {
            final x = bentRect.left + px + 0.5, y = bentRect.top + py + 0.5;
            double n(int channel) => noise.sample(channel, x + 0.5, y + 0.5, baseFrequencyX: frequency.dx, baseFrequencyY: frequency.dy, octaves: 2);
            final fromX = (x + bend * (n(0) - 0.5)).floor(), fromY = (y + bend * (n(1) - 0.5)).floor();
            final gotX = data.getUint8((py * 128 + px) * 4), gotY = data.getUint8((py * 128 + px) * 4 + 1);
            total++;
            if (gotX == fromX && gotY == fromY) exact++;
            if ((gotX - fromX).abs() <= 1 && (gotY - fromY).abs() <= 1) near++;
          }
        }
        // A pixel thrown to the very edge of another may land either side of it; none lands further off than that.
        expect(near, total, reason: 'seed $seed');
        expect(exact / total, greaterThan(0.97), reason: 'seed $seed');
        source.dispose();
        bent.dispose();
      }
    });
  });
}

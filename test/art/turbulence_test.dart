import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/turbulence.dart';

import 'support/pictures.dart';

/// `feTurbulence` in Dart held to Chromium's own (test/art/reference/web-turbulence*.png, which
/// tool/wisp_reference.mjs drew at two device pixels to the logical one with the noise made opaque): the same seed
/// gives the same cloud, pixel for pixel, plain and stitched. Every wisp's shader reads its noise from a table this
/// makes, and test/art/wisp_shader_test.dart holds the shader to this in turn.
void main() {
  late Map<String, dynamic> cases;
  setUpAll(() {
    cases = (jsonDecode(File('test/art/reference/cases.json').readAsStringSync()) as Map<String, dynamic>)['cases'] as Map<String, dynamic>;
  });

  /// The mean difference between Chromium's picture of [name] and the port, of 255, the port asked [shift] logical
  /// pixels from each pixel's middle.
  Future<double> off(WidgetTester tester, String name, {double shift = 0.5, int? seed}) async {
    final c = cases[name] as Map<String, dynamic>;
    final web = (await tester.runAsync(() => readPng('test/art/reference/web-$name.png')))!;
    final frequency = (c['frequency'] as String).split(' ').map(double.parse).toList();
    final noise = Turbulence(seed ?? c['seed'] as int);
    final width = (c['width'] as num).toDouble(), height = (c['height'] as num).toDouble();
    final tile = c['stitch'] == true ? TurbulenceTile(width, height) : null;
    var total = 0.0, count = 0;
    for (var py = 0; py < web.height; py += 3) {
      for (var px = 0; px < web.width; px += 3) {
        for (var channel = 0; channel < 3; channel++) {
          final value = noise.sample(channel, (px + 0.5) / 2 + shift, (py + 0.5) / 2 + shift, baseFrequencyX: frequency.first, baseFrequencyY: frequency.last, octaves: c['octaves'] as int, tile: tile);
          total += ((value * 255).round() - web.data[(py * web.width + px) * 4 + channel]).abs();
          count++;
        }
      }
    }
    return total / count;
  }

  for (final name in ['turbulence', 'turbulence-sides', 'turbulence-stitched']) {
    testWidgets('is Chromium\'s noise, pixel for pixel: $name', (tester) async {
      // Within the rounding of a colour held in eight bits behind an alpha.
      expect(await off(tester, name), lessThan(0.75));
      // So that the number can fail: the wrong seed is another cloud, and the pixel's own middle is half a pixel off.
      expect(await off(tester, name, seed: 4), greaterThan(20));
      expect(await off(tester, name, shift: 0), greaterThan(2));
    });
  }

  group('the generator', () {
    test('clamps the seed as the specification does', () {
      expect(Turbulence(0).seed, 1);
      expect(Turbulence(3.9).seed, 3);
      expect(Turbulence(-5).seed, 6);
    });

    test('gives every lattice point a unit gradient, and a shuffle of all 256', () {
      final noise = Turbulence(3);
      expect(noise.lattice.sublist(0, 256).toSet().length, 256);
      for (var i = 0; i < 4 * 256; i++) {
        final x = noise.gradient[i * 2], y = noise.gradient[i * 2 + 1];
        expect(x * x + y * y, closeTo(1, 1e-9));
      }
      // And a different seed is a different shuffle.
      expect(Turbulence(5).lattice.sublist(0, 256), isNot(noise.lattice.sublist(0, 256)));
    });

    test('is smooth: one pixel on is a little different, never a jump', () {
      final noise = Turbulence(3);
      double at(double x) => noise.sample(0, x, 20, baseFrequencyX: 0.018, baseFrequencyY: 0.06, octaves: 2);
      for (var x = 0.0; x < 200; x += 1) {
        expect((at(x + 1) - at(x)).abs(), lessThan(0.03));
      }
    });

    test('meets itself across a stitched tile', () {
      final noise = Turbulence(7);
      const tile = TurbulenceTile(256, 256);
      double at(double x, double y) => noise.sample(0, x, y, baseFrequencyX: 0.035, baseFrequencyY: 0.035, octaves: 3, tile: tile);
      for (var v = 3.5; v < 256; v += 17) {
        expect(at(0, v), closeTo(at(256, v), 1e-9));
        expect(at(v, 0), closeTo(at(v, 256), 1e-9));
      }
      // Unstitched, the two edges are two places in the cloud.
      double plain(double x) => noise.sample(0, x, 40, baseFrequencyX: 0.035, baseFrequencyY: 0.035, octaves: 3);
      expect((plain(0) - plain(256)).abs(), greaterThan(0.01));
    });
  });

  group('the table a shader reads', () {
    test('holds each lattice point\'s gradient for red and for green, to twelve bits', () {
      final noise = Turbulence(3);
      final table = wispNoiseTable(noise);
      expect(table.length, wispNoiseTableWidth * wispNoiseTableHeight * 4);
      for (final (channel, bx, by) in [(0, 0, 0), (1, 255, 255), (0, 17, 200), (1, 99, 3)]) {
        final at = (by * wispNoiseTableWidth + channel * 256 + bx) * 4;
        final x = (table[at] * 16 + (table[at + 1] >> 4)) / 4095 * 2 - 1;
        final y = (((table[at + 1] & 0xf) << 8) + table[at + 2]) / 4095 * 2 - 1;
        final g = noise.gradientAt(channel, bx, by);
        expect(x, closeTo(noise.gradient[g], 1 / 4095));
        expect(y, closeTo(noise.gradient[g + 1], 1 / 4095));
        // Opaque, so nothing multiplies the colour on its way to the sampler.
        expect(table[at + 3], 255);
      }
    });
  });
}

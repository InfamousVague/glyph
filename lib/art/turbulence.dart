import 'dart:math' as math;
import 'dart:typed_data';

/// `feTurbulence`, as the SVG filter specification writes it out and as Chromium's Skia draws it: Perlin's gradient
/// noise over a lattice of 256 points, shuffled and given its gradients by a Park and Miller generator from the
/// filter's `seed`. Every smoke in the web app is this noise (art/WispEdgeFilter.tsx, art/WispText.tsx,
/// art/wispFoot.ts, art/wispSides.ts, art/wispMask.ts, art/dockSmoke.ts), so the port carries the algorithm itself and
/// not a noise that looks like it: the same seed gives the same cloud, lattice point for lattice point.
///
/// Pure Dart, for what is left of it here since the smoke gave way to a blur (2026-10-24): the table the bend reads
/// ([wispNoiseTable], shaders/wisp_bend.frag) for the heat on words and the scene's haze, the frost's grain and the
/// one point a voice's ripple carries a letter by (lib/editor/marks/text_effects.dart, lib/editor/ai/wisp_filters.dart),
/// and the tests that hold the shader to this and this to the browser.
///
/// What differs from the page: nothing in the numbers. Chromium works the noise out in whole device pixels (the
/// point is `(x + 1, y + 1)` in the screen's own pixels, the frequency divided by the scale), which puts its cloud
/// half a device pixel from where the specification's would be; [sample] takes any point and the callers hand it
/// logical pixels.
class Turbulence {
  Turbulence(num seed) : seed = _setupSeed(seed.truncate()) {
    _init();
  }

  /// The seed after the specification's own clamp: 1 for anything under 1.
  final int seed;

  static const int _bSize = 0x100;
  static const int _bMask = 0xff;
  static const int _perlinN = 0x1000;
  static const int _randM = 2147483647;
  static const int _randA = 16807;
  static const int _randQ = 127773;
  static const int _randR = 2836;

  /// The shuffled lattice, twice over and two more, as the reference keeps it so `lattice[i + by]` needs no wrap.
  final Uint8List lattice = Uint8List(_bSize + _bSize + 2);

  /// The unit gradients: `gradient[(channel * 256 + index) * 2 + axis]`, channels red, green, blue, alpha.
  final Float64List gradient = Float64List(4 * _bSize * 2);

  static int _setupSeed(int seed) {
    if (seed <= 0) seed = -seed.remainder(_randM - 1) + 1;
    if (seed > _randM - 1) seed = _randM - 1;
    return seed;
  }

  static int _random(int seed) {
    var result = _randA * (seed % _randQ) - _randR * (seed ~/ _randQ);
    if (result <= 0) result += _randM;
    return result;
  }

  void _init() {
    var s = seed;
    final order = Uint8List(_bSize);
    for (var k = 0; k < 4; k++) {
      for (var i = 0; i < _bSize; i++) {
        order[i] = i;
        s = _random(s);
        final gx = ((s % (_bSize + _bSize)) - _bSize) / _bSize;
        s = _random(s);
        final gy = ((s % (_bSize + _bSize)) - _bSize) / _bSize;
        final length = math.sqrt(gx * gx + gy * gy);
        gradient[(k * _bSize + i) * 2] = length == 0 ? 0 : gx / length;
        gradient[(k * _bSize + i) * 2 + 1] = length == 0 ? 0 : gy / length;
      }
    }
    for (var i = _bSize - 1; i > 0; i--) {
      final k = order[i];
      s = _random(s);
      final j = s % _bSize;
      order[i] = order[j];
      order[j] = k;
    }
    for (var i = 0; i < _bSize + _bSize + 2; i++) {
      lattice[i] = order[i & _bMask];
    }
  }

  /// The gradient the lattice gives the point `(bx, by)` for [channel], as an index into [gradient].
  int gradientAt(int channel, int bx, int by) => (channel * _bSize + lattice[lattice[bx & _bMask] + (by & _bMask)]) * 2;

  /// One octave: `noise2` of the reference, at the noise's own coordinates. [stitch] wraps the lattice so a tile
  /// meets itself.
  double noise2(int channel, double vx, double vy, [TurbulenceStitch? stitch]) {
    var t = vx + _perlinN;
    var bx0 = t.floor();
    var bx1 = bx0 + 1;
    final rx0 = t - bx0;
    final rx1 = rx0 - 1;
    t = vy + _perlinN;
    var by0 = t.floor();
    var by1 = by0 + 1;
    final ry0 = t - by0;
    final ry1 = ry0 - 1;
    if (stitch != null) {
      if (bx0 >= stitch.wrapX) bx0 -= stitch.width;
      if (bx1 >= stitch.wrapX) bx1 -= stitch.width;
      if (by0 >= stitch.wrapY) by0 -= stitch.height;
      if (by1 >= stitch.wrapY) by1 -= stitch.height;
    }
    bx0 &= _bMask;
    bx1 &= _bMask;
    by0 &= _bMask;
    by1 &= _bMask;
    final i = lattice[bx0];
    final j = lattice[bx1];
    final b00 = (channel * _bSize + lattice[i + by0]) * 2;
    final b10 = (channel * _bSize + lattice[j + by0]) * 2;
    final b01 = (channel * _bSize + lattice[i + by1]) * 2;
    final b11 = (channel * _bSize + lattice[j + by1]) * 2;
    final sx = rx0 * rx0 * (3 - 2 * rx0);
    final sy = ry0 * ry0 * (3 - 2 * ry0);
    var u = rx0 * gradient[b00] + ry0 * gradient[b00 + 1];
    var v = rx1 * gradient[b10] + ry0 * gradient[b10 + 1];
    final a = u + sx * (v - u);
    u = rx0 * gradient[b01] + ry1 * gradient[b01 + 1];
    v = rx1 * gradient[b11] + ry1 * gradient[b11 + 1];
    final b = u + sx * (v - u);
    return a + sy * (b - a);
  }

  /// The sum of the octaves at a point in user space, before it is made a colour: `turbulence` of the reference.
  /// `fractalNoise` sums the octaves as they are and [fractal] false (`turbulence`) their absolute values. A
  /// [tile] stitches: its frequencies are nudged to whole lattice cells across the tile, as the specification says.
  double sum(
    int channel,
    double x,
    double y, {
    required double baseFrequencyX,
    required double baseFrequencyY,
    required int octaves,
    bool fractal = true,
    TurbulenceTile? tile,
  }) {
    var fx = baseFrequencyX, fy = baseFrequencyY;
    TurbulenceStitch? stitch;
    if (tile != null) {
      fx = tile.stitchedFrequency(fx, tile.width);
      fy = tile.stitchedFrequency(fy, tile.height);
      stitch = TurbulenceStitch((tile.width * fx + 0.5).floor(), (tile.height * fy + 0.5).floor());
    }
    var total = 0.0;
    var vx = x * fx, vy = y * fy;
    var ratio = 1.0;
    for (var octave = 0; octave < octaves; octave++) {
      final n = noise2(channel, vx, vy, stitch);
      total += (fractal ? n : n.abs()) / ratio;
      vx *= 2;
      vy *= 2;
      ratio *= 2;
      if (stitch != null) stitch = TurbulenceStitch(stitch.width * 2, stitch.height * 2);
    }
    return total;
  }

  /// The colour channel the filter draws at a point, 0 to 1: `(sum + 1) / 2` for fractal noise, the sum for
  /// turbulence, clamped.
  double sample(
    int channel,
    double x,
    double y, {
    required double baseFrequencyX,
    required double baseFrequencyY,
    required int octaves,
    bool fractal = true,
    TurbulenceTile? tile,
  }) {
    final total = sum(channel, x, y, baseFrequencyX: baseFrequencyX, baseFrequencyY: baseFrequencyY, octaves: octaves, fractal: fractal, tile: tile);
    return (fractal ? (total + 1) / 2 : total).clamp(0.0, 1.0);
  }
}

/// A tile the noise is stitched to (`stitchTiles="stitch"`): the primitive's own box, from its corner.
class TurbulenceTile {
  const TurbulenceTile(this.width, this.height);
  final double width, height;

  /// The frequency nearest [frequency] that fits a whole number of lattice cells across [side].
  double stitchedFrequency(double frequency, double side) {
    if (frequency == 0) return 0;
    final lo = (side * frequency).floorToDouble() / side;
    final hi = (side * frequency).ceilToDouble() / side;
    return frequency / lo < hi / frequency ? lo : hi;
  }
}

/// Where the lattice wraps for one octave of a stitched tile.
class TurbulenceStitch {
  TurbulenceStitch(this.width, this.height)
      : wrapX = Turbulence._perlinN + width,
        wrapY = Turbulence._perlinN + height;
  final int width, height;
  final int wrapX, wrapY;
}

/// The side of [wispNoiseTable]'s picture: 256 lattice points down, and two channels of 256 across.
const int wispNoiseTableWidth = 512;
const int wispNoiseTableHeight = 256;

/// The table a fragment shader reads the noise from (shaders/wisp_noise.glsl): for every lattice point `(bx, by)`,
/// the gradient the red channel's noise has there in the left half and the green's in the right, since the two the
/// displacement reads are the only two a wisp uses. Chromium's own shader keeps a table like it for the same reason:
/// the generator runs in order, and a shader cannot.
///
/// A texel is opaque and holds one gradient in its colour, twelve bits to each axis: the first axis in red and the
/// top four bits of green, the second in the bottom four of green and blue. Opaque, so nothing between here and the
/// sampler has a reason to multiply the colour by an alpha; twelve bits put a gradient within 1/4096 of itself,
/// which is a few thousandths of a pixel of bend.
Uint8List wispNoiseTable(Turbulence noise) {
  final out = Uint8List(wispNoiseTableWidth * wispNoiseTableHeight * 4);
  for (var by = 0; by < 256; by++) {
    for (var channel = 0; channel < 2; channel++) {
      for (var bx = 0; bx < 256; bx++) {
        final g = noise.gradientAt(channel, bx, by);
        final x = (((noise.gradient[g] + 1) / 2) * 4095).round().clamp(0, 4095);
        final y = (((noise.gradient[g + 1] + 1) / 2) * 4095).round().clamp(0, 4095);
        final at = (by * wispNoiseTableWidth + channel * 256 + bx) * 4;
        out[at] = x >> 4;
        out[at + 1] = ((x & 0xf) << 4) | (y >> 8);
        out[at + 2] = y & 0xff;
        out[at + 3] = 255;
      }
    }
  }
  return out;
}

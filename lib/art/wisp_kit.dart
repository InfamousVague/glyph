import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'turbulence.dart';

/// What every wisp draws with: the fragment programs (shaders/wisp_bend.frag, wisp_haze.frag, wisp_smoke.frag, and
/// wisp_merge.frag for the drawing they are held to) and, for each `seed` a filter names, the table its noise is
/// read from (turbulence.dart). The web app's counterpart is the hidden `<svg>` of filters art/WispEdgeFilter.tsx
/// mounts once and the shelves art/wispBox.ts keeps.
///
/// Loaded once, off the first frame: a program is read from the bundle and a table decoded, neither of which can be
/// had at once. Until [maybe] answers, a wisp draws what the web app draws before its filter exists, the plain edge.
class WispKit {
  WispKit._(this._bend, this._merge, this._small, this._field, this._haze, this._smoke, this._halo, this._back, this._through, this._soft);

  final ui.FragmentProgram _bend, _merge, _small, _field, _haze, _smoke, _halo, _back, _through, _soft;
  final Map<int, ui.Image> _tables = {};
  final Map<int, Future<ui.Image>> _tablesComing = {};

  static WispKit? _kit;
  static Future<WispKit>? _loading;

  /// The kit, once it has loaded.
  static WispKit? get maybe => _kit;

  /// Loads the programs, and the tables for [seeds], once; a later call asks only for seeds not yet made.
  static Future<WispKit> load({Iterable<int> seeds = const [3]}) async {
    final kit = await (_loading ??= _load());
    await Future.wait([for (final seed in seeds) kit.table(seed)]);
    return kit;
  }

  static Future<WispKit> _load() async {
    final programs = await Future.wait([
      ui.FragmentProgram.fromAsset('shaders/wisp_bend.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_merge.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_small.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_field.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_haze.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_smoke.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_halo.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_back.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_through.frag'),
      ui.FragmentProgram.fromAsset('shaders/wisp_soft.frag'),
    ]);
    return _kit = WispKit._(programs[0], programs[1], programs[2], programs[3], programs[4], programs[5], programs[6], programs[7], programs[8], programs[9]);
  }

  /// The noise table for [seed], made the first time it is asked for.
  Future<ui.Image> table(int seed) {
    final have = _tables[seed];
    if (have != null) return Future.value(have);
    return _tablesComing[seed] ??= () {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(wispNoiseTable(Turbulence(seed)), wispNoiseTableWidth, wispNoiseTableHeight, ui.PixelFormat.rgba8888, (image) {
        _tables[seed] = image;
        done.complete(image);
      });
      return done.future;
    }();
  }

  /// The table for [seed] if it has been made; asks for it if not, so the next frame may have it.
  ui.Image? tableNow(int seed) {
    final have = _tables[seed];
    if (have == null) unawaited(table(seed));
    return have;
  }

  ui.FragmentShader? _bendShader, _smallShader, _fieldShader, _mergeShader, _hazeShader, _smokeShader, _haloShader;

  /// The noise of [smoke] as a picture, set up for one draw at [origin] (shaders/wisp_field.frag): what
  /// shaders/wisp_smoke.frag reads the bend from.
  ui.FragmentShader field({required Offset origin, required WispSmoke smoke, required ui.Image table}) {
    final shader = _fieldShader ??= _field.fragmentShader();
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    put(origin.dx);
    put(origin.dy);
    put(smoke.frequency.dx);
    put(smoke.frequency.dy);
    put(smoke.slide.dx);
    put(smoke.slide.dy);
    put(smoke.noiseRect.left);
    put(smoke.noiseRect.top);
    put(smoke.noiseRect.right);
    put(smoke.noiseRect.bottom);
    shader.setImageSampler(0, table);
    return shader;
  }

  /// A smoke read off the backdrop (shaders/wisp_back.frag), as a program of its own for one filter: measuring
  /// only. [viewAt] is the view's corner on the screen; the engine gives the backdrop and its size.
  ui.FragmentShader back({required Offset viewAt, required double ratio, required WispSmoke smoke, required ui.Image field, required Rect fieldRect, required Color paper, double probe = 0}) {
    final shader = _back.fragmentShader();
    // The first two are the engine's: the backdrop's size.
    var i = 2;
    void put(double value) => shader.setFloat(i++, value);
    put(viewAt.dx);
    put(viewAt.dy);
    put(ratio);
    put(fieldRect.left);
    put(fieldRect.top);
    put(fieldRect.width);
    put(fieldRect.height);
    put(field.width.toDouble());
    put(field.height.toDouble());
    put(smoke.frequency.dx);
    put(smoke.frequency.dy);
    put(smoke.slide.dx);
    put(smoke.slide.dy);
    put(smoke.noiseRect.left);
    put(smoke.noiseRect.top);
    put(smoke.noiseRect.right);
    put(smoke.noiseRect.bottom);
    put(smoke.lipA ?? 0);
    put(smoke.lipB ?? 0);
    put(smoke.soft);
    put(smoke.axis == Axis.vertical ? 0 : 1);
    put(smoke.lipA == null ? 0 : 1);
    put(smoke.lipB == null ? 0 : 1);
    put(smoke.bend);
    put(smoke.fade.clearUntil);
    put(smoke.fade.wholeFrom);
    put(smoke.fade.wholeUntil);
    put(smoke.fade.clearFrom);
    put(paper.r * paper.a);
    put(paper.g * paper.a);
    put(paper.b * paper.a);
    put(paper.a);
    put(probe);
    // The first sampler is the engine's: the backdrop.
    shader.setImageSampler(1, field);
    return shader;
  }

  /// A smoke's soft half off the blurred backdrop (shaders/wisp_soft.frag), a program of its own for one filter:
  /// measuring only. [viewAt] is the view's corner on the screen in the view's pixels; [contrast] how far the page's
  /// ink stands from its [paper] at most in a channel, 0 to 1.
  ui.FragmentShader soft({required Offset viewAt, required double ratio, required WispSmoke smoke, required Color paper, required double contrast, required double gain}) {
    final shader = _soft.fragmentShader();
    var i = 2;
    void put(double value) => shader.setFloat(i++, value);
    put(viewAt.dx);
    put(viewAt.dy);
    put(ratio);
    put(smoke.lipA ?? 0);
    put(smoke.lipB ?? 0);
    put(smoke.soft);
    put(smoke.axis == Axis.vertical ? 0 : 1);
    put(smoke.lipA == null ? 0 : 1);
    put(smoke.lipB == null ? 0 : 1);
    put(smoke.fade.clearUntil);
    put(smoke.fade.wholeFrom);
    put(smoke.fade.wholeUntil);
    put(smoke.fade.clearFrom);
    put(paper.r);
    put(paper.g);
    put(paper.b);
    put(contrast);
    put(gain);
    return shader;
  }

  /// A view's smokes as one filter over the view's own layers (shaders/wisp_through.frag), a program of its own for
  /// the one filter: measuring only. [corner] is the point of the view the first pixel of the engine's picture is
  /// of, [ratio] that picture's pixels to one of the view's; [smokes] are one or two, each over its own strip, of
  /// one seed, one axis and one fade.
  ui.FragmentShader through({required Offset corner, required double ratio, required List<({Rect strip, WispSmoke smoke})> smokes, required ui.Image field, required Rect fieldRect, double probe = 0}) {
    final shader = _through.fragmentShader();
    // The first two are the engine's: the picture's size.
    var i = 2;
    void put(double value) => shader.setFloat(i++, value);
    put(corner.dx);
    put(corner.dy);
    put(ratio);
    put(fieldRect.left);
    put(fieldRect.top);
    put(fieldRect.width);
    put(fieldRect.height);
    put(field.width.toDouble());
    put(field.height.toDouble());
    final first = smokes.first.smoke;
    put(first.fade.clearUntil);
    put(first.fade.wholeFrom);
    put(first.fade.wholeUntil);
    put(first.fade.clearFrom);
    put(first.axis == Axis.vertical ? 0 : 1);
    for (var n = 0; n < 2; n++) {
      if (n >= smokes.length) {
        // No smoke: a strip nothing is in.
        for (var k = 0; k < 19; k++) {
          put(0);
        }
        continue;
      }
      final strip = smokes[n].strip, smoke = smokes[n].smoke;
      put(strip.left);
      put(strip.top);
      put(strip.right);
      put(strip.bottom);
      put(smoke.frequency.dx);
      put(smoke.frequency.dy);
      put(smoke.slide.dx);
      put(smoke.slide.dy);
      put(smoke.noiseRect.left);
      put(smoke.noiseRect.top);
      put(smoke.noiseRect.right);
      put(smoke.noiseRect.bottom);
      put(smoke.lipA ?? 0);
      put(smoke.lipB ?? 0);
      put(smoke.soft);
      put(0);
      put(smoke.lipA == null ? 0 : 1);
      put(smoke.lipB == null ? 0 : 1);
      put(smoke.bend);
    }
    put(probe);
    // The first sampler is the engine's: the view.
    shader.setImageSampler(1, field);
    return shader;
  }

  /// The noise of a table in its own space, set up for one draw whose canvas counts in the noise's cells from
  /// [origin] (shaders/wisp_field.frag with a frequency of one and no slide): what every smoke of that seed reads
  /// its bend from, whatever its frequency and wherever it has slid ([wispNoiseField]).
  ui.FragmentShader noise({required Offset origin, required ui.Image table}) {
    final shader = _fieldShader ??= _field.fragmentShader();
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    // The program adds half a pixel to where it stands, for a smoke's own pixels: taken off here.
    put(origin.dx - 0.5);
    put(origin.dy - 0.5);
    put(1);
    put(1);
    put(0);
    put(0);
    put(-1e9);
    put(-1e9);
    put(1e9);
    put(1e9);
    shader.setImageSampler(0, table);
    return shader;
  }

  /// The bend pass, set up for one draw: [source] thrown about by the noise of [smoke], drawn at [origin] in the
  /// view. The one shader is used again for every draw; a draw takes its own copy of what was set.
  ///
  /// With a [spread], the bend is one drawn smaller than the screen, by a program of its own
  /// (shaders/wisp_small.frag): [spread] is how far round each point the view is read, a quarter of the small
  /// picture's pixel, so each of its pixels is the mean of the view's under it.
  ui.FragmentShader bend({
    required ui.Image source,
    required Rect sourceRect,
    required Offset origin,
    required WispSmoke smoke,
    required ui.Image table,
    Offset spread = Offset.zero,
  }) {
    final small = spread != Offset.zero;
    final shader = small ? (_smallShader ??= _small.fragmentShader()) : (_bendShader ??= _bend.fragmentShader());
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    put(origin.dx);
    put(origin.dy);
    put(sourceRect.left);
    put(sourceRect.top);
    put(sourceRect.width);
    put(sourceRect.height);
    put(smoke.frequency.dx);
    put(smoke.frequency.dy);
    put(smoke.slide.dx);
    put(smoke.slide.dy);
    put(smoke.noiseRect.left);
    put(smoke.noiseRect.top);
    put(smoke.noiseRect.right);
    put(smoke.noiseRect.bottom);
    put(smoke.lipA ?? 0);
    put(smoke.lipB ?? 0);
    put(smoke.soft);
    put(smoke.axis == Axis.vertical ? 0 : 1);
    put(smoke.lipA == null ? 0 : 1);
    put(smoke.lipB == null ? 0 : 1);
    put(smoke.bend);
    if (small) {
      put(spread.dx);
      put(spread.dy);
      // Read between the view's pixels; a bend at the screen's size takes the one pixel.
      shader.setImageSampler(0, source, filterQuality: FilterQuality.low);
    } else {
      shader.setImageSampler(0, source);
    }
    shader.setImageSampler(1, table);
    return shader;
  }

  /// The soft half of a smoke, set up for one draw at [origin]: [bent], a small picture of the bent view lying over
  /// [bentRect], blurred and kept near its own ink (shaders/wisp_haze.frag). [taps] is the blur as the shader reads
  /// it ([wispBlurTaps]); [near] is the dilate's radius in the view's pixels, and [gain] what the ink found is
  /// multiplied by, none ([gain] 0) leaving the blur whole. [own] is the part of the picture that is this smoke's,
  /// where the picture holds others' too. The draw must lay the picture's own pixels on the canvas's, one to one.
  ui.FragmentShader haze({required ui.Image bent, required Rect bentRect, Rect? own, required Offset origin, required WispBlurTaps taps, required Offset near, required double gain}) {
    final shader = _hazeShader ??= _haze.fragmentShader();
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    put(origin.dx);
    put(origin.dy);
    for (final rect in [bentRect, own ?? bentRect]) {
      put(rect.left);
      put(rect.top);
      put(rect.width);
      put(rect.height);
    }
    put(bentRect.width / bent.width);
    put(bentRect.height / bent.height);
    for (final offset in taps.offsets) {
      put(offset);
    }
    for (final weight in taps.weights) {
      put(weight);
    }
    put(near.dx);
    put(near.dy);
    put(gain);
    shader.setImageSampler(0, bent, filterQuality: FilterQuality.low);
    return shader;
  }

  /// A smoke in one pass, set up for one draw at [origin]: the view bent where it stands and merged with [haze],
  /// its soft half lying over [hazeRect] (shaders/wisp_smoke.frag). [bentRect] is where the bent view is worked out
  /// at all, the filter's own subregion; [field] is the noise of the smoke's seed in its own space
  /// ([wispNoiseField]) over [fieldRect] of it.
  ui.FragmentShader smoke({
    required ui.Image source,
    required Rect sourceRect,
    required Rect bentRect,
    required ui.Image haze,
    required Rect hazeRect,
    required ui.Image field,
    required Rect fieldRect,
    required Offset origin,
    required WispSmoke smoke,
  }) {
    final shader = _smokeShader ??= _smoke.fragmentShader();
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    put(origin.dx);
    put(origin.dy);
    for (final rect in [sourceRect, bentRect, hazeRect, fieldRect]) {
      put(rect.left);
      put(rect.top);
      put(rect.width);
      put(rect.height);
    }
    put(field.width.toDouble());
    put(field.height.toDouble());
    put(smoke.frequency.dx);
    put(smoke.frequency.dy);
    put(smoke.slide.dx);
    put(smoke.slide.dy);
    put(smoke.noiseRect.left);
    put(smoke.noiseRect.top);
    put(smoke.noiseRect.right);
    put(smoke.noiseRect.bottom);
    put(smoke.lipA ?? 0);
    put(smoke.lipB ?? 0);
    put(smoke.soft);
    put(smoke.axis == Axis.vertical ? 0 : 1);
    put(smoke.lipA == null ? 0 : 1);
    put(smoke.lipB == null ? 0 : 1);
    put(smoke.bend);
    put(smoke.fade.clearUntil);
    put(smoke.fade.wholeFrom);
    put(smoke.fade.wholeUntil);
    put(smoke.fade.clearFrom);
    shader.setImageSampler(0, source);
    // The noise's pixels are packed numbers: read one at a time, and weighed by the shader once unpacked.
    shader.setImageSampler(1, field);
    // The soft half is a small picture, read between its pixels.
    shader.setImageSampler(2, haze, filterQuality: FilterQuality.low);
    return shader;
  }

  /// The last pass, set up for one draw: the view, the bent view and its blur made one picture at [origin].
  ui.FragmentShader merge({
    required ui.Image source,
    required Rect sourceRect,
    required ui.Image bent,
    required ui.Image soft,
    required Rect bentRect,
    required Offset origin,
    required WispSmoke smoke,
  }) {
    final shader = _mergeShader ??= _merge.fragmentShader();
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    put(origin.dx);
    put(origin.dy);
    put(sourceRect.left);
    put(sourceRect.top);
    put(sourceRect.width);
    put(sourceRect.height);
    put(bentRect.left);
    put(bentRect.top);
    put(bentRect.width);
    put(bentRect.height);
    put(smoke.lipA ?? 0);
    put(smoke.lipB ?? 0);
    put(smoke.soft);
    put(smoke.axis == Axis.vertical ? 0 : 1);
    put(smoke.lipA == null ? 0 : 1);
    put(smoke.lipB == null ? 0 : 1);
    put(smoke.near.dx);
    put(smoke.near.dy);
    put(smoke.fade.clearUntil);
    put(smoke.fade.wholeFrom);
    put(smoke.fade.wholeUntil);
    put(smoke.fade.clearFrom);
    shader.setImageSampler(0, source);
    // The bent view is read between its pixels for the dilate's taps; the other two pixel for pixel.
    shader.setImageSampler(1, bent, filterQuality: FilterQuality.low);
    shader.setImageSampler(2, soft);
    return shader;
  }

  /// The dock's halo in one pass, set up for one draw at [origin] (shaders/wisp_halo.frag): [source], the view
  /// behind the dock over [sourceRect]; [soft], that bent and softened, over [softRect]; [pills], the halo's ramp
  /// (in red) and core (in green) over [halo], the halo's own box; [tile], the smoke the ramp is cut by, slid by
  /// [slide]; and [wash], the page's ground at the wash's strength.
  ui.FragmentShader halo({
    required ui.Image source,
    required Rect sourceRect,
    required ui.Image soft,
    required Rect softRect,
    required ui.Image pills,
    required Rect halo,
    required ui.Image tile,
    required double tileSide,
    required Offset slide,
    required Color wash,
    required Offset origin,
  }) {
    final shader = _haloShader ??= _halo.fragmentShader();
    var i = 0;
    void put(double value) => shader.setFloat(i++, value);
    put(origin.dx);
    put(origin.dy);
    for (final rect in [sourceRect, softRect, halo]) {
      put(rect.left);
      put(rect.top);
      put(rect.width);
      put(rect.height);
    }
    put(wash.r * wash.a);
    put(wash.g * wash.a);
    put(wash.b * wash.a);
    put(wash.a);
    put(slide.dx);
    put(slide.dy);
    put(tileSide);
    shader.setImageSampler(0, source);
    shader.setImageSampler(1, soft, filterQuality: FilterQuality.low);
    shader.setImageSampler(2, pills, filterQuality: FilterQuality.low);
    shader.setImageSampler(3, tile, filterQuality: FilterQuality.low);
    return shader;
  }

  /// Puts a kit in place of the loaded one, or takes it away: for a test that wants the plain edge.
  static void debugReset() {
    _kit = null;
    _loading = null;
  }
}

/// A Gaussian blur as shaders/wisp_haze.frag reads it: thirteen pixels each way, the middle one and three pairs
/// either side. [offsets] is where each pair is read, in pixels from the middle; [weights] is what the middle and
/// each pair weigh, the middle and twice the pairs summing to one.
@immutable
class WispBlurTaps {
  const WispBlurTaps(this.offsets, this.weights);
  final List<double> offsets, weights;

  /// No blur: the pixel itself.
  static const none = WispBlurTaps([1.5, 3.5, 5.5], [1, 0, 0, 0]);
}

/// The taps of a blur whose deviation is [sigma] of the picture's own pixels.
///
/// The curve is cut at six pixels from the middle, and a curve cut short is a narrower blur than it says, so the
/// one used is the one whose cut weights have the deviation asked for (found by halving; past about three and a
/// half pixels no cut curve is that wide, and the widest stands). A pair is read at the point between its two
/// pixels that the engine's own reading between pixels weighs as the curve does.
WispBlurTaps wispBlurTaps(double sigma) {
  if (sigma < 0.2) return WispBlurTaps.none;
  List<double> curve(double s) => [for (var k = 0; k <= 6; k++) math.exp(-k * k / (2 * s * s))];
  double spread(List<double> w) {
    var sum = w[0], moment = 0.0;
    for (var k = 1; k <= 6; k++) {
      sum += 2 * w[k];
      moment += 2 * w[k] * k * k;
    }
    return moment / sum;
  }

  var low = 0.1, high = 40.0;
  for (var i = 0; i < 40; i++) {
    final mid = (low + high) / 2;
    spread(curve(mid)) < sigma * sigma ? low = mid : high = mid;
  }
  final w = curve((low + high) / 2);
  final total = w[0] + 2 * (w[1] + w[2] + w[3] + w[4] + w[5] + w[6]);
  final offsets = <double>[], weights = <double>[w[0] / total];
  for (var k = 1; k <= 5; k += 2) {
    final pair = w[k] + w[k + 1];
    offsets.add(pair > 1e-12 ? (k * w[k] + (k + 1) * w[k + 1]) / pair : k + 0.5);
    weights.add(pair / total);
  }
  return WispBlurTaps(offsets, weights);
}

/// A view's own `mask-image` along a band's axis, the four stops of the `linear-gradient` the stylesheets write
/// (art/wisp.css, notes/NoteTabs.module.css, editor/boards/theme.ts): clear up to [clearUntil], whole from [wholeFrom]
/// until [wholeUntil], clear again from [clearFrom]. Two stops at one place are a cut.
class WispFade {
  const WispFade({this.clearUntil = -1e9, this.wholeFrom = -1e9, this.wholeUntil = 1e9, this.clearFrom = 1e9});
  final double clearUntil, wholeFrom, wholeUntil, clearFrom;

  static const none = WispFade();

  /// How much of the view shows at [along] the axis, 0 to 1.
  double at(double along) {
    final rise = wholeFrom > clearUntil ? ((along - clearUntil) / (wholeFrom - clearUntil)).clamp(0.0, 1.0) : (along >= clearUntil ? 1.0 : 0.0);
    final fall = clearFrom > wholeUntil ? ((clearFrom - along) / (clearFrom - wholeUntil)).clamp(0.0, 1.0) : (along < clearFrom ? 1.0 : 0.0);
    return rise * fall;
  }

  @override
  bool operator ==(Object other) =>
      other is WispFade && other.clearUntil == clearUntil && other.wholeFrom == wholeFrom && other.wholeUntil == wholeUntil && other.clearFrom == clearFrom;

  @override
  int get hashCode => Object.hash(clearUntil, wholeFrom, wholeUntil, clearFrom);
}

/// One smoke filter's numbers, in the view's own pixels: what a `<filter>` of the web app says in attributes.
///
/// The band is the web filters' white strips on black after their blur: [lipA] is where a strip that comes from
/// before the view (its top, or its left) ends, [lipB] where one that runs on past it (its foot, or its right)
/// begins, [soft] the blur's `stdDeviation` and [axis] the way the lips face. Null for a lip that is not there. With
/// neither, [flat] bends everything alike, as a letter of art/WispText.tsx is bent.
class WispSmoke {
  const WispSmoke({
    required this.seed,
    required this.frequency,
    this.slide = Offset.zero,
    this.noiseRect = const Rect.fromLTRB(-1e9, -1e9, 1e9, 1e9),
    this.lipA,
    this.lipB,
    this.soft = 1,
    this.axis = Axis.vertical,
    required this.bend,
    required this.blur,
    this.near = Offset.zero,
    this.fade = WispFade.none,
  });

  /// A filter with no band: the noise bends the whole picture by [bend].
  const WispSmoke.flat({required this.seed, required this.frequency, required this.bend, required this.blur})
      : slide = Offset.zero,
        noiseRect = const Rect.fromLTRB(-1e9, -1e9, 1e9, 1e9),
        lipA = 1e9,
        lipB = null,
        soft = 1,
        axis = Axis.vertical,
        near = Offset.zero,
        fade = WispFade.none;

  /// `feTurbulence seed`.
  final int seed;

  /// `baseFrequency`, per pixel, across and down.
  final Offset frequency;

  /// `feOffset dx dy` on the noise.
  final Offset slide;

  /// The turbulence's own subregion: slid out of it, the noise is black and throws everything one way.
  final Rect noiseRect;
  final double? lipA, lipB;
  final double soft;
  final Axis axis;

  /// `feDisplacementMap scale`: the throw is at most half of it either way.
  final double bend;

  /// `feGaussianBlur stdDeviation` on the bent view.
  final double blur;

  /// `feMorphology radius`, across and down: how far past the bent strokes the blur may show.
  final Offset near;
  final WispFade fade;

  /// The band at a point [along] its axis, 0 to 1: what shaders/wisp_bend.frag works out for each pixel.
  double bandAt(double along) {
    final sigma = soft <= 0 ? 0.0001 : soft;
    var band = 0.0;
    if (lipA != null) band += gaussianRamp((lipA! - along) / sigma);
    if (lipB != null) band += gaussianRamp((along - lipB!) / sigma);
    return band.clamp(0.0, 1.0);
  }

  /// The parts of [strip] this smoke changes at all, along its axis: from the strip's start to three deviations of
  /// the ramp past lip A (or to where the fade is whole, if that is further), and from three deviations before lip
  /// B (or where the fade begins) to its end. Between the two the band is under 0.0014, so the bend moves nothing by
  /// a pixel and the smoke adds less than half a step of 255: the view as it is. One part where the two meet, or
  /// where there is only one lip; all of [strip] for a smoke with no band ([WispSmoke.flat]).
  List<Rect> touched(Rect strip) {
    const nowhere = 1e8;
    final from = axis == Axis.vertical ? strip.top : strip.left, to = axis == Axis.vertical ? strip.bottom : strip.right;
    Rect part(double a, double b) => axis == Axis.vertical ? Rect.fromLTRB(strip.left, a, strip.right, b) : Rect.fromLTRB(a, strip.top, b, strip.bottom);
    final reach = 3 * soft;
    // Where the first part ends and the second begins; a lip or a fade that is not there reaches nothing.
    var firstEnd = from, secondStart = to;
    if (lipA != null) firstEnd = math.max(firstEnd, lipA! + reach);
    if (fade.wholeFrom > -nowhere) firstEnd = math.max(firstEnd, fade.wholeFrom);
    if (lipB != null) secondStart = math.min(secondStart, lipB! - reach);
    if (fade.wholeUntil < nowhere) secondStart = math.min(secondStart, fade.wholeUntil);
    // Out to whole pixels, where there is a part at all: an end nothing reaches stays the strip's own edge, which
    // need not lie on a whole pixel (a sliver between the edge and the next whole one would be a strip, with every
    // picture a strip is drawn through, for a line of nothing).
    if (firstEnd > from) firstEnd = math.min(firstEnd.ceilToDouble(), to);
    if (secondStart < to) secondStart = math.max(secondStart.floorToDouble(), from);
    if (firstEnd >= secondStart) return [strip];
    return [
      if (firstEnd > from) part(from, firstEnd),
      if (secondStart < to) part(secondStart, to),
    ];
  }

  WispSmoke copyWith({Offset? frequency, Offset? slide, double? lipA, double? bend, double? blur, WispFade? fade}) => WispSmoke(
        seed: seed,
        frequency: frequency ?? this.frequency,
        slide: slide ?? this.slide,
        noiseRect: noiseRect,
        lipA: lipA ?? this.lipA,
        lipB: lipB,
        soft: soft,
        axis: axis,
        bend: bend ?? this.bend,
        blur: blur ?? this.blur,
        near: near,
        fade: fade ?? this.fade,
      );

  @override
  bool operator ==(Object other) =>
      other is WispSmoke &&
      other.seed == seed &&
      other.frequency == frequency &&
      other.slide == slide &&
      other.noiseRect == noiseRect &&
      other.lipA == lipA &&
      other.lipB == lipB &&
      other.soft == soft &&
      other.axis == axis &&
      other.bend == bend &&
      other.blur == blur &&
      other.near == near &&
      other.fade == fade;

  @override
  int get hashCode => Object.hash(seed, frequency, slide, noiseRect, lipA, lipB, soft, axis, bend, blur, near, fade);
}

/// The normal distribution's running total at [x] standard deviations: a hard step after `feGaussianBlur`. The same
/// approximation the shaders use (Abramowitz and Stegun 7.1.26), so a test can hold one to the other.
double gaussianRamp(double x) {
  final t = 1 / (1 + 0.3275911 * x.abs() * 0.70710678);
  final y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-0.5 * x * x);
  return 0.5 * (1 + x.sign * y);
}

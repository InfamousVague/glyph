import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'turbulence.dart';

/// What every wisp draws with: the fragment programs (shaders/wisp_bend.frag, wisp_merge.frag) and,
/// for each `seed` a filter names, the table its noise is read from (turbulence.dart). The web app's counterpart is
/// the hidden `<svg>` of filters art/WispEdgeFilter.tsx mounts once and the shelves art/wispBox.ts keeps.
///
/// Loaded once, off the first frame: a program is read from the bundle and a table decoded, neither of which can be
/// had at once. Until [maybe] answers, a wisp draws what the web app draws before its filter exists, the plain edge.
class WispKit {
  WispKit._(this._bend, this._merge);

  final ui.FragmentProgram _bend, _merge;
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
    ]);
    return _kit = WispKit._(programs[0], programs[1]);
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

  ui.FragmentShader? _bendShader, _mergeShader;

  /// The bend pass, set up for one draw: [source] thrown about by the noise of [smoke], drawn at [origin] in the
  /// view. The one shader is used again for every draw; a draw takes its own copy of what was set.
  ui.FragmentShader bend({required ui.Image source, required Rect sourceRect, required Offset origin, required WispSmoke smoke, required ui.Image table}) {
    final shader = _bendShader ??= _bend.fragmentShader();
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
    shader.setImageSampler(0, source);
    shader.setImageSampler(1, table);
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

  /// Puts a kit in place of the loaded one, or takes it away: for a test that wants the plain edge.
  static void debugReset() {
    _kit = null;
    _loading = null;
  }
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

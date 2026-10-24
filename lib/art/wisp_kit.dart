import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import 'turbulence.dart';

/// The bend that is left of the wisp: the fragment program that throws a picture about by the SVG specification's
/// noise (shaders/wisp_bend.frag), and for each `seed` a filter names, the table its noise is read from
/// (turbulence.dart). The heat a mark gives words (lib/editor/marks/text_effects.dart, `🔥🔥…🔥🔥`) and the haze
/// over a scene's words (lib/scene/at_work.dart) are drawn with it: a heat haze, which wavers, not smoke.
///
/// The smoke itself is gone (Matt, 2026-10-24: "replace the smoke effect with a gradient blur on all places that
/// use the wisp smoke", and then "remove the smoke on mac too so all versions get blur"): a page's edges, the dock's
/// halo, a lane's foot and the tab row's ends are a gradient blur (lib/art/edge_strips.dart), and letters that came
/// out of smoke come out of a blur (lib/art/blur_letter.dart). With it went the nine programs the smoke alone was
/// drawn with (its field, its soft half, its merge, the halo, the readings off the backdrop) and the sheet of
/// letters in smoke.
///
/// Loaded once, off the first frame: a program is read from the bundle and a table decoded, neither of which can be
/// had at once. Until [maybe] answers, what is drawn with it is drawn without the bend.
class WispKit {
  WispKit._(this._bend);

  final ui.FragmentProgram _bend;
  final Map<int, ui.Image> _tables = {};
  final Map<int, Future<ui.Image>> _tablesComing = {};

  static WispKit? _kit;
  static Future<WispKit>? _loading;

  /// The kit, once it has loaded.
  static WispKit? get maybe => _kit;

  /// Loads the program, and the tables for [seeds], once; a later call asks only for seeds not yet made.
  static Future<WispKit> load({Iterable<int> seeds = const [3]}) async {
    final kit = await (_loading ??= _load());
    await Future.wait([for (final seed in seeds) kit.table(seed)]);
    return kit;
  }

  static Future<WispKit> _load() async {
    final bend = await ui.FragmentProgram.fromAsset('shaders/wisp_bend.frag');
    return _kit = WispKit._(bend);
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

  ui.FragmentShader? _bendShader;

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

  /// Takes the loaded kit away: for a test that wants what is drawn without the bend.
  static void debugReset() {
    _kit = null;
    _loading = null;
  }
}

/// One bend's numbers, in the view's own pixels: what a `<filter>` of the web app says in attributes.
///
/// The band is the web filters' white strips on black after their blur: [lipA] is where a strip that comes from
/// before the view (its top, or its left) ends, [lipB] where one that runs on past it (its foot, or its right)
/// begins, [soft] the blur's `stdDeviation` and [axis] the way the lips face. Null for a lip that is not there. With
/// neither, [flat] bends everything alike, as the heat bends its letters.
@immutable
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
  });

  /// A filter with no band: the noise bends the whole picture by [bend].
  const WispSmoke.flat({required this.seed, required this.frequency, required this.bend, required this.blur})
      : slide = Offset.zero,
        noiseRect = const Rect.fromLTRB(-1e9, -1e9, 1e9, 1e9),
        lipA = 1e9,
        lipB = null,
        soft = 1,
        axis = Axis.vertical;

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

  /// `feGaussianBlur stdDeviation` on the bent picture, which whoever draws it lays on as a layer's blur.
  final double blur;

  /// The band at a point [along] its axis, 0 to 1: what shaders/wisp_bend.frag works out for each pixel.
  double bandAt(double along) {
    final sigma = soft <= 0 ? 0.0001 : soft;
    var band = 0.0;
    if (lipA != null) band += gaussianRamp((lipA! - along) / sigma);
    if (lipB != null) band += gaussianRamp((along - lipB!) / sigma);
    return band.clamp(0.0, 1.0);
  }

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
      other.blur == blur;

  @override
  int get hashCode => Object.hash(seed, frequency, slide, noiseRect, lipA, lipB, soft, axis, bend, blur);
}

/// The normal distribution's running total at [x] standard deviations: a hard step after `feGaussianBlur`. The same
/// approximation the shader uses (Abramowitz and Stegun 7.1.26), so a test can hold one to the other.
double gaussianRamp(double x) {
  final t = 1 / (1 + 0.3275911 * x.abs() * 0.70710678);
  final y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-0.5 * x * x);
  return 0.5 * (1 + x.sign * y);
}

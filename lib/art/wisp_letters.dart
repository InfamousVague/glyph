import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../perf/frame_log.dart' show Perf, ghostPerf;
import 'wisp_kit.dart';
import 'wisp_smoke.dart';

/// Every letter in smoke on one sheet: the letters of a spoiler, of words arriving, of a headline typing itself,
/// each bent by its own noise and blurred, drawn together on one picture once and then laid on the page from it.
///
/// A letter's filter is three primitives (art/WispText.tsx: `feTurbulence`, `feDisplacementMap`, `feGaussianBlur`),
/// and drawn by itself ([paintWispLetter]'s first way) each letter is a layer of its own with a blur on it: a
/// picture the engine makes and three or four more for the blur, on every frame, for every letter. A spoiler's
/// thirty letters were over a hundred pictures a frame, and a long note with two of them on the screen spent nine
/// milliseconds of every frame on a Mac making them (tool/perf.sh, `note-fling-down`: raster 9.2 ms with the
/// letters, 1.0 without). The smoke itself only steps thirty times a second, and a letter that scrolls is the same
/// picture moved.
///
/// So while frames follow one another, what each frame asks for is remembered, and when the frame is done the
/// sheet is drawn for it: two pictures in all, however many letters, the letters bent (shaders/wisp_bend.frag, each
/// in a place of its own, at half or a quarter of the screen's pixels since they are about to be blurred) and that
/// blurred (shaders/wisp_haze.frag, each letter by its own deviation). The next frame lays each letter down from
/// the sheet. A letter is therefore drawn one frame behind what its filter says, eight or sixteen milliseconds:
/// its smoke steps every thirty-three and nobody can tell a step that late. A letter the sheet does not hold yet
/// (the first frame it is seen, or the first after the page stood still) is drawn by itself as before, so a page
/// drawn once, or a picture taken in a test, is the first way's own pixels.
class WispLetterSheet {
  WispLetterSheet._();
  static final WispLetterSheet instance = WispLetterSheet._();

  /// Frames this close together follow one another; further apart, the page stood still between them and the sheet
  /// is what the letters were then.
  static const Duration _flowing = Duration(milliseconds: 50);

  /// No more letters than this on a sheet, and no wider a sheet than this many pixels; the rest draw by themselves.
  static const int _most = 400;
  static const int _wide = 2048;

  ui.Image? _sheet;
  Map<_Letter, _Place> _places = const {};
  Duration _sheetFrame = Duration.zero;

  final Map<_Letter, _Ask?> _asked = {};
  Duration _frame = const Duration(days: -1), _frameBefore = const Duration(days: -2);
  bool _scheduled = false;

  /// How many sheets were drawn, and how many letters were laid down from one: for a test to read.
  @visibleForTesting
  int debugSheets = 0, debugLaid = 0;

  /// Lays the letter down from the sheet if it is there, and answers whether it was. Either way the letter is
  /// remembered for the sheet drawn when this frame is done. The canvas has the letter's corner at its origin.
  bool paint(Canvas canvas, {required WispKit kit, required ui.Image table, required ui.Image glyph, required Rect glyphRect, required Size box, required WispSmoke smoke, required double opacity, Offset at = Offset.zero}) {
    // Only a frame's own painting is remembered and laid down: there is no frame to follow one drawn outside it.
    if (glyphRect.isEmpty || SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) return false;
    // The screen's pixels to one of the letter's: its picture was made at them.
    final ratio = glyph.width / glyphRect.width;
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    if (now != _frame) {
      _frameBefore = _frame;
      _frame = now;
    }
    final flows = _frame - _frameBefore <= _flowing;
    final key = _Letter(glyph, glyphRect, box, smoke.seed, at);
    final had = _asked[key];
    if (_asked.containsKey(key)) {
      // Asked twice in one frame with two smokes: two letters of one shape, each in its own. Neither is the sheet's.
      if (had != null && had.smoke != smoke) {
        had.glyph.dispose();
        _asked[key] = null;
      }
    } else if (_asked.length < _most) {
      _asked[key] = _Ask(glyph.clone(), glyphRect, box, smoke, table, ratio, at);
    }
    if (!_scheduled) {
      _scheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _draw(kit, flows), debugLabel: 'WispLetterSheet.draw');
    }
    final place = _places[key];
    final sheet = _sheet;
    // The sheet's letter is this one as the frame before asked for it, and only a frame old.
    if (!flows || place == null || sheet == null || _sheetFrame != _frameBefore || _asked[key] == null) return false;
    canvas.drawImageRect(sheet, place.from, place.over, Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0))..filterQuality = FilterQuality.low);
    debugLaid += 1;
    if (ghostPerf) Perf.count('wisp.letters.laid');
    return true;
  }

  /// The frame is done: the sheet for what it asked.
  void _draw(WispKit kit, bool flows) {
    _scheduled = false;
    final asks = <_Letter, _Ask>{
      for (final entry in _asked.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    _asked.clear();
    void done() {
      for (final ask in asks.values) {
        ask.glyph.dispose();
      }
    }

    // A page drawn once is not worth a sheet: the next frame, if it is long in coming, draws by itself anyway, and
    // the sheet there was is what the letters were before the page stood still.
    if (!flows || asks.isEmpty) {
      _sheet?.dispose();
      _sheet = null;
      _places = const {};
      done();
      return;
    }
    // The sheet as it is, if it already holds every one of these in the smoke now asked for.
    if (_sheet != null && asks.entries.every((entry) => _places[entry.key]?.smoke == entry.value.smoke)) {
      _sheetFrame = _frame;
      done();
      return;
    }

    // Each letter's place: rows of them, left to right, a pixel between.
    final places = <_Letter, _Place>{};
    var x = 0, y = 0, rowTall = 0, sheetWide = 1;
    for (final entry in asks.entries) {
      final ask = entry.value;
      final step = _stepOf(ask.smoke.blur * ask.ratio);
      final texel = step / ask.ratio;
      // What the letter's own layer covers: the filter's region, and the blur's reach round it.
      final over = Rect.fromLTWH(-3 * ask.box.width, -1.5 * ask.box.height, 7 * ask.box.width, 4 * ask.box.height).inflate(ask.smoke.blur * 3);
      final wide = math.max(1, (over.width / texel).ceil()), tall = math.max(1, (over.height / texel).ceil());
      if (wide > _wide) continue;
      if (x + wide > _wide) {
        x = 0;
        y += rowTall + 1;
        rowTall = 0;
      }
      places[entry.key] = _Place(Rect.fromLTWH(x.toDouble(), y.toDouble(), wide.toDouble(), tall.toDouble()), over.topLeft & Size(wide * texel, tall * texel), ask.smoke, texel, step);
      x += wide + 1;
      rowTall = math.max(rowTall, tall);
      sheetWide = math.max(sheetWide, x);
    }
    final sheetTall = math.max(1, y + rowTall);
    if (places.isEmpty || sheetTall > 4 * _wide) {
      done();
      return;
    }

    // The letters bent, each in its place at the place's own size.
    var recorder = ui.PictureRecorder();
    var canvas = Canvas(recorder);
    for (final entry in places.entries) {
      final ask = asks[entry.key]!, place = entry.value;
      final region = Rect.fromLTWH(-3 * ask.box.width, -1.5 * ask.box.height, 7 * ask.box.width, 4 * ask.box.height);
      canvas.save();
      canvas.translate(place.from.left, place.from.top);
      canvas.clipRect(Offset.zero & place.from.size, doAntiAlias: false);
      canvas.scale(1 / place.texel);
      canvas.translate(region.left - place.over.left, region.top - place.over.top);
      final shader = kit.bend(
        source: ask.glyph,
        sourceRect: ask.glyphRect.shift(ask.at),
        origin: ask.at + region.topLeft,
        smoke: ask.smoke,
        table: ask.table,
        spread: place.step > 1 ? Offset(place.texel / 4, place.texel / 4) : Offset.zero,
      );
      canvas.drawRect(Offset.zero & region.size, Paint()..shader = shader..isAntiAlias = false);
      canvas.restore();
    }
    var picture = recorder.endRecording();
    final bent = picture.toImageSync(sheetWide, sheetTall);
    picture.dispose();

    // And blurred, each by its own deviation, reading only its own place.
    recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    final whole = Rect.fromLTWH(0, 0, sheetWide.toDouble(), sheetTall.toDouble());
    for (final place in places.values) {
      // A filter with no blur to speak of is drawn with none, as the letter's own layer is.
      final taps = place.smoke.blur < 0.05 ? WispBlurTaps.none : wispBlurTaps(wispSmallSigma(place.smoke.blur * place.step / place.texel, place.step));
      final shader = kit.haze(bent: bent, bentRect: whole, own: place.from, origin: place.from.topLeft, taps: taps, near: Offset.zero, gain: 0);
      canvas.save();
      canvas.translate(place.from.left, place.from.top);
      canvas.drawRect(Offset.zero & place.from.size, Paint()..shader = shader..isAntiAlias = false..blendMode = BlendMode.src);
      canvas.restore();
    }
    picture = recorder.endRecording();
    final sheet = picture.toImageSync(sheetWide, sheetTall);
    picture.dispose();
    bent.dispose();
    done();

    _sheet?.dispose();
    _sheet = sheet;
    _places = places;
    _sheetFrame = _frame;
    debugSheets += 1;
    if (ghostPerf) Perf.count('wisp.letters.sheets');
  }

  /// How many of the screen's pixels one of a letter's on the sheet covers each way, by its blur in the screen's
  /// pixels: a letter about to be blurred by six of them loses nothing drawn at a quarter of the size.
  static int _stepOf(double sigma) => wispSmallStep(sigma);

  /// Lets the sheet go: a test ended, or the faces changed.
  void clear() {
    _sheet?.dispose();
    _sheet = null;
    _places = const {};
    for (final ask in _asked.values) {
      ask?.glyph.dispose();
    }
    _asked.clear();
    _frame = const Duration(days: -1);
    _frameBefore = const Duration(days: -2);
    debugSheets = 0;
    debugLaid = 0;
  }
}

/// A letter as the sheet knows it: its picture (the very one, not one like it), where that lies, its box, which
/// noise bends it, and where on its page the noise is laid from (nowhere: from the letter's own corner).
@immutable
class _Letter {
  const _Letter(this.glyph, this.glyphRect, this.box, this.seed, this.at);
  final ui.Image glyph;
  final Rect glyphRect;
  final Size box;
  final int seed;
  final Offset at;

  @override
  bool operator ==(Object other) =>
      other is _Letter && identical(other.glyph, glyph) && other.glyphRect == glyphRect && other.box == box && other.seed == seed && other.at == at;

  @override
  int get hashCode => Object.hash(identityHashCode(glyph), glyphRect, box, seed, at);
}

class _Ask {
  _Ask(this.glyph, this.glyphRect, this.box, this.smoke, this.table, this.ratio, this.at);

  /// A hold of its own on the letter's picture, kept until the sheet is drawn.
  final ui.Image glyph;
  final Rect glyphRect;
  final Size box;
  final WispSmoke smoke;
  final ui.Image table;
  final double ratio;
  final Offset at;
}

class _Place {
  const _Place(this.from, this.over, this.smoke, this.texel, this.step);

  /// Where the letter is on the sheet, in the sheet's pixels, and what that covers round the letter's own corner.
  final Rect from, over;
  final WispSmoke smoke;

  /// One of the sheet's pixels there, in the letter's, and how many of the screen's it covers each way.
  final double texel;
  final int step;
}

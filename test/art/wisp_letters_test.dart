import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/wisp_kit.dart';
import 'package:ghost_md/art/wisp_letters.dart';
import 'package:ghost_md/art/wisp_settings.dart';
import 'package:ghost_md/art/wisp_text.dart';

import 'support/pictures.dart';

/// The sheet every letter in smoke is laid down from (lib/art/wisp_letters.dart), held to each letter drawn by
/// itself through a layer and a blur of its own: a spoiler's worth of letters, each in one of twelve smokes that
/// breathe as the editor's do (lib/editor/marks/wisp_format.dart `smokePose`), on frames that follow one another.
///
/// `build/smoke-compare/letters.png` has the letters drawn by themselves, the same from the sheet, and their
/// difference four times brighter; that picture is what was looked at.
const _ratio = 2.625;
const _size = Size(390, 150);

/// A slot's smoke at a time, as the editor poses a spoiler's.
({WispSmoke smoke, double lift, double shown}) _pose(int slot, double t) {
  final phase = slot * 0.83;
  return (
    smoke: WispSmoke.flat(
      seed: slot * 11 + 3,
      frequency: Offset(0.02 + 0.006 * math.sin(t * 0.7 + phase), 0.07 + 0.02 * math.sin(t * 0.5 + phase * 1.3)),
      bend: 36 + 14 * math.sin(t * 1.9 + phase),
      blur: 3.2 + 1.3 * math.sin(t * 1.4 + phase * 1.7),
    ),
    lift: 3 * math.sin(t * 1.1 + phase * 2.3),
    shown: 0.7 + 0.25 * math.sin(t * 2.6 + phase * 3.1),
  );
}

class _Glyph {
  _Glyph(String letter, TextStyle style) : painter = TextPainter(text: TextSpan(text: letter, style: style), textDirection: TextDirection.ltr)..layout() {
    final pad = (painter.preferredLineHeight * 0.3).ceilToDouble();
    final rect = Rect.fromLTWH(-pad, -pad, painter.width + 2 * pad, painter.height + 2 * pad);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_ratio);
    painter.paint(canvas, Offset(pad, pad));
    final picture = recorder.endRecording();
    final w = (rect.width * _ratio).ceil(), h = (rect.height * _ratio).ceil();
    image = picture.toImageSync(w, h);
    picture.dispose();
    imageRect = Rect.fromLTWH(rect.left, rect.top, w / _ratio, h / _ratio);
  }

  final TextPainter painter;
  late final ui.Image image;
  late final Rect imageRect;
}

/// The time the smokes are posed at; setting it draws the line again, whether or not it moved on.
class _Clock extends ChangeNotifier {
  double value = 0;
  void at(double time) {
    value = time;
    notifyListeners();
  }
}

class _Line extends CustomPainter {
  _Line(this.glyphs, this.time) : super(repaint: time);
  final List<_Glyph?> glyphs;
  final _Clock time;

  @override
  void paint(Canvas canvas, Size size) {
    final kit = WispKit.maybe!;
    var x = 24.0, y = 30.0, n = 0;
    for (final glyph in glyphs) {
      if (glyph == null) {
        x += 5;
        continue;
      }
      if (x + glyph.painter.width > size.width - 24) {
        x = 24;
        y += 44;
      }
      final slot = n++ % 12;
      final pose = _pose(slot, time.value);
      canvas.save();
      canvas.translate(x, y + pose.lift);
      paintWispLetter(
        canvas,
        kit: kit,
        table: kit.tableNow(slot * 11 + 3)!,
        glyph: glyph.image,
        glyphRect: glyph.imageRect,
        box: Size(glyph.painter.width, glyph.painter.height),
        smoke: pose.smoke,
        opacity: pose.shown,
      );
      canvas.restore();
      x += glyph.painter.width;
    }
  }

  @override
  bool shouldRepaint(_Line old) => true;
}

Future<void> _fonts() async {
  final loader = FontLoader('Inter Variable');
  loader.addFont(File('assets/fonts/InterVariable-latin.ttf').readAsBytes().then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  setUpAll(_fonts);
  tearDown(() {
    debugWispQuick = null;
    WispLetterSheet.instance.clear();
  });

  testWidgets('letters in smoke are laid down from one sheet while frames follow one another, and look as they did', (tester) async {
    tester.view.devicePixelRatio = _ratio;
    tester.view.physicalSize = _size * _ratio;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => WispKit.load(seeds: [for (var slot = 0; slot < 12; slot++) slot * 11 + 3]));
    const style = TextStyle(fontFamily: 'Inter Variable', fontSize: 16, height: 1.5, color: Color(0xFFE8E6E3));
    final glyphs = [
      for (final letter in 'the key is under the third stone, and The Answer Is forty-two'.split('')) letter == ' ' ? null : _Glyph(letter, style),
    ];
    final time = _Clock();
    final key = GlobalKey();
    final sheet = WispLetterSheet.instance;
    Future<void> show() => tester.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: key, child: ColoredBox(color: const Color(0xFF0D0D0D), child: CustomPaint(size: _size, painter: _Line(glyphs, time)))),
          ),
        );

    // Each letter by itself, at the time the sheet's picture will be of.
    const frame = Duration(milliseconds: 16);
    const steps = 6;
    debugWispQuick = false;
    time.at((steps - 1) * 0.016);
    await show();
    final alone = await capture(tester, key, ratio: _ratio);
    expect(sheet.debugSheets, 0);

    // The same frames from the start with the sheet: the first two draw each letter by itself (nothing is known
    // of the first, and nothing says a second will follow), and the rest are laid down from it.
    debugWispQuick = true;
    time.at(0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await show();
    expect(sheet.debugLaid, 0, reason: 'nothing is on a sheet in the first frame');
    final letters = glyphs.whereType<_Glyph>().length;
    for (var step = 1; step <= steps; step++) {
      final laid = sheet.debugLaid;
      // The last frame asks for the smoke the one before it did: the sheet it is laid from is of that very smoke.
      time.at(math.min(step, steps - 1) * 0.016);
      await tester.pump(frame);
      if (step >= 2) expect(sheet.debugLaid - laid, letters, reason: 'frame $step lays every letter down from the sheet');
    }
    // Every frame that asked for a new smoke drew the sheet again, once: one sheet a frame, not a layer and a blur
    // a letter. The last asked for nothing new, and the sheet stood.
    expect(sheet.debugSheets, steps - 1);
    final laid = await capture(tester, key, ratio: _ratio);

    // A page that stood still draws its next frame letter by letter: the sheet is what the letters were.
    final before = sheet.debugLaid;
    time.at(1.0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(sheet.debugLaid, before);

    await tester.runAsync(() async {
      final score = apart(alone, laid);
      await writePng('build/smoke-compare/letters.png', _stacked([alone, laid, difference(alone, laid)]));
      // ignore: avoid_print
      print('letters, each alone against the sheet: $score');
      // Both blur the same bent letters, one by the engine's blur and one by the sheet's own.
      expect(score.mean, lessThan(1.2));
    });
  });
}

Pixels _stacked(List<Pixels> pictures, {int gap = 6}) {
  final width = pictures.first.width;
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

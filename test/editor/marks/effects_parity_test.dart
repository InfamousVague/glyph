// Heat and frost held to the page's own filters, drawn by Chromium.
//
// tool/editor_reference.mjs drew the marks' note in the web app itself with its clock held at 0, 0.7 and 1.9
// seconds (fixtures/marks-at-*.png, two pixels to the CSS one, with every mark's box beside them in the .json):
// the heated words, the two lines of text above them through the haze, and the frosted word are there as the
// page's `<filter>`s leave them (src/app/editor/textEffects.ts `heat`, `frost`). Here the same note is drawn with
// the marks' clock held at the same moments, and each of those four stretches is cut out of both pictures, with
// the room its filter may paint in, and compared.
//
// A number here is a guard, not a judgement (a texture can score alike and look nothing alike): each case writes
// build/smoke-compare/effects/<name>-<stretch>.png, the page's, this one, and their difference four times
// brighter, four times its size, and those are what was looked at. To keep the numbers honest, each stretch is
// also drawn wrong on purpose (its noise laid from where the letter stands on the canvas, which is how the port
// first drew it, a field that is not the page's) and must score worse; and a word with no effect on it is scored
// too, which is what the two engines' own lettering differs by.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/wisp_settings.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/state/state.dart' show Extension;

import '../../support/render.dart';
import 'support.dart';

typedef _Pixels = ({int width, int height, Uint8List data});

Future<_Pixels> _decode(WidgetTester tester, String path) async => (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      return (width: image.width, height: image.height, data: data!.buffer.asUint8List());
    }))!;

Future<_Pixels> _capture(WidgetTester tester) async {
  final boundary = tester.allRenderObjects.whereType<RenderRepaintBoundary>().first;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return (width: image.width, height: image.height, data: data!.buffer.asUint8List());
  }))!;
}

_Pixels _crop(_Pixels from, Rect box) {
  final left = box.left.floor().clamp(0, from.width - 1), top = box.top.floor().clamp(0, from.height - 1);
  final wide = (box.right.ceil().clamp(left + 1, from.width) - left).toInt(), tall = (box.bottom.ceil().clamp(top + 1, from.height) - top).toInt();
  final out = Uint8List(wide * tall * 4);
  for (var y = 0; y < tall; y++) {
    out.setRange(y * wide * 4, (y + 1) * wide * 4, from.data, ((top + y) * from.width + left) * 4);
  }
  return (width: wide, height: tall, data: out);
}

double _apart(_Pixels a, _Pixels b) {
  var total = 0;
  for (var i = 0; i < a.data.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      total += (a.data[i + c] - b.data[i + c]).abs();
    }
  }
  return total / (a.data.length / 4 * 3);
}

/// The page's, this one and their difference four times brighter, one above the next, four times their size.
Future<void> _write(WidgetTester tester, String name, _Pixels web, _Pixels mine) async {
  const by = 4, gap = 4;
  final wide = web.width * by, tall = (web.height * by + gap) * 3 - gap;
  final out = Uint8List(wide * tall * 4);
  for (var i = 0; i < out.length; i += 4) {
    out[i] = 255;
    out[i + 2] = 255;
    out[i + 3] = 255;
  }
  for (var part = 0; part < 3; part++) {
    for (var y = 0; y < web.height * by; y++) {
      for (var x = 0; x < wide; x++) {
        final from = ((y ~/ by) * web.width + x ~/ by) * 4, to = ((part * (web.height * by + gap) + y) * wide + x) * 4;
        for (var c = 0; c < 3; c++) {
          final w = web.data[from + c], m = mine.data[from + c];
          out[to + c] = part == 0 ? w : (part == 1 ? m : ((w - m).abs() * 4).clamp(0, 255));
        }
        out[to + 3] = 255;
      }
    }
  }
  await tester.runAsync(() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(out);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: wide, height: tall, pixelFormat: ui.PixelFormat.rgba8888);
    final image = (await (await descriptor.instantiateCodec()).getNextFrame()).image;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/smoke-compare/effects/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// The most each stretch's mean difference from the page's may be, of 255: about half as much again as each
/// measured when the pictures were last looked at (the haze over the second line up 2.7 to 2.9, over the first
/// 1.8 to 1.9, the heated words 2.5 to 2.7, the frost 1.0 to 1.7; a word with no effect on it 0.07, and what is
/// left is the edge of a letter's own picture falling half a pixel from the page's). Drawn wrong they are 8 to 9,
/// 11 to 13, 4.3 to 5.3 and 4.5 to 10.
///
/// The frost at rest has its rime at its whole reach, three of the picture's pixels of specks where a moving one at
/// these moments has one, and is 3.6 from the page's (6.4 drawn wrong): the same crystals to the eye, and a grain
/// that turns over in under two pixels shows every quarter of a pixel between the two engines' lines.
const Map<String, double> _limits = <String, double>{'haze-55': 4.2, 'haze-100': 2.9, 'heat': 3.8, 'frost': 2.6, 'frost at rest': 4.6};

void main() {
  setUpAll(loadAppFonts);
  tearDown(() {
    debugEffectAnchor = 0;
    debugWispQuick = null;
  });

  // Four moments of the motion, and the picture the page drew with reduced motion asked for: the filters at rest
  // (the heat's noise at its low frequency and first seed, the rime at its whole reach).
  for (final (name, still) in const <(String, bool)>[('marks-dark-at-0', false), ('marks-at-0', false), ('marks-at-0_7', false), ('marks-at-1_9', false), ('marks-formatted', true)]) {
    testWidgets('$name: the heat, its haze and the frost beside the page\'s own', (tester) async {
      final fixture = Measured.read('marks', name);
      MarkClock.hold = ((fixture.json['at'] ?? 0) as num).toDouble();
      addTearDown(() => MarkClock.hold = null);
      final web = await _decode(tester, 'test/editor/marks/fixtures/$name.png');

      // The stretches, by the page's own boxes: each with the room its filter paints in, in the picture's pixels.
      final stretches = <(String, Rect)>[];
      Rect? plain;
      for (final mark in (fixture.json['marks'] as List).cast<Map<String, dynamic>>()) {
        final effect = (mark['attrs'] as Map)['data-effect'] as String?;
        final classes = (mark['classes'] as List).cast<String>();
        final r = (mark['rects'] as List).first as Map<String, dynamic>;
        final box = Rect.fromLTRB((r['left'] as num).toDouble(), (r['top'] as num).toDouble(), (r['right'] as num).toDouble(), (r['bottom'] as num).toDouble());
        if (classes.contains('cm-effectLetter') || effect == null) continue;
        if (effect == 'heat' || effect == 'heat-above' || effect == 'frost') {
          final label = effect == 'heat-above' ? 'haze-${(mark['attrs'] as Map)['style'].toString().contains('-100') ? 100 : 55}' : effect;
          final room = Rect.fromLTRB(box.left - 0.1 * box.width, box.top - 0.4 * box.height, box.right + 0.1 * box.width, box.bottom + 0.4 * box.height);
          stretches.add((label, Rect.fromLTRB(room.left * 2, room.top * 2, room.right * 2, room.bottom * 2)));
          // The word after the frosted one, on its line: no effect on it.
          if (effect == 'frost') plain = Rect.fromLTRB((box.right + 8) * 2, box.top * 2, (box.right + 60) * 2, box.bottom * 2);
        }
      }
      expect(stretches.map((s) => s.$1).toSet(), {'heat', 'haze-55', 'haze-100', 'frost'});

      Future<_Pixels> drawn(int anchor) async {
        debugEffectAnchor = anchor;
        debugWispQuick = true;
        await pumpMeasured(tester, fixture, formats: marks, more: <Extension>[markExtensions(marks)], shaders: true, reducedMotion: still);
        // Frames far apart: each letter by its own layers (what a page that moves lays down is held to this by
        // effects_kept_test.dart), and painted more than once, so a stretch knows its own box.
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        final picture = await _capture(tester);
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        debugDisableShadows = false;
        return picture;
      }

      final mine = await drawn(0), wrong = await drawn(2);
      debugDisableShadows = true;
      // ignore: avoid_print
      print('$name: a word with no effect on it: ${_apart(_crop(web, plain!), _crop(mine, plain)).toStringAsFixed(2)}');
      for (final (label, box) in stretches) {
        final a = _crop(web, box);
        final score = _apart(a, _crop(mine, box)), off = _apart(a, _crop(wrong, box));
        await _write(tester, '$name-$label', a, _crop(mine, box));
        // ignore: avoid_print
        print('$name $label: ${score.toStringAsFixed(2)}   (drawn wrong, its noise from the canvas: ${off.toStringAsFixed(2)})');
        final limit = _limits[still && label == 'frost' ? 'frost at rest' : label];
        if (limit != null) {
          expect(score, lessThan(limit), reason: '$name $label has moved away from the page\'s picture');
          expect(off, greaterThan(score * 1.15), reason: '$name $label drawn wrong should be further from the page than drawn right');
        }
      }
    });
  }
}

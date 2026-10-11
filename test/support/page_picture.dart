// A picture of the app laid over the page's own picture of the same thing (a reference tool's .png, drawn by
// Chromium), and how far apart the two are, in numbers a wrong drawing moves.
//
// The mean difference of two pictures of text is small whatever is wrong with the rest: letters are most of what
// differs between two engines, and a ground a shade off, a corner left square, a seam between two lines or a box a
// pixel out are a few thousandths of the mean. So the ground is asked about by itself. A pixel is GROUND where the
// picture round it is one flat colour: nothing within [reach] pixels of it differs from its neighbour. Where
// either picture has ground, the other must have the same colour there to within [level] steps of 255; the pixels
// that do not are counted ([Laid.off]). Letters and edges are within [reach] of a change in both pictures, so a
// letter half a pixel from the page's is not counted, and a ground of another shade, a missing or an extra box, a
// line of text where the page has none, a square corner and a seam all are.
//
// A limit on either number is proven where it is set: the test that sets it draws the thing wrong on purpose once
// and shows the wrong drawing over it.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../art/support/pictures.dart';

export '../art/support/pictures.dart' show Pixels, capture, readPng, writePng;

/// Two pictures laid over one another.
class Laid {
  Laid({required this.mean, required this.ink, required this.inkWorst, required this.off, required this.ground, required this.pixels, required this.worstRun, required this.sizes});

  /// The mean difference of the three colours of every pixel, of 255. Mostly the two engines' letters: a line of
  /// sixty letters whose advances differ by a hundredth of a pixel has its last letters a third of a pixel along,
  /// and every edge of them another shade. To read, not to hold.
  final double mean;

  /// How much ink is where: both pictures blurred over [inkWindow] pixels each way (so a letter a pixel along is
  /// the same letter), and the mean difference of the three colours of that, of 255. Letters of another weight
  /// or another colour, words that are not there, and a thing drawn larger move it; a letter half a pixel from
  /// the page's does not.
  final double ink;

  /// The most that blurred difference comes to at any one place.
  final double inkWorst;

  /// Pixels that are ground in one picture and another colour in the other.
  final int off;

  /// Pixels that are ground in either picture.
  final int ground;
  final int pixels;

  /// The longest run of such pixels along one row or down one column: a seam or an edge out of place is long, a
  /// speck is not.
  final int worstRun;

  /// The two pictures' sizes, the page's first.
  final (int, int, int, int) sizes;

  /// The part of a thousand of the ground that is another colour.
  double get offPerMille => ground == 0 ? 0 : off * 1000 / ground;

  @override
  String toString() => 'ink ${ink.toStringAsFixed(3)} (worst ${inkWorst.toStringAsFixed(1)}), ground off $off of $ground, longest run $worstRun, mean ${mean.toStringAsFixed(2)}';
}

/// How far each way the ink is blurred, and how far apart it is asked about, in the picture's pixels.
const int inkWindow = 16, _inkStep = 8;

/// The sums of one colour of `p` over every rectangle from its corner: `(w + 1) * (h + 1)` of them.
Float64List _sums(Pixels p, int channel) {
  final w = p.width, h = p.height;
  final out = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0.0;
    for (var x = 0; x < w; x++) {
      row += p.data[(y * w + x) * 4 + channel];
      out[(y + 1) * (w + 1) + x + 1] = out[y * (w + 1) + x + 1] + row;
    }
  }
  return out;
}

(double, double) _ink(Pixels a, Pixels b) {
  final w = a.width, h = a.height;
  if (w < inkWindow || h < inkWindow) return (0, 0);
  var total = 0.0, worst = 0.0;
  var count = 0;
  final across = <int>[for (var x = 0; x + inkWindow <= w; x += _inkStep) x], down = <int>[for (var y = 0; y + inkWindow <= h; y += _inkStep) y];
  final each = List<double>.filled(across.length * down.length, 0);
  for (var c = 0; c < 3; c++) {
    final sa = _sums(a, c), sb = _sums(b, c);
    double over(Float64List s, int x, int y) => s[(y + inkWindow) * (w + 1) + x + inkWindow] - s[y * (w + 1) + x + inkWindow] - s[(y + inkWindow) * (w + 1) + x] + s[y * (w + 1) + x];
    var n = 0;
    for (final y in down) {
      for (final x in across) {
        final d = (over(sa, x, y) - over(sb, x, y)).abs() / (inkWindow * inkWindow);
        total += d;
        if (d > each[n]) each[n] = d;
        n++;
      }
    }
    count += n;
  }
  for (final d in each) {
    if (d > worst) worst = d;
  }
  return (count == 0 ? 0 : total / count, worst);
}

/// Where a picture is not flat: a pixel that differs from the one after it or the one under it, spread [reach]
/// pixels every way.
Uint8List _busy(Pixels p, int reach) {
  final w = p.width, h = p.height, d = p.data;
  final edge = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      var differs = false;
      if (x + 1 < w) {
        final j = i + 4;
        if ((d[i] - d[j]).abs() > 1 || (d[i + 1] - d[j + 1]).abs() > 1 || (d[i + 2] - d[j + 2]).abs() > 1) differs = true;
      }
      if (!differs && y + 1 < h) {
        final j = i + w * 4;
        if ((d[i] - d[j]).abs() > 1 || (d[i + 1] - d[j + 1]).abs() > 1 || (d[i + 2] - d[j + 2]).abs() > 1) differs = true;
      }
      if (differs) {
        edge[y * w + x] = 1;
        if (x + 1 < w) edge[y * w + x + 1] = 1;
        if (y + 1 < h) edge[(y + 1) * w + x] = 1;
      }
    }
  }
  // Spread along the rows, then down the columns.
  final across = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    var last = -1 << 20;
    for (var x = 0; x < w; x++) {
      if (edge[y * w + x] == 1) last = x;
      if (x - last <= reach) across[y * w + x] = 1;
    }
    last = 1 << 20;
    for (var x = w - 1; x >= 0; x--) {
      if (edge[y * w + x] == 1) last = x;
      if (last - x <= reach) across[y * w + x] = 1;
    }
  }
  final out = Uint8List(w * h);
  for (var x = 0; x < w; x++) {
    var last = -1 << 20;
    for (var y = 0; y < h; y++) {
      if (across[y * w + x] == 1) last = y;
      if (y - last <= reach) out[y * w + x] = 1;
    }
    last = 1 << 20;
    for (var y = h - 1; y >= 0; y--) {
      if (across[y * w + x] == 1) last = y;
      if (last - y <= reach) out[y * w + x] = 1;
    }
  }
  return out;
}

/// [mine] laid over [page]. Both are cut to the part they share, from the top left; their sizes are in the answer,
/// for the test to hold.
///
/// [mask], when given, is filled with where the ground is off, for a picture of it.
Laid lay(Pixels page, Pixels mine, {int reach = 3, int level = 3, Uint8List? mask}) {
  final w = math.min(page.width, mine.width), h = math.min(page.height, mine.height);
  final a = page.width == w && page.height == h ? page : page.crop(0, 0, w, h);
  final b = mine.width == w && mine.height == h ? mine : mine.crop(0, 0, w, h);
  final busyA = _busy(a, reach), busyB = _busy(b, reach);
  var total = 0, off = 0, ground = 0;
  final wrong = mask ?? Uint8List(w * h);
  for (var n = 0; n < w * h; n++) {
    final i = n * 4;
    final dr = (a.data[i] - b.data[i]).abs(), dg = (a.data[i + 1] - b.data[i + 1]).abs(), db = (a.data[i + 2] - b.data[i + 2]).abs();
    total += dr + dg + db;
    if (busyA[n] == 1 && busyB[n] == 1) continue;
    ground += 1;
    if (dr > level || dg > level || db > level) {
      off += 1;
      wrong[n] = 1;
    }
  }
  var worst = 0;
  for (var y = 0; y < h; y++) {
    var run = 0;
    for (var x = 0; x < w; x++) {
      run = wrong[y * w + x] == 1 ? run + 1 : 0;
      if (run > worst) worst = run;
    }
  }
  for (var x = 0; x < w; x++) {
    var run = 0;
    for (var y = 0; y < h; y++) {
      run = wrong[y * w + x] == 1 ? run + 1 : 0;
      if (run > worst) worst = run;
    }
  }
  final (ink, inkWorst) = _ink(a, b);
  return Laid(mean: total / (w * h * 3), ink: ink, inkWorst: inkWorst, off: off, ground: ground, pixels: w * h, worstRun: worst, sizes: (page.width, page.height, mine.width, mine.height));
}

/// The page's picture, this one, and where they differ (four times brighter, with the ground that is off in red),
/// side by side, written to [path] for looking at.
Future<void> writeLaid(WidgetTester tester, String path, Pixels page, Pixels mine, {int reach = 3, int level = 3}) async {
  final w = math.min(page.width, mine.width), h = math.min(page.height, mine.height);
  final a = page.crop(0, 0, w, h), b = mine.crop(0, 0, w, h);
  final mask = Uint8List(w * h);
  lay(a, b, reach: reach, level: level, mask: mask);
  const gap = 8;
  final wide = w * 3 + gap * 2;
  final out = Uint8List(wide * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < wide; x++) {
      final to = (y * wide + x) * 4;
      final part = x ~/ (w + gap), px = x - part * (w + gap);
      if (px >= w) {
        out[to] = 255;
        out[to + 2] = 255;
        out[to + 3] = 255;
        continue;
      }
      final from = (y * w + px) * 4;
      for (var c = 0; c < 3; c++) {
        out[to + c] = part == 0 ? a.data[from + c] : (part == 1 ? b.data[from + c] : math.min(255, (a.data[from + c] - b.data[from + c]).abs() * 4));
      }
      if (part == 2 && mask[y * w + px] == 1) {
        out[to] = 255;
        out[to + 1] = 0;
        out[to + 2] = 0;
      }
      out[to + 3] = 255;
    }
  }
  await tester.runAsync(() async {
    File(path).parent.createSync(recursive: true);
    await writePng(path, Pixels(wide, h, out));
  });
}

/// The page's picture at [path], read off the test's clock.
Future<Pixels> pagePicture(WidgetTester tester, String path) async => (await tester.runAsync(() => readPng(path)))!;

/// What is under [key]'s boundary, as the page's picture is: at two pixels to the logical one, on [ground].
Future<Pixels> ownPicture(WidgetTester tester, GlobalKey key, {double ratio = 2}) => capture(tester, key, ratio: ratio);

// Where the ink of a picture is, row by row: for the tests that hold words to the rows of pixels the page's own
// picture has them on (test/editor/view/ink_rows_test.dart, and its like beside the tables').
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';

/// A picture as its pixels.
class Pixels {
  Pixels(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;

  static Future<Pixels> of(WidgetTester tester, Future<ui.Image> Function() make) async => (await tester.runAsync(() async {
        final image = await make();
        final data = await image.toByteData();
        final pixels = Pixels(image.width, image.height, data!.buffer.asUint8List());
        image.dispose();
        return pixels;
      }))!;

  static Future<Pixels> file(WidgetTester tester, String path) => of(tester, () async {
        final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
        return (await codec.getNextFrame()).image;
      });

  /// The screen as it is drawn now, `across` pixels wide (780 for a picture at two device pixels to one of a
  /// screen 390 wide), whatever the screen's own are.
  static Future<Pixels> screen(WidgetTester tester, {int across = 780}) {
    RenderObject boundary = find.byType(GhostApp).evaluate().single.renderObject!;
    while (!boundary.isRepaintBoundary) {
      boundary = boundary.parent!;
    }
    final layer = boundary.debugLayer! as OffsetLayer;
    // The window's own layer is in device pixels already; any other is in logical ones.
    final bounds = boundary.paintBounds;
    return of(tester, () => layer.toImage(bounds, pixelRatio: across / bounds.width));
  }

  /// The ink on one row, by the row's own ground: how much of it, and on how many pixels across.
  ({double mass, int across}) inkOfRow(int y) {
    final counts = <int, int>{};
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final colour = rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
      counts[colour] = (counts[colour] ?? 0) + 1;
    }
    var ground = 0, most = -1;
    counts.forEach((colour, n) {
      if (n > most) {
        most = n;
        ground = colour;
      }
    });
    final gr = ground >> 16, gg = ground >> 8 & 255, gb = ground & 255;
    var mass = 0.0, across = 0;
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final far = ((rgba[i] - gr).abs() + (rgba[i + 1] - gg).abs() + (rgba[i + 2] - gb).abs()) / 3 / 128;
      if (far > 0.2) across += 1;
      mass += far > 1 ? 1 : far;
    }
    return (mass: mass, across: across);
  }

  /// How much ink is on each row from `top` to `bottom`: for every pixel of the row, how far it is from the
  /// row's own ground (its commonest colour), from none to one. A column inked on nearly every row is a rule down
  /// the line (a quote's bar), not words, and is left out.
  List<double> ink(int top, int bottom) {
    final rows = bottom - top;
    final per = List<Float64List>.generate(rows, (_) => Float64List(width));
    for (var r = 0; r < rows; r++) {
      final y = top + r;
      if (y < 0 || y >= height) continue;
      final counts = <int, int>{};
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final colour = rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
        counts[colour] = (counts[colour] ?? 0) + 1;
      }
      var ground = 0, most = -1;
      counts.forEach((colour, n) {
        if (n > most) {
          most = n;
          ground = colour;
        }
      });
      final gr = ground >> 16, gg = ground >> 8 & 255, gb = ground & 255;
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final far = ((rgba[i] - gr).abs() + (rgba[i + 1] - gg).abs() + (rgba[i + 2] - gb).abs()) / 3 / 128;
        per[r][x] = far > 1 ? 1 : far;
      }
    }
    final ruled = List<bool>.filled(width, false);
    if (rows >= 8) {
      for (var x = 0; x < width; x++) {
        var inked = 0;
        for (var r = 0; r < rows; r++) {
          if (per[r][x] > 0.2) inked += 1;
        }
        ruled[x] = inked >= rows * 0.9;
      }
    }
    return <double>[
      for (var r = 0; r < rows; r++)
        () {
          var sum = 0.0;
          for (var x = 0; x < width; x++) {
            if (!ruled[x]) sum += per[r][x];
          }
          return sum;
        }(),
    ];
  }
}

/// Where a line's ink is: its first and last rows (those with a twentieth of its heaviest row's ink or more), and
/// the row its weight is centred on. Null for a line with no ink.
({int first, int last, double centre})? inked(List<double> rows, int top) {
  var most = 0.0, sum = 0.0, weighted = 0.0;
  for (final row in rows) {
    if (row > most) most = row;
  }
  if (most < 0.5) return null;
  var first = -1, last = -1;
  for (var r = 0; r < rows.length; r++) {
    sum += rows[r];
    weighted += rows[r] * (r + 0.5);
    if (rows[r] >= most / 20) {
      if (first < 0) first = r;
      last = r;
    }
  }
  return (first: top + first, last: top + last, centre: top + weighted / sum);
}

/// The bands of rows a picture's words are on, from `top` to `bottom`: each run of rows with ink on them, a rule
/// across the picture (a row inked along more than half its width: a table's border) left out, and a band less
/// than three rows tall with it (a dot, a dash).
List<({int first, int last})> bands(Pixels picture, int top, int bottom) {
  final found = <({int first, int last})>[];
  int? began;
  for (var y = top; y <= bottom; y++) {
    var inkedHere = false;
    if (y < bottom && y < picture.height) {
      final row = picture.inkOfRow(y);
      inkedHere = row.mass >= 0.5 && row.across <= picture.width / 2;
    }
    if (inkedHere) {
      began ??= y;
    } else if (began != null) {
      if (y - began >= 3) found.add((first: began, last: y - 1));
      began = null;
    }
  }
  return found;
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A picture as plain pixels: red, green, blue and alpha, the colour not multiplied by the alpha.
class Pixels {
  Pixels(this.width, this.height, this.data);
  final int width, height;
  final Uint8List data;

  /// The picture laid on a ground of [ground], as the eye sees it on the page.
  Pixels on(int ground) {
    final out = Uint8List(data.length);
    final g = [(ground >> 16) & 0xff, (ground >> 8) & 0xff, ground & 0xff];
    for (var i = 0; i < data.length; i += 4) {
      final a = data[i + 3] / 255;
      for (var c = 0; c < 3; c++) {
        out[i + c] = (data[i + c] * a + g[c] * (1 - a)).round();
      }
      out[i + 3] = 255;
    }
    return Pixels(width, height, out);
  }

  Pixels crop(int left, int top, int w, int h) {
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      out.setRange(y * w * 4, (y + 1) * w * 4, data, ((top + y) * width + left) * 4);
    }
    return Pixels(w, h, out);
  }
}

Future<ui.Image> decodePng(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<Pixels> pixelsOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return Pixels(image.width, image.height, data!.buffer.asUint8List());
}

Future<Pixels> readPng(String path) async => pixelsOf(await decodePng(path));

Future<void> writePng(String path, Pixels pixels) async {
  final done = await _image(pixels);
  final png = await done.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

/// [pixels] as an image the engine can draw.
Future<ui.Image> imageOf(Pixels pixels) => _image(pixels);

Future<ui.Image> _image(Pixels pixels) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels.data);
  final descriptor = ui.ImageDescriptor.raw(buffer, width: pixels.width, height: pixels.height, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  return (await codec.getNextFrame()).image;
}

/// What is under [key]'s boundary, at [ratio] pixels to the logical one.
Future<Pixels> capture(WidgetTester tester, GlobalKey key, {double ratio = 2}) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async => pixelsOf(await boundary.toImage(pixelRatio: ratio))))!;
}

/// How far two pictures are apart: the mean and the 99th centile of the difference of their channels, of 255.
class Apart {
  Apart(this.mean, this.high, this.worst);
  final double mean;
  final int high, worst;

  @override
  String toString() => 'mean ${mean.toStringAsFixed(2)}, 99% under $high, worst $worst';
}

Apart apart(Pixels a, Pixels b) {
  expect((a.width, a.height), (b.width, b.height));
  final counts = List<int>.filled(256, 0);
  var total = 0;
  for (var i = 0; i < a.data.length; i++) {
    final d = (a.data[i] - b.data[i]).abs();
    counts[d]++;
    total += d;
  }
  var seen = 0, high = 0, worst = 0;
  for (var d = 0; d < 256; d++) {
    if (counts[d] > 0) worst = d;
    seen += counts[d];
    if (seen <= a.data.length * 0.99) high = d + 1;
  }
  return Apart(total / a.data.length, math.min(high, 255), worst);
}

/// [pictures] side by side with a gap between, for looking at.
Pixels beside(List<Pixels> pictures, {int gap = 8, int ground = 0xff00ff}) {
  final height = pictures.map((p) => p.height).reduce(math.max);
  final width = pictures.fold<int>(0, (sum, p) => sum + p.width) + gap * (pictures.length - 1);
  final out = Uint8List(width * height * 4);
  for (var i = 0; i < out.length; i += 4) {
    out[i] = (ground >> 16) & 0xff;
    out[i + 1] = (ground >> 8) & 0xff;
    out[i + 2] = ground & 0xff;
    out[i + 3] = 255;
  }
  var x = 0;
  for (final p in pictures) {
    for (var y = 0; y < p.height; y++) {
      out.setRange((y * width + x) * 4, (y * width + x + p.width) * 4, p.data, y * p.width * 4);
    }
    x += p.width + gap;
  }
  return Pixels(width, height, out);
}

/// Where two pictures differ, brightened four times so a small difference can be seen.
Pixels difference(Pixels a, Pixels b) {
  final out = Uint8List(a.data.length);
  for (var i = 0; i < a.data.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      out[i + c] = math.min(255, (a.data[i + c] - b.data[i + c]).abs() * 4);
    }
    out[i + 3] = 255;
  }
  return Pixels(a.width, a.height, out);
}

/// Where the screen is over the canvas: the world's offset in screen pixels and its scale. A point of the canvas at
/// (px, py) is on the screen at (px * scale + x, py * scale + y). A port of `src/app/canvas/viewport.ts`, pure.
library;

import 'dart:math' as math;

import 'geometry.dart';
import 'json_canvas.dart';

class CameraView {
  const CameraView({required this.x, required this.y, required this.scale});
  final double x;
  final double y;
  final double scale;

  CameraView copyWith({double? x, double? y, double? scale}) => CameraView(x: x ?? this.x, y: y ?? this.y, scale: scale ?? this.scale);

  @override
  bool operator ==(Object other) => other is CameraView && other.x == x && other.y == y && other.scale == scale;

  @override
  int get hashCode => Object.hash(x, y, scale);

  @override
  String toString() => 'CameraView(x: $x, y: $y, scale: $scale)';
}

const double _minScale = 0.1;
const double _maxScale = 3;

/// Room around the whole canvas when it is fitted to the screen, in screen pixels.
const double _fitRoom = 32;

/// The view before there is anything to fit, or a screen to fit it in: room at the top left, life size (`HOME`).
const CameraView home = CameraView(x: _fitRoom, y: _fitRoom, scale: 1);

/// A scale no smaller than a tenth of life and no larger than three times.
double clampScale(double scale) => math.min(_maxScale, math.max(_minScale, scale));

/// The view that shows the whole canvas in a screen this big, centred, no larger than life.
CameraView fitted(Canvas canvas, double width, double height) {
  final box = bounds(canvas);
  return box == null ? home : fittedTo(box, width, height);
}

/// The view with the point of the canvas that was under (px, py) still under it at [scale].
CameraView zoomedAt(CameraView view, double px, double py, double scale) {
  final next = clampScale(scale);
  return CameraView(x: px - ((px - view.x) / view.scale) * next, y: py - ((py - view.y) / view.scale) * next, scale: next);
}

/// The view that shows this box in a screen this big, centred, no larger than life: zoom-to-card (choice 10).
CameraView fittedTo(Box box, double width, double height) {
  if (width <= 0 || height <= 0) return home;
  final scale = clampScale(math.min(math.min((width - _fitRoom * 2) / math.max(box.width, 1), (height - _fitRoom * 2) / math.max(box.height, 1)), 1));
  return CameraView(x: (width - box.width * scale) / 2 - box.x * scale, y: (height - box.height * scale) / 2 - box.y * scale, scale: scale);
}

/// The part of the canvas the screen shows, in the canvas's own pixels: what the minimap draws as the viewport.
BoxOf shown(CameraView view, double width, double height) => BoxOf(-view.x / view.scale, -view.y / view.scale, width / view.scale, height / view.scale);

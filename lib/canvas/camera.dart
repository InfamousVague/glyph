/// Where the screen is over a canvas, and what moves it: a port of `src/app/canvas/camera.ts`.
///
/// On the web the view is written straight to the world element as a transform and to the page as the three
/// variables the dot grid is drawn from, so a pan is a style change and nothing re-renders. Here the camera is a
/// [ChangeNotifier] that the world (world.dart), the dots and the minimap listen to and read when they paint, so a
/// pan is a repaint and no widget is built again.
///
/// The canvas opens fitted to the screen and follows the screen's size until a hand has moved the view: a finger,
/// a wheel, the minimap or a zoom to a card. A wheel pans, as it does in Obsidian; with ctrl or meta held it zooms
/// about the pointer.
///
/// What differs:
/// - The screen's size is told to the camera by the view's layout ([resized]) where the web watched the element
///   (`ResizeObserver`).
/// - `shown`, the view copied once a frame for what React drew from it, is not here: everything reads [view].
/// - A trackpad's pinch arrives on the web as a wheel with ctrl held; Flutter hands a trackpad's two fingers over
///   as a pan-zoom gesture of its own, which gestures.dart turns into the same moves ([wheel] is the mouse's).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'geometry.dart';
import 'json_canvas.dart';
import 'viewport.dart';

class CanvasCamera extends ChangeNotifier {
  CanvasCamera(Canvas opened) : _opened = opened;

  Canvas _opened;
  CameraView _view = home;
  double _width = 0;
  double _height = 0;

  /// Whether a finger or a wheel has moved the view: until then, a screen that changes size fits the canvas again.
  bool _touched = false;

  /// The view now.
  CameraView get view => _view;

  /// The screen's size, as the canvas was last laid out.
  double get width => _width;
  double get height => _height;
  bool get touched => _touched;

  void _apply(CameraView next) {
    if (next == _view) return;
    _view = next;
    notifyListeners();
  }

  /// The canvas as it opened, or as the note reloaded it: fitted again.
  void open(Canvas canvas) {
    _opened = canvas;
    fit();
  }

  /// The whole canvas fitted to the screen, and the view following the screen's size again.
  void fit() {
    _touched = false;
    _apply(fitted(_opened, _width, _height));
  }

  /// The screen has this size: fitted again unless a hand has moved the view. Called from layout: the world
  /// paints after it is laid out and reads the view then, and the listeners are told after the frame.
  void resized(double width, double height) {
    if (width == _width && height == _height) return;
    _width = width;
    _height = height;
    if (_touched) return;
    final next = fitted(_opened, width, height);
    if (next == _view) return;
    _view = next;
    // Told once the frame is done, for what is built from the view rather than painted from it.
    scheduleMicrotask(() {
      if (!_gone) notifyListeners();
    });
  }

  bool _gone = false;

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }

  /// The view moved by hand to [next]: drawn at once, and no longer refitted when the screen changes size.
  void moveTo(CameraView next) {
    _touched = true;
    _apply(next);
  }

  /// The view fitted to one box of the canvas, no larger than life: zoom to a card.
  void zoomToBox(Box box) => moveTo(fittedTo(box, _width, _height));

  /// The screen centred on this point of the canvas, at the scale it is at: a tap on the minimap.
  void centreOn(Point point) => moveTo(CameraView(x: _width / 2 - point.x * _view.scale, y: _height / 2 - point.y * _view.scale, scale: _view.scale));

  /// The screen moved this far over the canvas, in the canvas's own pixels: a drag on the minimap.
  void panBy(double dx, double dy) => moveTo(CameraView(x: _view.x - dx * _view.scale, y: _view.y - dy * _view.scale, scale: _view.scale));

  /// The view this many times closer, or further for a number under one, about the middle of the screen.
  void zoomBy(double times) => moveTo(zoomedAt(_view, _width / 2, _height / 2, _view.scale * times));

  /// A wheel: it pans; with the modifier held it zooms about the pointer, at (x, y) of the canvas's own box.
  void wheel(double deltaX, double deltaY, {required double x, required double y, required bool zoom}) {
    if (zoom) {
      moveTo(zoomedAt(_view, x, y, _view.scale * math.exp(-deltaY * 0.01)));
    } else {
      moveTo(CameraView(x: _view.x - deltaX, y: _view.y - deltaY, scale: _view.scale));
    }
  }

  /// The point of the canvas under a point of the canvas's own box.
  Point under(double x, double y) => (x: (x - _view.x) / _view.scale, y: (y - _view.y) / _view.scale);

  /// The middle of the screen, in the canvas's pixels.
  Point middle() => under(_width / 2, _height / 2);
}

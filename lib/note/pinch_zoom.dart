/// Pinch a note's text larger or smaller (Matt: "add pinch to zoom text larger and smaller on notes"). A port of
/// `src/app/editor/pinchZoom.ts`.
///
/// Two fingers on the page set the note's zoom, which its type sizes are multiplied by on top of the Text size
/// setting. The words under the fingers stay under them as the lines reflow, and the zoom is kept, so every note
/// opens at the size last pinched.
///
/// What differs: the page sets `--note-zoom` on the scroller and its stylesheet multiplies; here [NoteZoom] is
/// listened to and the screen makes the editor's sizes from it (lib/note/note_screen.dart). The fingers are counted
/// from pointer events ([PinchTracker]) by a `Listener` round the page, which takes nothing from the scroll view:
/// two fingers down hold the page where it is (`ScrollPosition.hold`), where the page calls
/// `preventDefault` on their moves.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../core/stored.dart';

const double zoomMin = 0.7;
const double zoomMax = 2;
const String _key = 'glyph-note-zoom';

/// [zoom] held to what a note may be pinched to; anything that is not a number is 1 (`clampZoom`).
double clampZoom(double zoom) => zoom.isFinite ? math.min(zoomMax, math.max(zoomMin, zoom)) : 1;

/// The zoom kept on this device, or 1 (`readZoom`).
double readZoom([Stored? device]) {
  final kept = double.tryParse((device ?? stored).readText(_key) ?? '');
  return kept == null || kept == 0 ? 1 : clampZoom(kept);
}

/// Keeps [zoom]; one within a fiftieth of 1 is no zoom, and nothing is kept (`writeZoom`).
void writeZoom(double zoom, [Stored? device]) => (device ?? stored).writeText(_key, (zoom - 1).abs() < 0.02 ? null : zoom.toStringAsFixed(3));

/// The zoom for fingers now [distance] apart, pinched from [startDistance] at [startZoom] (`pinched`).
double pinched(double startZoom, double startDistance, double distance) => startDistance > 0 ? clampZoom(startZoom * distance / startDistance) : clampZoom(startZoom);

/// The note's zoom, listened to by whoever draws the note.
class NoteZoom extends ValueNotifier<double> {
  NoteZoom({Stored? device})
      : _device = device,
        super(readZoom(device));

  final Stored? _device;

  /// Kept for the next note.
  void keep() => writeZoom(value, _device);
}

/// Two fingers counted from the page's pointers: where they are, how far apart, and their middle.
class PinchTracker {
  final Map<int, Offset> _down = {};

  int get fingers => _down.length;
  bool get pinching => _down.length == 2;

  void put(int pointer, Offset at) => _down[pointer] = at;
  void lift(int pointer) => _down.remove(pointer);

  /// How far apart the two are (`apart`); zero with any other number down.
  double get apart {
    if (!pinching) return 0;
    final both = _down.values.toList();
    return (both[0] - both[1]).distance;
  }

  /// The middle of the two (`middle`), or null.
  Offset? get middle {
    if (!pinching) return null;
    final both = _down.values.toList();
    return (both[0] + both[1]) / 2;
  }
}

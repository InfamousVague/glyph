import 'package:flutter/animation.dart';

/// A sheet you can take hold of: drag its handle down and it follows your finger, and let go past [closePx] (96 px),
/// or on a flick, and it closes (Matt: "Can't grab and scroll up and down on drawer handles"). A port of
/// `src/app/editor/sheetDrag.ts`.
///
/// The handle is the grab, not the whole sheet, so the rows inside still scroll and a press on one is a press. Pulled
/// up, the sheet gives a little and comes back: there is nothing above it to open into, and a handle that does
/// nothing at all feels stuck. Let go under the threshold and it springs back to where it was. Reduced motion is not
/// asked: the panel follows the finger, and springs back, whatever the setting.
///
/// What differs: the web's hook wrote `transform` and `transition` onto the panel's element; this is the hook's
/// arithmetic alone, and tells [onMove] how far down the panel is to be drawn and whether it gets there at once or
/// on the spring ([springDuration], [springCurve]). The times are the pointer events' own stamps, where the page
/// read `performance.now()` as each arrived.
class SheetDrag {
  SheetDrag({required this.onMove, required this.onClose});

  /// Past this far down, or this fast, the sheet closes (`CLOSE_PX`, `FLICK_PX_PER_MS`).
  static const double closePx = 96;
  static const double flickPxPerMs = 0.5;

  /// How far it gives when pulled upward: enough to answer the hand, not enough to look like it opens (`GIVE_PX`).
  static const double givePx = 28;

  /// `SPRING`: `transform 220ms cubic-bezier(0.2, 0.9, 0.3, 1)`.
  static const Duration springDuration = Duration(milliseconds: 220);
  static const Curve springCurve = Cubic(0.2, 0.9, 0.3, 1);

  /// How far down the panel is drawn, in logical pixels (negative is up), and whether it springs there.
  final void Function(double dy, {required bool animated}) onMove;

  /// What a full pull does.
  final void Function() onClose;

  ({double y, double at})? _from;

  /// The last moment of movement, so a flick is judged on how it ended, not on its average.
  ({double y, double at})? _last;

  /// Whether a finger has hold of the handle.
  bool get held => _from != null;

  /// `onPointerDown`: [y] is the pointer's place down the window, [ms] its time, [primary] false for a second finger.
  void down(double y, double ms, {bool primary = true}) {
    if (!primary) return;
    _from = (y: y, at: ms);
    _last = _from;
    onMove(0, animated: false);
  }

  /// `onPointerMove`.
  void move(double y, double ms) {
    final start = _from;
    if (start == null) return;
    final dy = y - start.y;
    _last = (y: y, at: ms);
    // Down it follows the finger; up it gives, less and less, and never far.
    onMove(dy >= 0 ? dy : -givePx * (1 - 1 / (1 - dy / givePx + 1)), animated: false);
  }

  /// `onPointerUp` and `onPointerCancel`.
  void end(double y, double ms) {
    final start = _from;
    _from = null;
    if (start == null) return;
    final dy = y - start.y;
    final recent = _last ?? start;
    _last = null;
    // How it ended: a flick is quick at the last, where a slow pull that happens to cover ground is not.
    final elapsed = ms - recent.at;
    final speed = (y - recent.y) / (elapsed < 1 ? 1 : elapsed);
    if (dy > closePx || (dy > 24 && speed > flickPxPerMs)) {
      onClose();
      onMove(0, animated: false);
      return;
    }
    onMove(0, animated: true);
  }
}

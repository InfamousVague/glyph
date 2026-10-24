import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../perf/frame_log.dart' show Perf, ghostPerf;

/// Whether a letter whose look is kept (a frosted one, lib/editor/marks/text_effects.dart) is laid down from its
/// kept picture while frames follow one another ([WispKept]), where it is drawn by its own layers on every frame
/// otherwise. What a build draws, since 2026-10-10; a build made with `--dart-define=GHOST_WISP_QUICK=false` draws
/// every frame by the layers, and a test says which it gets ([debugWispQuick]).
bool get wispQuick => debugWispQuick ?? _quick;
const bool _quick = bool.fromEnvironment('GHOST_WISP_QUICK', defaultValue: true);

/// Says which drawing a test gets, whatever the build was told.
@visibleForTesting
bool? debugWispQuick;

/// Whether frames are following one another: asked while a frame paints.
///
/// What is drawn for a page that moves and what is drawn for a page drawn once are not the same question. A page
/// drawn once (a note opened and left, a picture taken in a test) is drawn as it always was, each letter's own
/// layers and blurs. A page whose frames follow one another, sixteen milliseconds apart or eight, draws the same
/// letters hundreds of times, and there what a letter looks like is made once and laid down again
/// ([WispKept]).
abstract final class WispFlow {
  /// Frames this close together follow one another; further apart, the page stood still between them.
  static const Duration within = Duration(milliseconds: 50);

  static Duration _frame = const Duration(days: -1), _before = const Duration(days: -2);

  /// This frame's time and the time of the frame before it that asked.
  static Duration get frame => _frame;
  static Duration get before => _before;

  /// Whether this frame follows another closely. False outside a frame's own painting: there is no frame to follow
  /// one drawn outside it. After, and soon after: a clock that went back (a test's, begun again) follows nothing.
  static bool get now {
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) return false;
    final stamp = SchedulerBinding.instance.currentFrameTimeStamp;
    if (stamp != _frame) {
      _before = _frame;
      _frame = stamp;
    }
    final since = _frame - _before;
    return since > Duration.zero && since <= within;
  }

  /// As a build begins: for a test.
  static void reset() {
    _frame = const Duration(days: -1);
    _before = const Duration(days: -2);
  }
}

/// Pictures of letters, kept while what they show stands: a letter's glow, its blur at one softness, the rime grown
/// round it at one reach. Each is drawn once, by whoever knows how ([paint]'s `draw`), into a picture of its own at
/// the screen's pixels, and laid down from it on every frame after, where drawing it afresh was a layer and a blur
/// or two for every letter on every frame (lib/editor/marks/text_effects.dart).
///
/// A picture laid between the screen's pixels is read between its own and comes out soft, so none is: see [paint].
abstract final class WispKept {
  static final Map<Object, ({ui.Image image, int bytes})> _kept = {};
  static int _bytes = 0;

  /// No more than this is kept, the pictures least lately laid down let go first.
  static const int _most = 12 << 20;

  /// How many pictures were made and how many times one was laid down: for a test.
  static int debugMade = 0, debugLaid = 0;

  /// Lays down the picture kept under [key], drawing it first with [draw] if there is none. [over] is what the
  /// picture covers, in the canvas's own coordinates; [draw] paints into a canvas with the same coordinates. [ratio]
  /// is the screen's pixels to one of them. [opacity] is how much of it shows, which may change from frame to frame
  /// under one key.
  ///
  /// A kept picture is always laid on the screen's own pixels, never between them. A soft one (a glow) is moved to
  /// the nearest, half a pixel at most. A [sharp] one (a letter hardly blurred yet, among letters that are not) is
  /// kept as it stands between the pixels, to a quarter of one each way, which is as finely as text itself is set:
  /// one picture for each such place it is seen in, and laid where it belongs.
  static void paint(Canvas canvas, Object key, {required Rect over, required double ratio, required void Function(Canvas canvas) draw, double opacity = 1, bool sharp = false}) {
    // How far past a corner of the screen's pixels [over]'s corner falls, and how much of that the picture has in it.
    var past = Offset.zero, within = Offset.zero;
    final to = canvas.getTransform();
    if (to[0] == 1 && to[5] == 1 && to[1] == 0 && to[4] == 0) {
      final x = (to[12] + over.left) * ratio, y = (to[13] + over.top) * ratio;
      if (sharp) {
        past = Offset(x - x.floorToDouble(), y - y.floorToDouble());
        within = Offset((past.dx * 4).roundToDouble() / 4, (past.dy * 4).roundToDouble() / 4);
        key = (key, within);
      } else {
        past = Offset(x - x.roundToDouble(), y - y.roundToDouble());
      }
    }
    var had = _kept.remove(key);
    if (had == null) {
      final wide = ((over.width * ratio).ceil() + (sharp ? 1 : 0)).clamp(1, 4096), tall = ((over.height * ratio).ceil() + (sharp ? 1 : 0)).clamp(1, 4096);
      final recorder = ui.PictureRecorder();
      final into = Canvas(recorder);
      into.translate(within.dx, within.dy);
      into.scale(ratio);
      into.translate(-over.left, -over.top);
      draw(into);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(wide, tall);
      picture.dispose();
      had = (image: image, bytes: wide * tall * 4);
      _bytes += had.bytes;
      debugMade += 1;
      if (ghostPerf) Perf.count('wisp.kept.made');
      while (_bytes > _most && _kept.isNotEmpty) {
        final oldest = _kept.remove(_kept.keys.first)!;
        _bytes -= oldest.bytes;
        oldest.image.dispose();
      }
    }
    _kept[key] = had;
    debugLaid += 1;
    final size = Size(had.image.width.toDouble(), had.image.height.toDouble());
    canvas.drawImageRect(
      had.image,
      Offset.zero & size,
      (over.topLeft - past / ratio) & (size / ratio),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0))
        ..filterQuality = FilterQuality.low,
    );
  }

  /// Lets every kept picture go: a test ended, or the faces changed.
  static void clear() {
    for (final one in _kept.values) {
      one.image.dispose();
    }
    _kept.clear();
    _bytes = 0;
    debugMade = 0;
    debugLaid = 0;
  }
}

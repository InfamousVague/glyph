/// A cassette, drawn flat in two inks: an ink shell with everything on it printed in paper, and a paper label with
/// everything on it printed in ink. The tokens reverse with the theme, so the tape does too. A port of
/// `src/app/tapes/TapeArt.tsx` and TapeArt.module.css, shape for shape from its 320 by 204 drawing.
///
/// [positionMs] sets how much tape is on the right reel - a note's length, or where playback has got to - out of
/// [lengthMs], the whole tape. While [playing], the reels turn at tape speed over their own radii (`tape.dart`
/// `reelTurn`). Drawn [bare], the label is its paper and its A mark and no words.
///
/// What differs: the web's home page drew these on a shelf of tapes (`home/TapeShelf.tsx`), which went with the
/// dashboard (docs/DESIGN.md §147): a recording is a row with a cassette's mark and its length now, so nothing on
/// today's home page draws this. It is here for the tape at the top of a spoken note (`tapes/NoteTape.tsx`) and the
/// meeting's screen, which are not ported yet, as `useTape.ts` (the player) is not.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'tape.dart';

/// The cassette (`src/app/tapes/TapeArt.tsx`), painted from the same 320 by 204 drawing. Nothing on today's home
/// page draws it: the shelf of tapes went with the dashboard.
class TapeArt extends StatefulWidget {
  const TapeArt({super.key, required this.positionMs, this.lengthMs = tapeMs, this.playing = false, this.title, this.side, this.counter, this.bare = false});

  /// Milliseconds of tape on the take-up reel: the note's length, or the playhead.
  final num positionMs;

  /// How much tape the cassette holds: five minutes unless the note is longer.
  final num lengthMs;
  final bool playing;

  /// The label's first line. Not drawn on a [bare] cassette.
  final String? title;

  /// Small print, top right of the label.
  final String? side;

  /// Small print, bottom right of the label.
  final String? counter;

  /// The label paper and its A mark, and no words.
  final bool bare;

  @override
  State<TapeArt> createState() => _TapeArtState();
}

class _TapeArtState extends State<TapeArt> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<({double supply, double takeup})> _angles = ValueNotifier((supply: 0, takeup: 0));
  Duration _last = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TapeArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// The reels turn only while it plays, and hold still when the phone is set to reduce motion.
  void _sync() {
    final turning = widget.playing && !context.tokens.reducedMotion;
    if (turning && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!turning && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final dt = math.min(100, (elapsed - _last).inMicroseconds / 1000);
    _last = elapsed;
    // Counter-clockwise while the tape runs left to right along the bottom.
    final turn = reelTurn(widget.positionMs, dt, widget.lengthMs);
    _angles.value = (supply: (_angles.value.supply - turn.supply) % 360, takeup: (_angles.value.takeup - turn.takeup) % 360);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 320 / 204,
        child: CustomPaint(
          painter: _TapePainter(
            packs: packRadii(widget.positionMs, widget.lengthMs),
            angles: _angles,
            ink: t.color('app-ink'),
            paper: t.color('app-paper'),
            pack: t.colorOf('color-mix(in oklch, var(--app-paper) 20%, var(--app-ink))'),
            font: t.textAt(13, weight: 'bold'),
            title: widget.bare ? null : widget.title,
            side: widget.bare ? null : widget.side,
            counter: widget.bare ? null : widget.counter,
          ),
        ),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter({required this.packs, required this.angles, required this.ink, required this.paper, required this.pack, required this.font, this.title, this.side, this.counter}) : super(repaint: angles);

  final ({double supply, double takeup}) packs;
  final ValueNotifier<({double supply, double takeup})> angles;
  final Color ink, paper, pack;
  final TextStyle font;
  final String? title, side, counter;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320, size.height / 204);
    final inkFill = Paint()..color = ink;
    final paperFill = Paint()..color = paper;
    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    // The shell.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(2, 2, 316, 200), const Radius.circular(14)), inkFill);

    // Wound tape, seen through the window: a flat tone of paper on the ink, with a hard edge.
    for (final (x, r) in [(leftX, packs.supply), (rightX, packs.takeup)]) {
      canvas.drawCircle(Offset(x, reelY), r, Paint()..color = pack);
      canvas.drawCircle(Offset(x, reelY), r, stroke(paper, 1));
    }
    _reel(canvas, leftX, angles.value.supply, inkFill, paperFill);
    _reel(canvas, rightX, angles.value.takeup, inkFill, paperFill);

    // From the left pack down round its guide, along the bottom, and up onto the right pack.
    final leave = Offset(leftX - packs.supply * 0.62, reelY + packs.supply * 0.78);
    final arrive = Offset(rightX + packs.takeup * 0.62, reelY + packs.takeup * 0.78);
    canvas.drawPath(
      Path()
        ..moveTo(leave.dx, leave.dy)
        ..lineTo(46, 156)
        ..lineTo(70, 170)
        ..lineTo(250, 170)
        ..lineTo(274, 156)
        ..lineTo(arrive.dx, arrive.dy),
      stroke(paper, 1.4),
    );
    canvas.drawCircle(const Offset(50, 154), 3.5, paperFill);
    canvas.drawCircle(const Offset(270, 154), 3.5, paperFill);

    // The label: its paper, with the window cut out of it, and everything on it printed in ink.
    final label = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 14, 280, 132), const Radius.circular(8)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(62, 61, 196, 56), const Radius.circular(28)));
    canvas.save();
    canvas.clipPath(label);
    canvas.drawRect(const Rect.fromLTWH(20, 14, 280, 132), paperFill);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 22, 15, 15), const Radius.circular(2)), inkFill);
    _words(canvas, 'A', const Offset(37.5, 33.5), size: 11, color: paper, weight: FontWeight.w800, anchor: 0.5);
    if (title != null && title!.isNotEmpty) _words(canvas, title!, const Offset(53, 34), size: 13, color: ink, weight: FontWeight.w800, tracking: 0.06 * 13);
    if (side != null && side!.isNotEmpty) _words(canvas, side!, const Offset(290, 33), size: 7, color: ink, weight: FontWeight.w600, tracking: 0.14 * 7, anchor: 1, tabular: true);
    canvas.drawLine(const Offset(30, 44), const Offset(290, 44), stroke(ink, 0.8));
    canvas.drawLine(const Offset(20, 129), const Offset(300, 129), stroke(ink, 0.8));
    if (counter != null && counter!.isNotEmpty) _words(canvas, counter!, const Offset(290, 142), size: 7, color: ink, weight: FontWeight.w600, tracking: 0.14 * 7, anchor: 1, tabular: true);
    canvas.restore();

    // The shell's own furniture, in a thinner paper line.
    final outline = stroke(paper.withValues(alpha: 0.55), 1.2);
    canvas.drawPath(
      Path()
        ..moveTo(66, 202)
        ..lineTo(84, 166)
        ..lineTo(236, 166)
        ..lineTo(254, 202),
      outline,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(146, 177, 28, 10), const Radius.circular(2)), outline);
    canvas.drawCircle(const Offset(104, 186), 5, outline);
    canvas.drawCircle(const Offset(216, 186), 5, outline);
    for (final at in const [Offset(14, 14), Offset(306, 14), Offset(14, 190), Offset(306, 190), Offset(160, 194)]) {
      canvas.drawCircle(at, 2.8, paperFill);
    }
    canvas.restore();
  }

  /// A hub: a paper ring, the spindle hole, and the six teeth that show it turning.
  void _reel(Canvas canvas, double cx, double degrees, Paint inkFill, Paint paperFill) {
    canvas.save();
    canvas.translate(cx, reelY);
    canvas.rotate(degrees * math.pi / 180);
    canvas.drawCircle(Offset.zero, hubR, paperFill);
    canvas.drawCircle(Offset.zero, hubR - 5.5, inkFill);
    for (var tooth = 0; tooth < 6; tooth += 1) {
      canvas.save();
      canvas.rotate(tooth * math.pi / 3);
      canvas.drawRect(Rect.fromLTWH(-1.4, -(hubR - 5.5), 2.8, 3.4), paperFill);
      canvas.restore();
    }
    canvas.drawCircle(const Offset(0, -hubR + 2.6), 1.3, inkFill);
    canvas.restore();
  }

  /// SVG `<text>`: its baseline at [at], anchored at its start (0), middle (0.5) or end (1).
  void _words(Canvas canvas, String text, Offset at, {required double size, required Color color, required FontWeight weight, double tracking = 0, double anchor = 0, bool tabular = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: Tokens.resized(font, size).copyWith(
          color: color,
          fontWeight: weight,
          letterSpacing: tracking,
          height: 1,
          fontVariations: [FontVariation('wght', weight.value.toDouble()), FontVariation('opsz', size.clamp(14, 32).toDouble())],
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    // Tracking trails the last letter in a browser's measure as it does here, so an end anchor keeps it.
    painter.paint(canvas, Offset(at.dx - painter.width * anchor, at.dy - baseline));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_TapePainter old) =>
      old.packs != packs || old.ink != ink || old.paper != paper || old.pack != pack || old.title != title || old.side != side || old.counter != counter || old.font != font;
}

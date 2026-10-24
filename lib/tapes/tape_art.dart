/// A cassette, drawn flat in two inks: an ink shell with everything on it printed in paper, and a paper label with
/// everything on it printed in ink. The tokens reverse with the theme, so the tape does too. A port of
/// `src/app/tapes/TapeArt.tsx` and TapeArt.module.css, shape for shape from its 320 by 204 drawing.
///
/// [positionMs] sets how much tape is on the right reel - a note's length, or where playback has got to - out of
/// [lengthMs], the whole tape. While [playing], the reels turn at tape speed over their own radii (`tape.dart`
/// `reelTurn`). Drawn [bare], the label is its paper and its A mark and no words.
///
/// With [titleLines] above one, the label's first line is a title in larger type over as many lines, cut with an
/// ellipsis, and the rule under it steps down into the room above the window (the shelf of meetings,
/// `home/meeting_shelf.dart`: Matt, 2026-10-23, "show the note title on the cassette"). At one, the drawing is the
/// web's, unchanged. [centred] is the shelf's since 2026-10-24 (Matt: "make all cassete titles one line and center
/// them in the open spot"): one line in the larger type, smaller for a long title down to [tapeTitleMinSize] and then
/// cut, centred in the open spot right of the A mark, between the label's top and the rule over the window
/// ([tapeCentredTitle]).
///
/// Given a [hue], one of the kit's colour ramps ([tapeHues]; [tapeHue] picks one from a note's id, so a note's tape is
/// the same colour on every device and every surface), the cassette is that hue at different strengths on different
/// parts rather than two inks, for depth (Matt, 2026-10-24: "give the cassettes different colors from the color token
/// palette as well with different opacities on different parts of the cassete to build depth"): the shell solid with
/// a shaded rim and a lit top edge, the guard at its foot a step down, the label paper faintly tinted with a band of
/// the hue across it and a shadow under it, the window smoked, the tape dark, the hubs lit. Lit and shaded are the
/// lighter and darker of the paper and the ink, so the light comes from above in both themes. The title stays ink on
/// a label that is nearly paper. In simple mode ([muted]) every strength is lower, a pastel of the hue. Without a
/// hue it is the two inks.
///
/// What differs: the web's home page drew these on a shelf of tapes (`home/TapeShelf.tsx`), which went with the
/// dashboard (docs/DESIGN.md §147); today's home page draws them on the shelf of meetings (GHST-112,
/// `home/meeting_shelf.dart`), each with its note's title on the label in two lines ([TapeArt.titleLines]). It is
/// here too for the tape at the top of a spoken note (`tapes/NoteTape.tsx`) and the meeting's screen.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import 'tape.dart';

/// The kit's colour ramps a cassette can wear (`--glacier-<hue>-1` to `-12`, which turn over with the theme), set
/// round the colour wheel so that the next one along is never the one before. Its grey is the two inks' business.
const List<String> tapeHues = ['red', 'amber', 'green', 'teal', 'blue', 'purple'];

/// The hue a note's cassette wears: one of [tapeHues], from a hash of its [id] (32-bit FNV-1a over its UTF-16 code
/// units), so the same note is the same colour on every device, and two notes side by side usually differ.
String tapeHue(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    // Times the FNV prime, 2^24 + 0x193, in two parts that stay under 2^53, so a web build gets the same answer.
    final x = hash ^ unit;
    hash = (x * 0x193 + ((x & 0xff) << 24)) & 0xffffffff;
  }
  return tapeHues[hash % tapeHues.length];
}

/// The cassette (`src/app/tapes/TapeArt.tsx`), painted from the same 320 by 204 drawing.
class TapeArt extends StatefulWidget {
  const TapeArt({super.key, required this.positionMs, this.lengthMs = tapeMs, this.playing = false, this.title, this.side, this.counter, this.bare = false, this.titleLines = 1, this.centred = false, this.hue, this.muted});

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

  /// How many lines the title may take. One is the web's label; more draws it as [tapeLabelTitle] lays it out.
  final int titleLines;

  /// The title on one line in the larger type, centred in the open band over the window ([tapeCentredTitle]).
  final bool centred;

  /// The colour ramp it is drawn in, one of [tapeHues] ([tapeHue] of its note); none is the two inks.
  final String? hue;

  /// The [hue] at lower strengths, calm: simple mode's unless said.
  final bool? muted;

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
    final hue = widget.hue != null && tapeHues.contains(widget.hue) ? widget.hue : null;
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
            titleLines: widget.titleLines,
            centred: widget.centred,
            hue: hue == null ? null : t.color('glacier-$hue-9'),
            muted: widget.muted ?? preferences.value.simple,
            dark: t.isDark,
          ),
        ),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter({required this.packs, required this.angles, required this.ink, required this.paper, required this.pack, required this.font, this.title, this.side, this.counter, this.titleLines = 1, this.centred = false, this.hue, this.muted = false, this.dark = false}) : super(repaint: angles);

  final ({double supply, double takeup}) packs;
  final ValueNotifier<({double supply, double takeup})> angles;
  final Color ink, paper, pack;
  final TextStyle font;
  final String? title, side, counter;
  final int titleLines;
  final bool centred;

  /// The ramp's ninth step (`--glacier-<hue>-9`), the solid of the hue in either theme; null draws the two inks.
  final Color? hue;
  final bool muted, dark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 320, size.height / 204);
    if (hue != null) {
      _paintHued(canvas, hue!);
      canvas.restore();
      return;
    }
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
    _print(canvas, rule: stroke(ink, 0.8));
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

  /// What is printed on the label in ink: the title, the side, the counter, and the two rules in [rule].
  void _print(Canvas canvas, {required Paint rule}) {
    final tall = titleLines > 1 || centred;
    if (title != null && title!.isNotEmpty) {
      if (centred) {
        final words = tapeCentredTitle(title!, font, color: ink);
        words.paint(canvas, Offset(tapeMiddle - words.width / 2, (tapeLabelTop + tapeTitleRule) / 2 - words.height / 2));
        words.dispose();
      } else if (tall) {
        final words = tapeLabelTitle(title!, font, lines: titleLines, color: ink);
        words.paint(canvas, const Offset(tapeTitleLeft, tapeTitleTop));
        words.dispose();
      } else {
        _words(canvas, title!, const Offset(53, 34), size: 13, color: ink, weight: FontWeight.w800, tracking: 0.06 * 13);
      }
    }
    if (side != null && side!.isNotEmpty) _words(canvas, side!, const Offset(290, 33), size: 7, color: ink, weight: FontWeight.w600, tracking: 0.14 * 7, anchor: 1, tabular: true);
    canvas.drawLine(Offset(30, tall ? tapeTitleRule : 44), Offset(290, tall ? tapeTitleRule : 44), rule);
    canvas.drawLine(const Offset(20, 129), const Offset(300, 129), rule);
    if (counter != null && counter!.isNotEmpty) _words(canvas, counter!, const Offset(290, 142), size: 7, color: ink, weight: FontWeight.w600, tracking: 0.14 * 7, anchor: 1, tabular: true);
  }

  /// The cassette in one hue at several strengths, for depth. Each part lays the hue over the paper at its own
  /// opacity, then the light (the lighter of paper and ink) or the shade (the darker) over that, so the light falls
  /// from above in either theme. Muted, for simple mode, the same parts at lower strengths.
  void _paintHued(Canvas canvas, Color hue) {
    final light = dark ? ink : paper, shade = dark ? paper : ink;
    final m = muted ? 0.5 : 1.0;
    Paint fill(Color color, double alpha) => Paint()..color = color.withValues(alpha: alpha);
    Paint stroke(Color color, double alpha, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: alpha);
    // The hue over the paper, so what is under the cassette never shows through it.
    Paint tinted(double alpha) => Paint()..color = Color.alphaBlend(hue.withValues(alpha: alpha), paper);

    // The shell, solid; its rim in the shade, and its top edge caught by the light.
    final shell = RRect.fromRectAndRadius(const Rect.fromLTWH(2, 2, 316, 200), const Radius.circular(14));
    canvas.drawRRect(shell, tinted(muted ? 0.42 : 1));
    canvas.drawRRect(shell.deflate(2.5), stroke(shade, 0.2 * m, 5));
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, 320, 18));
    canvas.drawRRect(shell.deflate(1.4), stroke(light, 0.45 * m, 1.2));
    canvas.restore();

    // The guard at the foot, a step into the shade.
    canvas.save();
    canvas.clipRRect(shell);
    canvas.drawPath(
      Path()
        ..moveTo(66, 204)
        ..lineTo(84, 166)
        ..lineTo(236, 166)
        ..lineTo(254, 204)
        ..close(),
      fill(shade, 0.14 * m),
    );
    canvas.restore();

    // The window: smoked glass, darker than the shell; the wound tape behind it darker still, with a lit hard edge.
    final window = RRect.fromRectAndRadius(const Rect.fromLTWH(62, 61, 196, 56), const Radius.circular(28));
    canvas.drawRRect(window, fill(shade, 0.42 * m));
    for (final (x, r) in [(leftX, packs.supply), (rightX, packs.takeup)]) {
      canvas.drawCircle(Offset(x, reelY), r, fill(shade, 0.62 * m));
      canvas.drawCircle(Offset(x, reelY), r, stroke(light, 0.4, 1));
    }
    final ring = fill(light, muted ? 0.8 : 0.92);
    final hole = Paint()..color = Color.alphaBlend(shade.withValues(alpha: 0.4 * m), hue);
    _reel(canvas, leftX, angles.value.supply, hole, ring);
    _reel(canvas, rightX, angles.value.takeup, hole, ring);

    // The tape from pack to pack round the guides, dark, as tape is.
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
      stroke(shade, 0.72 * m, 1.4),
    );
    canvas.drawCircle(const Offset(50, 154), 3.5, fill(light, 0.85));
    canvas.drawCircle(const Offset(270, 154), 3.5, fill(light, 0.85));

    // The label, raised: a shadow under it, then its paper with the faintest tint of the hue and a band of the hue
    // across it under the window. The title on it is ink on what is nearly paper.
    const labelBox = Rect.fromLTWH(20, 14, 280, 132);
    final edge = RRect.fromRectAndRadius(labelBox, const Radius.circular(8));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRRect(edge.shift(const Offset(0, 1.8)))
        ..addRRect(window),
      fill(shade, 0.22 * m),
    );
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRRect(edge)
        ..addRRect(window),
    );
    // A touch more on the dark, whose paper drinks a tint that reads on white.
    canvas.drawRect(labelBox, tinted(muted ? 0.06 : (dark ? 0.18 : 0.12)));
    canvas.drawRect(const Rect.fromLTWH(20, 119, 280, 8), fill(hue, muted ? 0.3 : 0.7));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 22, 15, 15), const Radius.circular(2)), fill(hue, muted ? 0.55 : 1));
    _words(canvas, 'A', const Offset(37.5, 33.5), size: 11, color: light, weight: FontWeight.w800, anchor: 0.5);
    _print(canvas, rule: stroke(ink, 0.55, 0.8));
    canvas.restore();
    canvas.drawRRect(edge, stroke(hue, 0.5 * m, 0.8));
    // The glass's rim in the shade along its top, where the label overhangs it.
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(0, 0, 320, reelY));
    canvas.drawRRect(window.deflate(0.8), stroke(shade, 0.35 * m, 1.6));
    canvas.restore();

    // The shell's own furniture, recessed into the shade with a thin lit line, and its screws.
    final outline = stroke(light, 0.1 + 0.4 * m, 1.2);
    final recess = fill(shade, 0.3 * m);
    canvas.drawPath(
      Path()
        ..moveTo(66, 202)
        ..lineTo(84, 166)
        ..lineTo(236, 166)
        ..lineTo(254, 202),
      outline,
    );
    final slot = RRect.fromRectAndRadius(const Rect.fromLTWH(146, 177, 28, 10), const Radius.circular(2));
    canvas.drawRRect(slot, recess);
    canvas.drawRRect(slot, outline);
    for (final x in const [104.0, 216.0]) {
      canvas.drawCircle(Offset(x, 186), 5, recess);
      canvas.drawCircle(Offset(x, 186), 5, outline);
    }
    for (final at in const [Offset(14, 14), Offset(306, 14), Offset(14, 190), Offset(306, 190), Offset(160, 194)]) {
      canvas.drawCircle(at, 2.8, fill(light, 0.8));
      canvas.drawCircle(at, 1, fill(shade, 0.35 * m));
    }
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
      old.packs != packs ||
      old.ink != ink ||
      old.paper != paper ||
      old.pack != pack ||
      old.title != title ||
      old.side != side ||
      old.counter != counter ||
      old.font != font ||
      old.titleLines != titleLines ||
      old.centred != centred ||
      old.hue != hue ||
      old.muted != muted ||
      old.dark != dark;
}

/// Where a title of more than one line sits on the label, in the drawing's units: from the A mark's right to the
/// label's inner edge, from just under the label's top to the rule, which steps down from 44 to just over the window
/// (at 61). [tapeTitleSize] is the type's size there, half as large again as the one line's 13, so a cassette 190
/// pixels wide still says its title at about eleven.
const double tapeTitleLeft = 53, tapeTitleTop = 15, tapeTitleWidth = 237, tapeTitleRule = 58, tapeTitleSize = 19;

/// The label's title over [lines] lines, laid out [tapeTitleWidth] wide in [font] at [tapeTitleSize], cut with an
/// ellipsis on the last: what the painter draws at ([tapeTitleLeft], [tapeTitleTop]). A word longer than the line is
/// broken where it meets the edge, so nothing runs off the label. The caller disposes of it.
TextPainter tapeLabelTitle(String title, TextStyle font, {int lines = 2, Color? color}) => _titleAt(title, font, tapeTitleSize, lines: lines, color: color, width: tapeTitleWidth);

/// The open spot on the label a centred title sits in: from the A mark's right ([tapeTitleLeft]) to the label's inner
/// edge, [tapeCentredWidth] wide about [tapeMiddle], and from the label's top to the rule. [tapeTitleMinSize] is the
/// smallest a long title is set at before it is cut.
const double tapeLabelTop = 14, tapeCentredWidth = tapeTitleWidth, tapeMiddle = tapeTitleLeft + tapeTitleWidth / 2, tapeTitleMinSize = 13;

/// The title on one line, centred ([TapeArt.centred]): at [tapeTitleSize] where it fits [tapeCentredWidth], else a
/// size smaller each time down to [tapeTitleMinSize], and there cut with an ellipsis. The caller disposes of it.
TextPainter tapeCentredTitle(String title, TextStyle font, {Color? color}) {
  for (var size = tapeTitleSize;; size -= 1) {
    final words = _titleAt(title, font, size, lines: 1, color: color, width: tapeCentredWidth);
    if (!words.didExceedMaxLines || size <= tapeTitleMinSize) return words;
    words.dispose();
  }
}

TextPainter _titleAt(String title, TextStyle font, double size, {required int lines, required double width, Color? color}) {
  const weight = FontWeight.w800;
  return TextPainter(
    text: TextSpan(
      text: title,
      style: Tokens.resized(font, size).copyWith(
        color: color,
        fontWeight: weight,
        letterSpacing: 0.02 * size,
        height: 1.08,
        fontVariations: [FontVariation('wght', weight.value.toDouble()), FontVariation('opsz', size)],
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: lines,
    ellipsis: '…',
  )..layout(maxWidth: width);
}

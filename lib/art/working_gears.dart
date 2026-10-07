import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'gears.dart';
import 'svg_path.dart';

/// The size of a tooth. Everything else is counted in teeth, so the machine stays meshed at any scale.
const double workingGearsModule = 1.9;

/// The driving cog, then the two it turns: a number of teeth each, chosen so none of the ratios is a whole number.
const List<int> workingGearsTeeth = [13, 9, 7];

/// How long the driving cog takes to come round once. The others follow from their teeth.
const double workingGearsTurn = 3.4;

/// One cog of the three: where it sits, the angle that meshes it, and how it turns.
class WorkingCog {
  const WorkingCog({required this.at, required this.teeth, required this.angle, required this.seconds, required this.way});
  final Offset at;
  final int teeth;

  /// Its starting angle, radians.
  final double angle;

  /// One turn, in seconds, and which way.
  final double seconds;
  final int way;

  String get path => spurPath(teeth, workingGearsModule, teeth > 10 ? Hub.holes : Hub.spokes);

  /// Where it has turned to after [elapsed] seconds.
  double angleAt(double elapsed) => angle + way * 2 * math.pi * (elapsed / seconds);
}

/// The three cogs as art/WorkingGears.tsx works them out, and the box that holds them.
({List<WorkingCog> cogs, Rect box}) workingGears() {
  final [big, mid, small] = workingGearsTeeth;
  const m = workingGearsModule;
  final rBig = pitchRadius(big, m), rMid = pitchRadius(mid, m), rSmall = pitchRadius(small, m);
  // The middle cog sits to the right of the driving one, the small one up and right of that: each at the sum of the
  // two pitch radii, which is where their teeth touch.
  const bigAt = Offset.zero;
  final midAt = Offset(rBig + rMid, 0);
  const towards = -0.72;
  final smallAt = Offset(midAt.dx + (rMid + rSmall) * math.cos(towards), midAt.dy + (rMid + rSmall) * math.sin(towards));
  // A tooth of one into a gap of the next: the start angles that mesh them.
  final midAngle = outsidePhase(big, 0, 0, mid);
  final smallAngle = outsidePhase(mid, midAngle, towards, small);
  // Rolling without slipping: each cog turns the other way from the one driving it, faster by the ratio of teeth.
  // The times are the stylesheet's, which is given them to the hundredth of a second.
  double hundredths(double seconds) => double.parse(seconds.toStringAsFixed(2));
  final cogs = [
    WorkingCog(at: bigAt, teeth: big, angle: 0, seconds: hundredths(workingGearsTurn), way: 1),
    WorkingCog(at: midAt, teeth: mid, angle: midAngle, seconds: hundredths(workingGearsTurn * mid / big), way: -1),
    WorkingCog(at: smallAt, teeth: small, angle: smallAngle, seconds: hundredths(workingGearsTurn * small / big), way: 1),
  ];
  return (cogs: cogs, box: Rect.fromLTRB(bigAt.dx - rBig - m, smallAt.dy - rSmall - m, smallAt.dx + rSmall + m, bigAt.dy + rBig + m));
}

/// Three cogs meshing and turning, small enough to sit in a line of type: the update card while the new version is
/// coming down (art/WorkingGears.tsx, art/WorkingGears.module.css).
///
/// The teeth really interleave: every gear shares one module, two that mesh sit the sum of their pitch radii apart,
/// and [outsidePhase] gives the second the start angle that puts a tooth of one into a gap of the other; the small
/// gears turn the other way, faster by the ratio of their teeth. Drawn in the text's own ink at 85%, 1.15 of the
/// text's size tall, and still when the phone asks for reduced motion.
///
/// What differs from the page, on purpose. The web app's cogs do not do what its own comments and tests say: its
/// stylesheet places each cog with `transform: translate()` and turns it with the `rotate` property about the centre
/// of its own box, and the engine applies `rotate` outside `transform`, so in Chromium the two driven cogs swing
/// round the driving cog's middle instead of turning about their own (seen by drawing the component's markup at
/// three moments). Here each cog turns about its own middle, where it meshes: the drawing the component describes.
class WorkingGears extends StatefulWidget {
  const WorkingGears({super.key, this.label = 'Working', this.size, this.color});

  /// What the picture is called for a screen reader.
  final String label;

  /// The text size the cogs sit beside (their `em`): the default text style's when left out.
  final double? size;
  final Color? color;

  @override
  State<WorkingGears> createState() => _WorkingGearsState();
}

class _WorkingGearsState extends State<WorkingGears> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((elapsed) => _elapsed.value = elapsed.inMicroseconds / 1e6);
  final ValueNotifier<double> _elapsed = ValueNotifier(0);
  final _made = workingGears();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (still && _ticker.isActive) {
      _ticker.stop();
      _elapsed.value = 0;
    } else if (!still && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final em = widget.size ?? MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14);
    final ink = widget.color ?? style.color ?? const Color(0xFF000000);
    final height = 1.15 * em;
    final box = _made.box;
    final gap = GlacierTheme.maybeOf(context)?.space(2) ?? 8;
    return Semantics(
      label: widget.label,
      image: true,
      child: Padding(
        padding: EdgeInsetsDirectional.only(end: gap),
        child: CustomPaint(
          size: Size(height * box.width / box.height, height),
          painter: _GearsPainter(_made.cogs, box, ink.withValues(alpha: ink.a * 0.85), _elapsed),
        ),
      ),
    );
  }
}

class _GearsPainter extends CustomPainter {
  _GearsPainter(this.cogs, this.box, this.color, this.elapsed) : super(repaint: elapsed);

  final List<WorkingCog> cogs;
  final Rect box;
  final Color color;
  final ValueNotifier<double> elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.save();
    canvas.scale(size.height / box.height);
    canvas.translate(-box.left, -box.top);
    for (final cog in cogs) {
      canvas.save();
      canvas.translate(cog.at.dx, cog.at.dy);
      canvas.rotate(cog.angleAt(elapsed.value));
      canvas.drawPath(Path.from(svgPath(cog.path))..fillType = PathFillType.evenOdd, paint);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GearsPainter old) => old.color != color || old.box != box;
}

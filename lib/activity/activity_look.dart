/// How the app's running work looks (docs/ACTIVITY.md; Matt, 2026-10-29: "better show users what background processes
/// are happening with vivid colors and iconography"): a colour for each kind, read from the `--activity-*` tokens
/// (assets/css/app.css, which Calm turns to ink), and a small glyph for each that moves gently while the job runs.
///
/// - **Sync**: arrows circling (the pack's refresh glyph, turning).
/// - **AI writing**: a sparkle that shimmers (the pack's sparkles, breathing in light and size).
/// - **Pictures**: a brush stroke drawing itself, rose into amber, its tip a dot.
/// - **Audio**: two reels turning, the cassette's own hubs (lib/tapes/tape_art.dart `_reel`), small.
/// - **Meetings**: the pack's people glyph, pulsing.
/// - **Downloads**: a ring filling round the pack's down arrow, as far as the job is, or round and round.
/// - **Needs you**: a still red dot.
/// - **Waiting**: the kind's glyph dimmed and still.
///
/// Motion stops where the device asks for less (`MediaQuery.disableAnimations`, the kit's `reducedMotion`): each glyph
/// is drawn still, as it rests. The glyphs drawn from Lucide's names follow the icon pack chosen in Settings ›
/// Appearance (lib/art/app_icon.dart); the stroke, the reels and the ring are the app's own, there being no pack glyph
/// for them.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/background_jobs.dart';

/// The token each look wears.
String jobToken(JobLook look) => switch (look) {
      JobLook.sync => 'activity-sync',
      JobLook.ai => 'activity-ai',
      JobLook.images => 'activity-images',
      JobLook.audio => 'activity-audio',
      JobLook.meetings => 'activity-meetings',
      JobLook.downloads => 'activity-downloads',
      JobLook.needsYou => 'activity-needs-you',
      JobLook.waiting => 'activity-waiting',
    };

/// A look's colour on this page, light or dark, vivid or Calm.
Color jobColour(Tokens t, JobLook look) => t.color(jobToken(look));

/// A kind's colour, whatever state its job is in.
Color kindColour(Tokens t, JobKind kind) => jobColour(t, JobLook.values[kind.index]);

/// The look a kind runs in.
JobLook runningLook(JobKind kind) => JobLook.values[kind.index];

/// Whether the glyphs move here: not where the device asks for less motion.
bool activityMoves(BuildContext context) => !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) && !context.tokens.reducedMotion;

/// The Lucide glyph a kind is drawn from, where it is one.
LucideIcon? kindIcon(JobKind kind) => switch (kind) {
      JobKind.sync => Lucide.refreshCw,
      JobKind.ai => Lucide.sparkles,
      JobKind.meetings => Lucide.users,
      JobKind.downloads => Lucide.arrowDown,
      JobKind.images || JobKind.audio => null,
    };

/// A job's glyph at [size]: [kind]'s, drawn as [look] says (running, waiting, needing you), moving while it runs and
/// [moving] allows. [fraction] fills the downloads' ring; null turns it.
class JobGlyph extends StatefulWidget {
  const JobGlyph({super.key, required this.kind, this.look, this.size = 18, this.fraction, this.moving = true, this.color});

  /// A job's own look and kind.
  factory JobGlyph.of(Job job, {Key? key, double size = 18, bool moving = true}) =>
      JobGlyph(key: key, kind: job.kind, look: job.look, size: size, fraction: job.fraction, moving: moving && job.state == JobState.running);

  final JobKind kind;

  /// Null is [kind] running.
  final JobLook? look;
  final double size;
  final double? fraction;
  final bool moving;

  /// In place of the look's own colour.
  final Color? color;

  @override
  State<JobGlyph> createState() => JobGlyphState();
}

/// How long one turn of each kind's motion takes.
Duration kindBeat(JobKind kind) => switch (kind) {
      JobKind.sync => const Duration(milliseconds: 1600),
      JobKind.ai => const Duration(milliseconds: 1800),
      JobKind.images => const Duration(milliseconds: 2200),
      JobKind.audio => const Duration(milliseconds: 2400),
      JobKind.meetings => const Duration(milliseconds: 1600),
      JobKind.downloads => const Duration(milliseconds: 2000),
    };

class JobGlyphState extends State<JobGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: kindBeat(widget.kind));

  /// Whether it is moving now.
  bool get moving => _beat.isAnimating;

  JobLook get _look => widget.look ?? runningLook(widget.kind);

  bool _moves(BuildContext context) => widget.moving && activityMoves(context) && _look != JobLook.waiting && _look != JobLook.needsYou;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(JobGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _beat.duration = kindBeat(widget.kind);
    _sync();
  }

  void _sync() {
    if (_moves(context)) {
      if (!_beat.isAnimating) _beat.repeat();
    } else if (_beat.isAnimating || _beat.value != 0) {
      _beat.stop();
      _beat.value = 0;
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = _look;
    final size = widget.size;
    if (look == JobLook.needsYou) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: Container(key: const ValueKey('job-glyph:dot'), width: size * 0.42, height: size * 0.42, decoration: BoxDecoration(color: widget.color ?? jobColour(t, look), shape: BoxShape.circle))),
      );
    }
    final waiting = look == JobLook.waiting;
    final colour = widget.color ?? (waiting ? kindColour(t, widget.kind) : jobColour(t, look));
    final still = !_moves(context);
    final drawn = AnimatedBuilder(
      animation: _beat,
      builder: (context, _) => _drawn(context, colour, still ? _rest(widget.kind) : _beat.value),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        key: ValueKey('job-glyph:${widget.kind.name}${waiting ? ':waiting' : ''}'),
        dimension: size,
        child: waiting ? Opacity(opacity: 0.45, child: drawn) : drawn,
      ),
    );
  }

  /// Where each kind's motion rests, drawn still: the stroke drawn whole, the ring full where it cannot say.
  static double _rest(JobKind kind) => switch (kind) {
        JobKind.images => 1,
        JobKind.ai => 0.25,
        _ => 0,
      };

  Widget _drawn(BuildContext context, Color colour, double beat) {
    final size = widget.size;
    final t = context.tokens;
    switch (widget.kind) {
      case JobKind.sync:
        return Transform.rotate(angle: beat * 2 * math.pi, child: AppIcon(Lucide.refreshCw, size: size, color: colour, strokeWidth: 2.2));
      case JobKind.ai:
        // The light rising and falling, the sparkle a breath larger at its brightest.
        final glow = 0.5 + 0.5 * math.sin(beat * 2 * math.pi);
        return Opacity(opacity: 0.6 + 0.4 * glow, child: Transform.scale(scale: 0.92 + 0.1 * glow, child: AppIcon(Lucide.sparkles, size: size, color: colour, strokeWidth: 2.1)));
      case JobKind.meetings:
        final pulse = 0.5 - 0.5 * math.cos(beat * 2 * math.pi);
        return Transform.scale(scale: 0.94 + 0.1 * pulse, child: AppIcon(Lucide.users, size: size, color: colour, strokeWidth: 2.1));
      case JobKind.images:
        return CustomPaint(painter: _StrokePainter(beat: beat, from: colour, to: widget.color ?? (widget.look == JobLook.waiting ? colour : t.color('activity-images-2'))));
      case JobKind.audio:
        return CustomPaint(painter: _ReelsPainter(turn: beat, colour: colour));
      case JobKind.downloads:
        final f = widget.fraction;
        return CustomPaint(
          painter: _FillPainter(fraction: f ?? 1, start: f == null ? beat : 0, colour: colour, spinning: f == null),
          child: Center(child: AppIcon(Lucide.arrowDown, size: size * 0.6, color: colour, strokeWidth: 2.6)),
        );
    }
  }
}

/// A brush stroke drawing itself left to right, [from] into [to], its tip a dot: drawn to [beat] of its length over
/// the first two thirds of the beat, held, and let go.
class _StrokePainter extends CustomPainter {
  const _StrokePainter({required this.beat, required this.from, required this.to});

  final double beat;
  final Color from, to;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.12, h * 0.7)
      ..cubicTo(w * 0.3, h * 0.2, w * 0.45, h * 0.95, w * 0.62, h * 0.5)
      ..quadraticBezierTo(w * 0.74, h * 0.2, w * 0.88, h * 0.3);
    final drawn = beat >= 1 ? 1.0 : (beat / 0.66).clamp(0.0, 1.0);
    final fade = beat >= 1 ? 1.0 : (beat < 0.85 ? 1.0 : 1 - (beat - 0.85) / 0.15);
    final metric = path.computeMetrics().first;
    final part = metric.extractPath(0, metric.length * drawn);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.8, w * 0.13)
      ..shader = LinearGradient(colors: [from.withValues(alpha: from.a * fade), to.withValues(alpha: to.a * fade)]).createShader(Offset.zero & size);
    canvas.drawPath(part, paint);
    final tip = metric.getTangentForOffset(metric.length * drawn)?.position;
    if (tip != null && drawn > 0) canvas.drawCircle(tip, w * 0.1, Paint()..color = Color.lerp(from, to, drawn)!.withValues(alpha: fade));
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.beat != beat || old.from != from || old.to != to;
}

/// Two cassette hubs turning, as the tape's own reels are drawn (lib/tapes/tape_art.dart `_reel`): a ring, the
/// spindle hole, and six teeth.
class _ReelsPainter extends CustomPainter {
  const _ReelsPainter({required this.turn, required this.colour});

  final double turn;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = w * 0.22;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, w * 0.09)
      ..color = colour;
    final fill = Paint()..color = colour;
    // The tape between them, under.
    canvas.drawLine(Offset(w * 0.27, h * 0.5 + r), Offset(w * 0.73, h * 0.5 + r), ring);
    for (final cx in [w * 0.27, w * 0.73]) {
      canvas.save();
      canvas.translate(cx, h * 0.5);
      canvas.rotate(turn * 2 * math.pi);
      canvas.drawCircle(Offset.zero, r, ring);
      for (var tooth = 0; tooth < 6; tooth += 1) {
        canvas.save();
        canvas.rotate(tooth * math.pi / 3);
        canvas.drawRect(Rect.fromLTWH(-w * 0.025, -r * 0.62, w * 0.05, r * 0.3), fill);
        canvas.restore();
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ReelsPainter old) => old.turn != turn || old.colour != colour;
}

/// A ring filling: a faint track, and [fraction] of it drawn from the top; [spinning], a quarter of it going round
/// from [start].
class _FillPainter extends CustomPainter {
  const _FillPainter({required this.fraction, required this.start, required this.colour, required this.spinning});

  final double fraction;
  final double start;
  final Color colour;
  final bool spinning;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(1.6, size.width * 0.1);
    final rect = (Offset.zero & size).deflate(stroke / 2 + 0.5);
    canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = colour.withValues(alpha: colour.a * 0.25));
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = colour;
    if (spinning) {
      canvas.drawArc(rect, -math.pi / 2 + start * 2 * math.pi, math.pi / 2, false, arc);
    } else {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction.clamp(0.0, 1.0), false, arc);
    }
  }

  @override
  bool shouldRepaint(_FillPainter old) => old.fraction != fraction || old.start != start || old.colour != colour || old.spinning != spinning;
}

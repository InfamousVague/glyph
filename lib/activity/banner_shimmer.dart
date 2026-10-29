/// A note's banner being made, shown where it will land (docs/ACTIVITY.md, In place; Matt, 2026-10-29: "Banner
/// shimmer where the banner will land"): a band at the banner's size and shape in the images' colour, a sheen sweeping
/// across it, and the brush stroke drawing itself over it, until the picture lands and fades in over it
/// (lib/note/note_banner.dart [NoteBannerView]).
///
/// Calm draws it in ink, as every `--activity-*` colour is. Where the device asks for less motion the band is still,
/// its sheen in the middle and the stroke drawn whole.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'activity_look.dart';
import '../core/background_jobs.dart';

/// How long one sweep of the sheen and one stroke take.
const Duration bannerShimmerBeat = Duration(milliseconds: 2200);

/// The band, [width] by [height], its corners [radius].
class BannerShimmer extends StatefulWidget {
  const BannerShimmer({super.key, required this.width, required this.height, this.radius = 0});

  final double width, height, radius;

  @override
  State<BannerShimmer> createState() => BannerShimmerState();
}

class BannerShimmerState extends State<BannerShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(vsync: this, duration: bannerShimmerBeat);

  /// Whether it is moving now.
  bool get moving => _beat.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (activityMoves(context)) {
      if (!_beat.isAnimating) _beat.repeat();
    } else {
      _beat.stop();
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
    final from = jobColour(t, JobLook.images), to = t.color('activity-images-2');
    final still = !activityMoves(context);
    return Semantics(
      label: 'Making a header image',
      liveRegion: true,
      image: true,
      child: ClipRRect(
        key: const ValueKey('banner-shimmer'),
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _beat,
            builder: (context, _) => CustomPaint(painter: BannerShimmerPainter(beat: still ? null : _beat.value, from: from, to: to)),
          ),
        ),
      ),
    );
  }
}

/// The band: a wash of [from], a sheen of [to] across it at [beat] (null: still, in the middle), and a brush stroke
/// drawn [beat] of the way across its middle, [from] into [to], its tip a dot.
class BannerShimmerPainter extends CustomPainter {
  const BannerShimmerPainter({required this.beat, required this.from, required this.to});

  final double? beat;
  final Color from, to;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = from.withValues(alpha: from.a * 0.12));
    // The sheen: a soft band a third as wide as the banner, leaning, from off the start to off the end.
    final at = beat ?? 0.5;
    final centre = -0.35 * w + at * 1.7 * w;
    final band = w * 0.34;
    canvas.drawRect(
      box,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [to.withValues(alpha: 0), to.withValues(alpha: to.a * 0.22), to.withValues(alpha: 0)],
          stops: const [0, 0.5, 1],
          transform: const GradientRotation(-0.25),
        ).createShader(Rect.fromLTWH(centre - band / 2, 0, band, h)),
    );
    // The stroke: across the middle third, drawn over the first two thirds of the beat, held, and let go.
    final path = Path()
      ..moveTo(w * 0.3, h * 0.58)
      ..cubicTo(w * 0.4, h * 0.3, w * 0.48, h * 0.78, w * 0.57, h * 0.5)
      ..quadraticBezierTo(w * 0.64, h * 0.32, w * 0.7, h * 0.4);
    final b = beat;
    final drawn = b == null ? 1.0 : (b / 0.66).clamp(0.0, 1.0);
    final fade = b == null || b < 0.85 ? 1.0 : 1 - (b - 0.85) / 0.15;
    if (drawn <= 0) return;
    final metric = path.computeMetrics().first;
    final stroke = math.max(3.0, h * 0.045);
    canvas.drawPath(
      metric.extractPath(0, metric.length * drawn),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..shader = LinearGradient(colors: [from.withValues(alpha: from.a * fade), to.withValues(alpha: to.a * fade)]).createShader(Rect.fromLTWH(w * 0.3, 0, w * 0.4, h)),
    );
    final tip = metric.getTangentForOffset(metric.length * drawn)?.position;
    if (tip != null) canvas.drawCircle(tip, stroke * 0.8, Paint()..color = Color.lerp(from, to, drawn)!.withValues(alpha: fade));
  }

  @override
  bool shouldRepaint(BannerShimmerPainter old) => old.beat != beat || old.from != from || old.to != to;
}

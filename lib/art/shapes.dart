import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The guide's picture (art/Shapes.tsx `Tips`, art/Shapes.module.css): a lid lifting off a box and settling back,
/// in the page's own ink, for the guide's last page. Flat, drawn on one colour only, so a page sets its weight with
/// [color] and it turns with the theme. Square, sized by the page, and decoration only.
///
/// It moves on a loop with long rests: the lid lifts, hangs there a moment, and settles with a little bounce, over
/// 4.4 seconds. With reduced motion it stands still in its finished pose, which is the box with its lid on.
class TipsShape extends StatefulWidget {
  const TipsShape({super.key, this.size = 120, this.color});

  final double size;
  final Color? color;

  /// The lid at [t] of its loop, 0 to 1: how far it has moved, in the drawing's own 120 units, and how far it has
  /// turned, in degrees. The stylesheet's `lid` keyframes, each stretch eased by `cubic-bezier(0.3, 0.7, 0.3, 1)`.
  static ({Offset move, double turn}) lidAt(double t) {
    const frames = <(double, Offset, double)>[
      (0, Offset.zero, 0),
      (0.20, Offset.zero, 0),
      (0.34, Offset(-3, -14), -16),
      (0.60, Offset(-3, -14), -16),
      (0.74, Offset(0, 2), 0),
      (0.80, Offset.zero, 0),
      (1, Offset.zero, 0),
    ];
    const ease = Cubic(0.3, 0.7, 0.3, 1);
    for (var i = 0; i + 1 < frames.length; i++) {
      final (from, moveA, turnA) = frames[i];
      final (to, moveB, turnB) = frames[i + 1];
      if (t <= to) {
        final local = ease.transform(((t - from) / (to - from)).clamp(0.0, 1.0));
        return (move: Offset.lerp(moveA, moveB, local)!, turn: turnA + (turnB - turnA) * local);
      }
    }
    return (move: Offset.zero, turn: 0);
  }

  @override
  State<TipsShape> createState() => _TipsShapeState();
}

class _TipsShapeState extends State<TipsShape> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 4400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _loop
        ..stop()
        ..value = 0;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    return ExcludeSemantics(child: CustomPaint(size: Size.square(widget.size), painter: _TipsPainter(ink, _loop)));
  }
}

class _TipsPainter extends CustomPainter {
  _TipsPainter(this.color, this.loop) : super(repaint: loop);
  final Color color;
  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.save();
    canvas.scale(size.width / 120, size.height / 120);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(34, 58, 52, 38), const Radius.circular(5)), paint);
    final lid = TipsShape.lidAt(loop.value);
    // The lid turns about a point a tenth along its own foot (`transform-origin: 10% 100%` of its own box).
    const origin = Offset(30 + 6, 44 + 10);
    canvas.translate(origin.dx + lid.move.dx, origin.dy + lid.move.dy);
    canvas.rotate(lid.turn * math.pi / 180);
    canvas.translate(-origin.dx, -origin.dy);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(30, 44, 60, 10), const Radius.circular(5)), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TipsPainter old) => old.color != color;
}

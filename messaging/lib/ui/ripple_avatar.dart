import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../kit/settings_type.dart';
import '../kit/semantic_colors.dart';

/// A face in a call, with wobbly rings going out from it while they talk (Matt, 2026-11-15: "make the profile
/// picture habe wobbly ripples going out when talking"). [level] is how loud they are now, 0 to 1 (lib/voice/rtc.dart
/// reads it from WebRTC): the rings come and go with it, wobble more the louder it is, and are still when quiet.
class RippleAvatar extends StatefulWidget {
  const RippleAvatar({super.key, required this.name, required this.level, this.size = 44, this.color, this.muted = false, this.ringed = false});

  /// A green ring round the face even while quiet: a call that is on.
  final bool ringed;
  final String name;
  final double level;
  final double size;
  final Color? color;
  final bool muted;

  /// Louder than this is talking.
  static const talking = 0.04;

  @override
  State<RippleAvatar> createState() => _RippleAvatarState();
}

class _RippleAvatarState extends State<RippleAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  double _strength = 0;

  @override
  void didUpdateWidget(RippleAvatar old) {
    super.didUpdateWidget(old);
    _follow();
  }

  @override
  void initState() {
    super.initState();
    _follow();
  }

  void _follow() {
    final speaking = !widget.muted && widget.level > RippleAvatar.talking;
    if (speaking && !_time.isAnimating) _time.repeat();
    // The rings fade out by themselves once quiet; the clock stops when they are gone.
    if (!speaking && _strength < 0.02 && _time.isAnimating) _time.stop();
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = widget.color ?? t.online;
    final want = widget.muted ? 0.0 : (widget.level <= RippleAvatar.talking ? 0.0 : (0.35 + widget.level * 1.6).clamp(0.0, 1.0));
    final letter = (widget.name.replaceAll('@', '').trim().characters.firstOrNull ?? '?').toUpperCase();
    // As big as the face: the rings spill past it, over what is around, rather than holding a row apart.
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _time,
        builder: (context, _) {
          // Eased towards how loud they are, frame by frame.
          _strength += (want - _strength) * (want > _strength ? 0.35 : 0.08);
          if (_strength < 0.02 && want == 0 && _time.isAnimating) WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
          return CustomPaint(
            painter: _Ripples(time: _time.value, strength: _strength, color: ink, radius: widget.size / 2),
            child: OverflowBox(
              maxWidth: widget.size,
              maxHeight: widget.size,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.color('app-paper-3'),
                  border: Border.all(color: _strength > 0.05 ? ink.withValues(alpha: (0.4 + _strength * 0.6).clamp(0, 1)) : (widget.ringed ? ink : t.color('app-rule')), width: _strength > 0.05 || widget.ringed ? 2.5 : 1),
                ),
                alignment: Alignment.center,
                child: Text(letter, style: pageText(t, widget.size * 0.4, weight: 'bold', color: t.color('app-ink'))),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Ripples extends CustomPainter {
  _Ripples({required this.time, required this.strength, required this.color, required this.radius});
  final double time;
  final double strength;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength < 0.02) return;
    final c = size.center(Offset.zero);
    const rings = 3;
    for (var i = 0; i < rings; i++) {
      // Each ring goes out and fades, a third of the way behind the one before.
      final phase = (time + i / rings) % 1.0;
      final r = radius + phase * radius * 0.85;
      final wobble = 0.06 * strength * (1 - phase * 0.5);
      final path = Path();
      const steps = 64;
      for (var s = 0; s <= steps; s++) {
        final a = s / steps * math.pi * 2;
        // Two waves going round at different speeds: a wobble, not a gear.
        final d = r * (1 + wobble * math.sin(a * 5 + time * math.pi * 4 + i) + wobble * 0.6 * math.sin(a * 3 - time * math.pi * 6));
        final p = c + Offset(math.cos(a) * d, math.sin(a) * d);
        s == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1 - phase) + 0.6
          ..color = color.withValues(alpha: (1 - phase) * 0.7 * strength),
      );
    }
  }

  @override
  bool shouldRepaint(_Ripples old) => old.time != time || old.strength != strength || old.color != color;
}

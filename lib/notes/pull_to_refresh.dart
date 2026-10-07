/// Pull a page down from its top to refresh it. A port of `src/app/notes/PullToRefresh.tsx` and
/// PullToRefresh.module.css (docs/DESIGN.md §152); its pure half is `core/pull.dart`.
///
/// It is felt the way the swipes are: light ticks quicken as the page nears the detent, a firm click says it is
/// there, and the lightest says it was backed out of; the refresh done, a light tap. It is shown too: under the top
/// bar, in the gap the page leaves as it comes down, a ring fills round an arrow as the detent nears, the arrow turns
/// once it is armed, the ring spins while the refresh runs, and a tick says it is done. A let-go short of the detent
/// does nothing, and the page goes back up. Only a touch that is plainly a pull is one (`pullIntent`): down, more
/// than across, from a page already at its top, and at once.
///
/// What differs:
/// - The web listened to its scroller's touches and moved the scroller's children by `translate`. Here this widget
///   wraps the scroller, watches the pointers that land on it, and hands the scroller's builder how far its content
///   is down ([PullDown]); the page moves its own content by it with [PullLowered], and gives the scroller
///   [PullDown.physics], which holds the page still while it is being pulled (the web called `preventDefault`).
/// - The ring is this widget's own child, placed at [top], where the web fixed it to the window from a measurement.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/detent_feel.dart';
import '../core/pull.dart';
import '../home/home_icons.dart';

enum _Phase { idle, pulling, refreshing, done }

/// How far the page's content is down, for the scroller a [PullToRefresh] builds.
class PullDown {
  const PullDown({required this.offset, required this.settling, required this.physics});

  /// In logical pixels, 0 at rest.
  final double offset;

  /// Whether it is settling to [offset] (a let-go, a refresh ending) rather than under the finger.
  final bool settling;

  /// The scroller's physics while this is in force: the page does not scroll under a pull.
  final ScrollPhysics physics;
}

/// The page's content, down by a [PullDown]: `translate: 0 <px>`, with `transition: translate 240ms ease-out` while
/// it settles and none while the finger drives it.
class PullLowered extends StatelessWidget {
  const PullLowered({super.key, required this.pull, required this.child});

  final PullDown pull;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: pull.offset),
      duration: pull.settling ? const Duration(milliseconds: 240) : Duration.zero,
      curve: t.curve('glacier-ease-out'),
      builder: (context, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
      child: child,
    );
  }
}

/// Pull to refresh (`src/app/notes/PullToRefresh.tsx`), wrapped round the scroller it watches and handing it how
/// far its content is down, where the web's listened to the scroller's touches and moved its children itself.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({super.key, required this.controller, required this.onRefresh, this.enabled = true, required this.top, required this.builder});

  /// The page's scroller's: a pull starts only from its top.
  final ScrollController controller;

  /// The refresh itself; the ring spins until it settles, and at least [pullLeastMs]. It may fail: the page goes back
  /// up either way.
  final Future<void> Function() onRefresh;

  /// Off where the page does not scroll, or while it is showing something a pull should leave alone.
  final bool enabled;

  /// Where the gap opens, from this widget's top: the scroller's top, below its padding (the bar).
  final double top;

  /// The scroller, built with how far its content is down.
  final Widget Function(BuildContext context, PullDown pull) builder;

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _Gesture {
  _Gesture(this.pointer, this.x, this.y, this.at);
  final int pointer;
  final double x, y;
  final Duration at;
  bool pulling = false;
  bool armed = false;
  final Approaching approaching = Approaching();
}

class _PullToRefreshState extends State<PullToRefresh> {
  double _offset = 0;
  bool _settling = false;
  _Phase _phase = _Phase.idle;
  _Gesture? _gesture;
  bool _busy = false;
  int _touches = 0;
  final List<Timer> _timers = [];

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  bool get _atTop => !widget.controller.hasClients || widget.controller.position.pixels <= 0;

  /// The page's content down by [px], following the finger or settling to it.
  void _lower(double px, {required bool settle, _Phase? phase}) {
    if (!mounted) return;
    setState(() {
      _offset = px;
      _settling = settle;
      if (phase != null) _phase = phase;
    });
  }

  void _down(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touches += 1;
    if (_busy || !widget.enabled || _touches != 1) {
      _gesture = null;
      return;
    }
    _gesture = _Gesture(event.pointer, event.position.dx, event.position.dy, event.timeStamp);
  }

  void _move(PointerMoveEvent event) {
    final gesture = _gesture;
    if (gesture == null || gesture.pointer != event.pointer) return;
    final dx = event.position.dx - gesture.x, dy = event.position.dy - gesture.y;
    if (!gesture.pulling) {
      final intent = pullIntent(dx, dy, _atTop, (event.timeStamp - gesture.at).inMilliseconds);
      if (intent == PullIntent.undecided) return;
      if (intent == PullIntent.other) {
        _gesture = null;
        return;
      }
      gesture.pulling = true;
      _phase = _Phase.pulling;
    }
    final px = pullOffset(dy);
    final fire = HapticsProvider.of(context);
    if (tickNow(gesture.approaching, const [1], px / pullDetentPx, event.timeStamp.inMicroseconds / 1000)) fire(HapticKind.selection);
    final now = pullArmed(px);
    if (now != gesture.armed) {
      // Out through the detent a firm click; back through it the lightest, so the two directions feel different.
      fire(now ? HapticKind.medium : HapticKind.selection);
      gesture.armed = now;
    }
    _lower(px, settle: false);
  }

  void _up(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touches = math.max(0, _touches - 1);
    final was = _gesture;
    if (was == null || was.pointer != event.pointer) return;
    _gesture = null;
    if (!was.pulling) return;
    if (!was.armed) {
      _lower(0, settle: true, phase: _Phase.idle);
      return;
    }
    _busy = true;
    _lower(pullRestPx, settle: true, phase: _Phase.refreshing);
    final fire = HapticsProvider.of(context);
    final least = Completer<void>();
    _timers.add(Timer(const Duration(milliseconds: pullLeastMs), least.complete));
    // It may fail: the page goes back up either way.
    final refresh = Future<void>.sync(widget.onRefresh).catchError((Object _) {});
    Future.wait<void>([refresh, least.future]).then((_) {
      if (!mounted) return;
      fire(HapticKind.light);
      setState(() => _phase = _Phase.done);
      _timers.add(
        Timer(const Duration(milliseconds: 350), () {
          _busy = false;
          _lower(0, settle: true, phase: _Phase.idle);
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pulling = _phase != _Phase.idle;
    final armed = pullArmed(_offset);
    final progress = math.min(1.0, _offset / pullDetentPx);
    final lit = armed || _phase == _Phase.refreshing || _phase == _Phase.done;
    final ink = lit ? t.color('app-ink') : t.color('app-ink-2');
    final size = t.lenOf('2.5rem');
    final said = switch (_phase) { _Phase.refreshing => 'Refreshing', _Phase.done => 'Up to date', _ => armed ? 'Let go to refresh' : '' };

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.builder(
              context,
              PullDown(offset: _offset, settling: _settling, physics: _gesture?.pulling == true || _busy ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics()),
            ),
          ),
          if (pulling)
            Positioned(
              // In the gap the page leaves: across its middle, half way down what has opened.
              top: widget.top + _offset / 2 - size / 2,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    label: said,
                    child: Opacity(
                      opacity: lit ? 1 : 0.25 + progress * 0.75,
                      child: Transform.scale(
                        scale: 0.6 + progress * 0.4,
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.color('app-paper-2'),
                            // `box-shadow: 0 1px 0 var(--app-rule)`.
                            boxShadow: [BoxShadow(color: t.color('app-rule'), offset: const Offset(0, 1))],
                          ),
                          child: CustomPaint(
                            painter: _PullRing(progress: progress, color: ink.withValues(alpha: armed ? 1 : 0.6)),
                            child: Center(
                              child: switch (_phase) {
                                _Phase.refreshing => _Spin(reduced: t.reducedMotion, child: HomeIcon(HomeGlyph.loader, size: 18, strokeWidth: 2.4, color: ink)),
                                _Phase.done => HomeIcon(HomeGlyph.check, size: 18, strokeWidth: 2.6, color: ink),
                                // The arrow turns over once a let-go would refresh: it points at what happens next.
                                _ => AnimatedRotation(
                                    turns: armed ? 0.5 : 0,
                                    duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 160),
                                    curve: t.curve('glacier-ease-out'),
                                    child: HomeIcon(HomeGlyph.arrowDown, size: 18, strokeWidth: 2.4, color: ink),
                                  ),
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.ring circle`: radius 18 in a box of 40, stroked 2.5, from twelve o'clock for as far as the pull has come.
class _PullRing extends CustomPainter {
  _PullRing({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final unit = size.width / 40;
    canvas.drawArc(
      Rect.fromCircle(center: size.center(Offset.zero), radius: 18 * unit),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * unit
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PullRing old) => old.progress != progress || old.color != color;
}

/// `animation: spin 800ms linear infinite`, a third as fast under reduced motion.
class _Spin extends StatefulWidget {
  const _Spin({required this.reduced, required this.child});
  final bool reduced;
  final Widget child;

  @override
  State<_Spin> createState() => _SpinState();
}

class _SpinState extends State<_Spin> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: Duration(milliseconds: widget.reduced ? 2400 : 800))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _controller, child: widget.child);
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import 'eyes.dart';

/// Where the account's sync stands (`core/sync/engine.ts` `SyncStatus.phase`). The engine itself is stage 7; the
/// launch screen only needs the word.
enum SyncPhase { off, idle, syncing, error }

/// What the launch screen reads of the app's updates (`core/ota.ts` `Updates`): whether a check is running, what it
/// found, and how to ask.
///
/// The web app has two kinds of update, a newer page ([readyBuild], loaded by [reload]) and a newer app (the APK,
/// [apkVersion]). A Flutter app has no page to load, so nothing gives [readyBuild] yet; the lines and the hand-over
/// are kept as the web has them for whatever stage 9 turns out to check.
class LaunchUpdates {
  const LaunchUpdates({this.readyBuild, this.apkVersion, this.checking = false, this.lastError, required this.check, required this.reload});

  /// A newer build is downloaded and runs on [reload] (`ready.build`).
  final String? readyBuild;

  /// A newer app is out (`apk.kind === 'available'`), by its version.
  final String? apkVersion;
  final bool checking;
  final String? lastError;
  final VoidCallback check;
  final VoidCallback reload;

  /// Updates that never check: a build with nowhere to ask.
  static const LaunchUpdates none = LaunchUpdates(check: _nothing, reload: _nothing);

  static void _nothing() {}
}

/// Long enough to read the lines; short enough not to be a wait.
const Duration shortest = Duration(milliseconds: 900);

/// The update check stops holding the door after this: it carries on, and says what it found in the usual places.
const Duration longest = Duration(milliseconds: 3000);
const Duration fade = Duration(milliseconds: 260);

/// A check that hasn't started by now isn't going to: this build or this device doesn't check.
const Duration skipAfter = Duration(milliseconds: 500);

/// How long "Updating" is shown before the reload: long enough to be read as the reason the launch starts again.
const Duration applyBeat = Duration(milliseconds: 450);

enum _LineState { working, done, note }

typedef _Line = ({String key, _LineState state, String words});

/// What the app shows while it opens (`launch/LaunchScreen.tsx`; Matt: "I want a loading screen with the logo and
/// checking for updates and stuff and show statuses for checking for updates etc"): the icon, the name, and a line for
/// each thing opening does, each turning to a tick as it's done.
///
/// It goes when the notes are read and the update check has answered, or three seconds on, whichever is first, so a
/// slow network never holds anyone at the door; and it stays at least long enough to be read rather than flash. Once
/// ready the ghost looks out of the screen and winks, then the screen fades and [onDone] hands over.
///
/// Differs from the web: its clock was a 150 ms beat compared against `Date.now()`; here each wait is a timer of its
/// own, so the moments are exact. And [claimAutoReload] and [recording] are asked of the caller, where the web read
/// local storage and the meeting recorder itself: neither exists here yet.
class LaunchScreen extends StatefulWidget {
  const LaunchScreen({
    super.key,
    required this.loading,
    required this.notes,
    required this.onDone,
    this.updates = LaunchUpdates.none,
    this.sync = SyncPhase.off,
    this.holdUpdate = false,
    this.claimAutoReload,
    this.recording,
  });

  final bool loading;
  final int notes;
  final LaunchUpdates updates;
  final SyncPhase sync;

  /// Leave an update for later: the app was opened to record, which a reload would end.
  final bool holdUpdate;

  /// Whether [LaunchUpdates.readyBuild] may be loaded now: once for a build (`core/ota.ts` `claimAutoReload`), so a
  /// build that will not come up cannot loop the launch. Without it, never.
  final bool Function(String build)? claimAutoReload;

  /// Whether a recording is running (`meetingStateNow()?.recording`): a reload would end it.
  final bool Function()? recording;
  final VoidCallback onDone;

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen> {
  bool _pastShortest = false;
  bool _pastLongest = false;
  bool _begun = false;
  bool _skipped = false;
  bool _applying = false;
  bool _latched = false;
  bool _leaving = false;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _begun = widget.updates.checking;
    // The update check, now: this screen is the moment the answer is worth having. After the frame, as an effect
    // runs after its render: asking may tell the caller something that rebuilds this.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.updates.check();
      if (_takeUpdate()) setState(() {});
    });
    _after(shortest, () => _pastShortest = true);
    _after(longest, () => _pastLongest = true);
    _after(skipAfter, () {
      if (!_begun) _skipped = true;
    });
  }

  void _after(Duration wait, VoidCallback then) {
    _timers.add(Timer(wait, () {
      if (mounted) setState(then);
    }));
  }

  @override
  void didUpdateWidget(LaunchScreen old) {
    super.didUpdateWidget(old);
    if (widget.updates.checking) _begun = true;
    _takeUpdate();
  }

  /// An update found while this screen is up: loaded now, after a beat for its line to be read. True when it took one.
  bool _takeUpdate() {
    final build = widget.updates.readyBuild;
    if (build == null || _applying || _leaving || widget.holdUpdate) return false;
    if (widget.recording?.call() ?? false) return false;
    if (!(widget.claimAutoReload?.call(build) ?? false)) return false;
    _applying = true;
    _timers.add(Timer(applyBeat, () {
      if (mounted) widget.updates.reload();
    }));
    return true;
  }

  void _winked() {
    if (_leaving || !mounted) return;
    setState(() => _leaving = true);
    _timers.add(Timer(fade, () {
      if (mounted) widget.onDone();
    }));
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final updates = widget.updates;
    final checked = _skipped || (_begun && !updates.checking);
    // Ready once, and ready from then on: a second check starting mid-fade can't hold the screen up again. Not while
    // an update is being taken: the app is about to start again, and the ghost's wink is the new build's to give.
    if (!_applying && !widget.loading && _pastShortest && (checked || _pastLongest)) _latched = true;

    final lines = <_Line>[
      widget.loading
          ? (key: 'notes', state: _LineState.working, words: 'Opening your notes')
          : (key: 'notes', state: _LineState.done, words: widget.notes == 1 ? '1 note' : '${widget.notes} notes'),
      if (!_skipped)
        _applying
            ? (key: 'updates', state: _LineState.working, words: 'Updating Ghost.md')
            : !checked
                ? (key: 'updates', state: _LineState.working, words: 'Checking for updates')
                : updates.readyBuild != null
                    ? (key: 'updates', state: _LineState.done, words: 'An update is ready for next time')
                    : updates.apkVersion != null
                        ? (key: 'updates', state: _LineState.note, words: 'Ghost.md ${updates.apkVersion} is out')
                        : updates.lastError != null
                            ? (key: 'updates', state: _LineState.note, words: 'Couldn’t check for updates')
                            : (key: 'updates', state: _LineState.done, words: 'Up to date'),
      if (widget.sync != SyncPhase.off)
        widget.sync == SyncPhase.syncing
            ? (key: 'sync', state: _LineState.working, words: 'Syncing your devices')
            : widget.sync == SyncPhase.error
                ? (key: 'sync', state: _LineState.note, words: 'Sync will try again')
                : (key: 'sync', state: _LineState.done, words: 'In sync'),
    ];

    final still = t.reducedMotion;
    final ease = t.curve('glacier-ease-out');
    final title = t.fontSize('2xl');
    final small = t.fontSize('sm');
    // `.launch`: a grid with everything in its middle, `--glacier-space-3` between the three; the name's own margins
    // (space-2 above, space-3 below) add to that, as a grid's gaps and its items' margins do not collapse.
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Opening Ghost.md',
      child: IgnorePointer(
        ignoring: _leaving,
        child: AnimatedOpacity(
          opacity: _leaving ? 0 : 1,
          duration: fade,
          curve: ease,
          child: ColoredBox(
            color: t.color('glacier-bg'),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Rise(duration: const Duration(milliseconds: 420), curve: ease, still: still, child: _IconChase(finishing: _latched, onFinished: _winked)),
                  SizedBox(height: t.space(3) + t.space(2)),
                  _Rise(
                    duration: const Duration(milliseconds: 420),
                    delay: const Duration(milliseconds: 60),
                    curve: ease,
                    still: still,
                    // `.name`: the page's own text, `line-height: normal`, where the kit's sizes carry a leading of their own.
                    child: Text('Ghost.md', style: t.textAt(title, weight: 'bold', tracking: t.len('app-tracking-title', em: title))),
                  ),
                  SizedBox(height: t.space(3) + t.space(3)),
                  // `.lines`: a grid at least 5.4em tall whose rows share what is left over, each line in the middle
                  // of its row; which is what spaceAround gives lines of one height.
                  ConstrainedBox(
                    key: const ValueKey('launch-lines'),
                    constraints: BoxConstraints(minHeight: 5.4 * small),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 0.55 * small,
                      children: [
                        for (final line in lines)
                          _Rise(
                            key: ValueKey(line.key),
                            duration: const Duration(milliseconds: 320),
                            curve: ease,
                            still: still,
                            child: _LineRow(line: line, still: still),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.line`: its mark, then its words; in the page's ink once done, muted until then.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.still});

  final _Line line;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.color(line.state == _LineState.done ? 'glacier-text' : 'glacier-text-muted');
    final em = t.fontSize('sm');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            key: const ValueKey('launch-mark'),
            width: 1.1 * em,
            child: Center(
              child: switch (line.state) {
                _LineState.working => _Turn(still: still, child: _Mark(Lucide.loaderCircle, color: color, strokeWidth: 2.4)),
                _LineState.done => _Mark(Lucide.check, color: color, strokeWidth: 2.6),
                _LineState.note => _Mark(Lucide.circleAlert, color: color, strokeWidth: 2.4),
              },
            ),
          ),
        ),
        SizedBox(width: 0.55 * em),
        Text(line.words, style: t.textAt(em, color: color)),
      ],
    );
  }
}

/// One of the three Lucide marks a line wears, 14 px: `LoaderCircle` and `CircleAlert` at a stroke of 2.4, `Check`
/// at 2.6 (LaunchScreen.tsx). The kit's own paths at the web's stroke, and in the alert's ring the wash the page
/// gives a closed icon (iconWash.css).
class _Mark extends StatelessWidget {
  const _Mark(this.icon, {required this.color, required this.strokeWidth});

  final LucideIcon icon;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => AppIcon(icon, size: 14, strokeWidth: strokeWidth, color: color);
}

/// `@keyframes turn`: once round every 900 ms, for as long as the line is working.
class _Turn extends StatefulWidget {
  const _Turn({required this.still, required this.child});

  final bool still;
  final Widget child;

  @override
  State<_Turn> createState() => _TurnState();
}

class _TurnState extends State<_Turn> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (!widget.still) _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _turn, child: widget.child);
}

/// `@keyframes rise`: from clear and 6 px low to where it belongs, once, as it arrives.
class _Rise extends StatefulWidget {
  const _Rise({super.key, required this.duration, required this.curve, required this.still, required this.child, this.delay = Duration.zero});

  final Duration duration;
  final Duration delay;
  final Curve curve;
  final bool still;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(vsync: this, duration: widget.duration);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.still) {
      _rise.value = 1;
    } else if (widget.delay == Duration.zero) {
      _rise.forward();
    } else {
      _wait = Timer(widget.delay, _rise.forward);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _rise,
      child: widget.child,
      builder: (context, child) {
        final at = widget.curve.transform(_rise.value);
        return Opacity(opacity: at, child: Transform.translate(offset: Offset(0, 6 * (1 - at)), child: child));
      },
    );
  }
}

/// A squircle's outline: a superellipse, |x|^n + |y|^n = 1, the shape of an app icon's corners rather than a rounded
/// rectangle's, centred at ([c], [c]) with half-width [r]. The points are the web's, to the hundredth it rounds to.
List<Offset> squircle(double c, double r, {double n = 5, int steps = 96}) {
  double part(double v) => (c + r * v.sign * math.pow(v.abs(), 2 / n)).toDouble();
  double hundredth(double v) => (v * 100).round() / 100;
  return [
    for (var i = 0; i < steps; i += 1) Offset(hundredth(part(math.cos(i / steps * math.pi * 2))), hundredth(part(math.sin(i / steps * math.pi * 2)))),
  ];
}

/// The drawing's box, the icon's squircle inside it, and the ring the bar runs round, a little outside the icon.
const double box = 128;
final List<Offset> _icon = squircle(box / 2, 48);
final List<Offset> _ring = squircle(box / 2, 58);
final Path _iconPath = Path()..addPolygon(_icon, true);
final Path _ringPath = Path()..addPolygon(_ring, true);

/// The ring twice round as one line, so a bar that crosses where the ring starts is still one stroke.
final PathMetric _ringTwice = (Path()..addPolygon([..._ring, ..._ring, _ring.first], false)).computeMetrics().first;
final double _lap = _ringTwice.length / 2;

/// `@keyframes wink`: one eye shut and open again, held shut a moment in the middle. [at] is 0 to 1 of the wink.
double winkScale(double at) {
  if (at <= 0 || at >= 1) return 1;
  if (at < 0.30) return 1 - 0.9 * Curves.easeInOut.transform(at / 0.30);
  if (at <= 0.62) return 0.1;
  return 0.1 + 0.9 * Curves.easeInOut.transform((at - 0.62) / 0.38);
}

/// What one frame of the chase draws.
class _Frame extends ChangeNotifier {
  /// Where the bar starts, in laps of the ring.
  double lap = 0;
  final List<Offset> looking = [for (final _ in eyes) Offset.zero];

  /// The bar and its track, fading once the app is open.
  double ring = 1;
  double wink = 1;

  void drawn() => notifyListeners();
}

/// The app's icon in a squircle, and a short bar chasing round a ring outside it while the app opens (`IconChase`;
/// Matt: "put the app logo in a squircle with a black bar that chases around the outside of the squircle"). The bar
/// is the page's ink, on a faint track of the same ring.
///
/// And the ghost watches it (eyes.dart): the picture's eyes are painted out and drawn again over it, and each frame
/// both turn toward the bar's middle, catching up with it as eyes do. The bar and the eyes run off one clock.
///
/// When the app is open ([finishing]), the bar fades and the ghost turns to look out of the screen, at whoever is
/// holding it, and winks; [onFinished] says the wink is over, for the screen to fade. Asked for less motion, the bar
/// stands still where the ring starts, the eyes look ahead, and there is no wink to wait for.
class _IconChase extends StatefulWidget {
  const _IconChase({required this.finishing, required this.onFinished});

  final bool finishing;
  final VoidCallback onFinished;

  @override
  State<_IconChase> createState() => _IconChaseState();
}

class _IconChaseState extends State<_IconChase> with SingleTickerProviderStateMixin {
  final _Frame _frame = _Frame();
  Ticker? _ticker;
  Duration _last = Duration.zero;
  Duration _now = Duration.zero;

  /// When the app was open, and when the wink began, on the ticker's clock.
  Duration? _finishedAt;
  Duration? _winkAt;
  Timer? _wink;
  Timer? _done;
  bool _told = false;

  /// Whether the eyes are moving at all: a still ghost has no look or wink to give. Asked once, as it starts.
  bool? _moving;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_moving != null) return;
    _moving = !context.tokens.reducedMotion;
    if (_moving!) _ticker = createTicker(_tick)..start();
    if (widget.finishing) _finish();
  }

  @override
  void didUpdateWidget(_IconChase old) {
    super.didUpdateWidget(old);
    if (widget.finishing && !old.finishing) _finish();
  }

  /// The look out, then the wink, then done; at once for a ghost that isn't moving.
  void _finish() {
    if (_told) return;
    if (!_moving!) {
      _told = true;
      // After the frame: this is told from a build, and the screen above answers by rebuilding.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFinished();
      });
      return;
    }
    _finishedAt = _now;
    _wink = Timer(const Duration(milliseconds: lookOutMs), () => _winkAt = _now);
    _done = Timer(const Duration(milliseconds: lookOutMs + winkMs), () {
      _told = true;
      if (mounted) widget.onFinished();
    });
  }

  void _tick(Duration now) {
    _now = now;
    final ms = now.inMicroseconds / 1000;
    final bar = barAt(ms);
    _frame.lap = -bar.offset / 100;
    final target = _ringTwice.getTangentForOffset(bar.middle * _lap)!.position;
    final ease = easeFor(math.min(64, (now - _last).inMicroseconds / 1000));
    _last = now;
    for (var i = 0; i < eyes.length; i += 1) {
      // Looking out of the screen is looking at no point on it: both eyes back to the middle of where they were.
      final to = _finishedAt != null ? Offset.zero : lookAt(eyes[i], target);
      _frame.looking[i] += (to - _frame.looking[i]) * ease;
    }
    final finished = _finishedAt;
    if (finished != null) {
      // `.chase[data-finishing] .bar { opacity: 0; transition: opacity 200ms var(--glacier-ease-out) }`
      final gone = ((now - finished).inMicroseconds / 200000).clamp(0.0, 1.0);
      _frame.ring = 1 - context.tokens.curve('glacier-ease-out').transform(gone);
    }
    final wink = _winkAt;
    _frame.wink = wink == null ? 1 : winkScale((now - wink).inMicroseconds / (winkMs * 1000));
    _frame.drawn();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _wink?.cancel();
    _done?.cancel();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.tokens.color('glacier-text');
    return ExcludeSemantics(
      child: SizedBox.square(
        key: const ValueKey('launch-chase'),
        dimension: box,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipPath(
                clipper: const _IconClip(),
                child: Padding(
                  padding: const EdgeInsets.all(box / 2 - 48),
                  child: Image.asset('assets/launch/ghost-icon-eyeless.webp', width: 96, height: 96, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _ChasePainter(_frame, ink))),
          ],
        ),
      ),
    );
  }
}

class _IconClip extends CustomClipper<Path> {
  const _IconClip();

  @override
  Path getClip(Size size) => _iconPath;

  @override
  bool shouldReclip(_IconClip old) => false;
}

/// The eyes over the picture, then the track and the bar round it.
class _ChasePainter extends CustomPainter {
  _ChasePainter(this.frame, this.ink) : super(repaint: frame);

  final _Frame frame;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // `.eye { fill: #161616 }`: the picture's near-black in any theme, as the eyes are part of it.
    final eye = Paint()..color = const Color(0xFF161616);
    for (var i = 0; i < eyes.length; i += 1) {
      final at = eyes[i] + frame.looking[i];
      // The wink squeezes the eye round its own middle (`transform-box: fill-box; transform-origin: center`).
      final ry = i == winkingEye ? eyeRy * frame.wink : eyeRy;
      canvas.drawOval(Rect.fromCenter(center: at, width: eyeRx * 2, height: ry * 2), eye);
    }
    if (frame.ring <= 0) return;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    // `.track { stroke: color-mix(in srgb, var(--glacier-text) 12%, transparent) }`
    canvas.drawPath(_ringPath, line..color = ink.withValues(alpha: ink.a * 0.12 * frame.ring));
    // `.bar { stroke-linecap: round; stroke-dasharray: 14 86 }` on a path 100 long.
    final from = frame.lap * _lap;
    canvas.drawPath(
      _ringTwice.extractPath(from, from + _lap * dash / 100),
      line
        ..strokeCap = StrokeCap.round
        ..color = ink.withValues(alpha: ink.a * frame.ring),
    );
  }

  @override
  bool shouldRepaint(_ChasePainter old) => old.ink != ink || old.frame != frame;
}

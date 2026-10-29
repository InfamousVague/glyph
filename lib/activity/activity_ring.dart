/// The ring in the header (docs/ACTIVITY.md, Ring; Matt, 2026-10-29): beside the button for you, in every version of
/// the header toolbar, one arc for each job in its kind's colour, the other devices' a little dimmed; a quiet grey ring
/// when nothing runs (Matt, 2026-10-29: "Keep the activity indicator always showing just have it gray put when nothing
/// is happening"); one bloom when the last job ends, and grey again after it; a still red dot when something needs the
/// person. A press opens the tray (activity_tray.dart), idle or not: a card hung under the ring on a wide window, a
/// sheet on a phone.
///
/// The bar always draws the ring, so its room is kept whether or not anything runs (lib/shell/app_shell.dart hands it
/// to the bar as `activity`, as it hands the Claude chip). Simple mode's plain places, which have no bar for an idle
/// ring to sit in, float it only while [activityShown] holds: something to show, or the bloom.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/background_jobs.dart';
import '../notes/floating_card.dart';
import '../sheet/sheet.dart';
import 'activity_look.dart';
import 'activity_tray.dart';

/// The name the ring and its card share, so a press on the ring is not a press outside the card.
const String activityToggle = '[data-activity-toggle]';

/// How long the bloom lasts once the last job ends.
const Duration activityBloom = Duration(milliseconds: 900);

/// The window under which the tray is a sheet from the foot rather than a card under the ring.
const double activityTrayCardWidth = 600;

/// Whether there is something for the ring to say: something on the record ([Activity.value]), or the bloom of the
/// last to end. Heard by simple mode's floating ring, drawn only while this holds, and by the ring, which shows the
/// bloom's tick only while it does. Told only as it flips, so neither is drawn again for every step of a download.
class ActivityShown extends ChangeNotifier implements ValueListenable<bool> {
  ActivityShown(this.record);

  final Activity record;
  bool _shown = false;
  bool _blooming = false;
  int _blooms = 0;
  Timer? _bloomEnd;
  bool _hearing = false;

  @override
  bool get value => _hearing ? _shown : record.value.isNotEmpty;

  /// Whether the bloom is showing now.
  bool get blooming => _blooming;

  void _heard() {
    if (record.blooms != _blooms) {
      _blooms = record.blooms;
      _blooming = true;
      _bloomEnd?.cancel();
      _bloomEnd = Timer(activityBloom, () {
        _blooming = false;
        _look();
      });
    }
    _look();
  }

  void _look() {
    final shown = record.value.isNotEmpty || _blooming;
    if (shown == _shown) return;
    _shown = shown;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!_hearing) {
      _hearing = true;
      _blooms = record.blooms;
      _shown = record.value.isNotEmpty;
      record.addListener(_heard);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners && _hearing) {
      _hearing = false;
      record.removeListener(_heard);
      // Nobody draws the bloom: it is not waited for.
      _bloomEnd?.cancel();
      _bloomEnd = null;
      _blooming = false;
    }
  }
}

final Expando<ActivityShown> _shownFor = Expando();

/// [ActivityShown] for the app's record as it is now ([activity]).
ActivityShown get activityShown => _shownFor[activity] ??= ActivityShown(activity);

/// What a screen reader hears the ring as.
String activityRingLabel(List<Job> jobs) {
  final live = jobs.where((job) => job.state.live).length;
  final needs = jobs.any((job) => job.needsYou);
  final parts = [
    if (live > 0) live == 1 ? '1 job running' : '$live jobs running',
    if (needs) 'something needs you',
  ];
  return parts.isEmpty ? 'Activity: nothing running' : 'Activity: ${parts.join(', ')}';
}

/// The ring: a round control a bar's ring across.
class ActivityRing extends StatefulWidget {
  const ActivityRing({super.key, this.fine = false, this.size, this.simple = false});

  /// A mouse rather than a finger.
  final bool fine;

  /// Its diameter; the bar's ring (`--app-bar-ring`) unless given.
  final double? size;

  /// Simple mode: the tray keeps Past 7 days and the devices behind More.
  final bool simple;

  static const Key key_ = ValueKey<String>('header:activity');

  @override
  State<ActivityRing> createState() => _ActivityRingState();
}

class _ActivityRingState extends State<ActivityRing> with TickerProviderStateMixin {
  late final Activity _record = activity;
  late final ActivityShown _shown = activityShown;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  late final AnimationController _bloom = AnimationController(vsync: this, duration: activityBloom);
  late int _blooms = _record.blooms;
  Color? _lastColour;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _record.addListener(_heard);
    // The bloom's end: the tick goes and the ring is grey again, moving or not.
    _shown.addListener(_settled);
  }

  void _settled() {
    if (mounted) setState(() {});
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _moving();
    if (_started) return;
    _started = true;
    // Drawn for a bloom alone (a sync that moved notes and ended before the bar was drawn again): the bloom is shown.
    if (_shown.blooming && _record.value.isEmpty) {
      if (activityMoves(context)) {
        _bloom.forward(from: 0);
      } else {
        _bloom.value = 1;
      }
    }
  }

  void _heard() {
    if (!mounted) return;
    if (_record.blooms != _blooms) {
      _blooms = _record.blooms;
      if (activityMoves(context)) {
        _bloom.forward(from: 0);
      } else {
        _bloom.value = 1;
      }
    }
    final last = _record.value.where((job) => job.state.live).lastOrNull;
    if (last != null) _lastColour = jobColour(context.tokens, last.look);
    _moving();
    setState(() {});
  }

  /// The arcs move while something runs that cannot say how far it is, and the device allows it.
  void _moving() {
    final moves = activityMoves(context) && _record.value.any((job) => job.state == JobState.running && job.fraction == null);
    if (moves && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!moves && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _record.removeListener(_heard);
    _shown.removeListener(_settled);
    _spin.dispose();
    _bloom.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted && _open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = widget.size ?? t.len('app-bar-ring');
    final jobs = _record.value;
    final live = jobs.where((job) => job.state.live).toList();
    final lead = live.where((job) => job.here).firstOrNull ?? live.firstOrNull ?? jobs.firstOrNull;
    final needs = _record.needsYou;
    final ring = AnimatedBuilder(
      animation: Listenable.merge([_spin, _bloom]),
      builder: (context, _) {
        // The tick shows through the bloom, and while the device holds still, for as long as the bloom would last.
        final ticked = live.isEmpty && jobs.isEmpty && _shown.blooming && _bloom.value > 0;
        return CustomPaint(
          key: const ValueKey('activity-ring:arcs'),
          painter: ActivityRingPainter(
            arcs: [for (final job in jobs) RingArc.of(t, job)],
            spin: _spin.value,
            track: t.color('glacier-border-subtle'),
            // Nothing running: the ring's track alone, thin, in the ink's grey, in Calm as well (it is no job's colour).
            idle: t.color('app-ink-3'),
            bloom: live.isEmpty && jobs.isEmpty ? _bloom.value : 0,
            bloomColour: _lastColour ?? (_record.lastEnded == null ? jobColour(t, JobLook.sync) : kindColour(t, _record.lastEnded!.kind)),
          ),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: lead != null
                  ? JobGlyph.of(lead, key: ValueKey('activity-ring:glyph:${lead.id}'), size: size * 0.5)
                  : ticked
                      ? Opacity(opacity: activityMoves(context) ? (1 - _bloom.value).clamp(0.0, 1.0) : 1, child: AppIcon(Lucide.check, size: size * 0.5, color: _lastColour ?? (_record.lastEnded == null ? t.color('glacier-text') : kindColour(t, _record.lastEnded!.kind)), strokeWidth: 2.4))
                      : const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
    final face = Stack(
      clipBehavior: Clip.none,
      children: [
        ring,
        if (needs)
          PositionedDirectional(
            top: 1,
            end: 1,
            child: Container(
              key: const ValueKey('activity-ring:dot'),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: jobColour(t, JobLook.needsYou), shape: BoxShape.circle, boxShadow: [BoxShadow(color: t.color('glacier-bg'), spreadRadius: 1.5)]),
            ),
          ),
      ],
    );
    final button = FloatingCardToggle(
      toggle: activityToggle,
      child: GlacierPressable(
        key: ActivityRing.key_,
        onPressed: () {
          cardOpenedFrom(context);
          setState(() => _open = !_open);
        },
        semanticLabel: activityRingLabel(jobs),
        pressScale: null,
        builder: (context, state) => GlacierFocusRing(visible: state.focused, radius: 999, child: face),
      ),
    );
    if (!_open) return button;
    final sheet = MediaQuery.sizeOf(context).width < activityTrayCardWidth;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        if (sheet)
          Sheet(label: 'Activity', onClose: _close, children: [ActivityTray(record: _record, simple: widget.simple, onClose: _close, sheet: true)])
        else
          FloatingCard(side: FloatingCardSide.end, wide: true, label: 'Activity', toggle: activityToggle, onClose: _close, child: ActivityTray(record: _record, simple: widget.simple, onClose: _close)),
      ],
    );
  }
}

/// One job's arc on the ring: its colour, how far it is (null, it cannot say), and whether it is another device's.
@immutable
class RingArc {
  const RingArc({required this.colour, this.fraction, this.elsewhere = false, this.moving = false, this.full = false});

  factory RingArc.of(Tokens t, Job job) => RingArc(
        colour: jobColour(t, job.look),
        fraction: job.fraction,
        elsewhere: !job.here,
        moving: job.state == JobState.running && job.fraction == null,
        // A failed job and one that waits on the person are their whole arc, red; one that waits otherwise is its
        // whole arc, dimmed.
        full: !job.state.live || job.state != JobState.running,
      );

  final Color colour;
  final double? fraction;
  final bool elsewhere;
  final bool moving;
  final bool full;

  /// How dim another device's arc is drawn.
  static const double elsewhereAlpha = 0.5;

  /// The colour it is drawn in, another device's dimmed.
  Color get drawn => elsewhere ? colour.withValues(alpha: colour.a * elsewhereAlpha) : colour;
}

/// The arcs round the ring, and the bloom.
class ActivityRingPainter extends CustomPainter {
  const ActivityRingPainter({required this.arcs, required this.spin, required this.track, this.idle, this.bloom = 0, required this.bloomColour});

  final List<RingArc> arcs;
  final double spin;
  final Color track;

  /// The ring with nothing running, a thin full circle in this; null draws nothing then.
  final Color? idle;

  /// 0 to 1 through the bloom; 0 is none.
  final double bloom;
  final Color bloomColour;

  /// How thick the idle ring is drawn: thinner than an arc, so it reads as quiet.
  static const double idleStroke = 1.5;

  /// The gap between two arcs, in radians.
  static const double gap = 0.32;

  /// The segments the arcs are drawn in, as (start, sweep) from the top, clockwise.
  static List<(double, double)> segments(int count) {
    if (count == 0) return const [];
    if (count == 1) return const [(-math.pi / 2, 2 * math.pi)];
    final each = 2 * math.pi / count;
    return [for (var i = 0; i < count; i += 1) (-math.pi / 2 + i * each + gap / 2, each - gap)];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(2.0, size.width * 0.085);
    final rect = (Offset.zero & size).deflate(stroke / 2 + 0.5);
    if (bloom > 0) {
      final grown = rect.inflate(size.width * 0.28 * Curves.easeOut.transform(bloom));
      canvas.drawOval(grown, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * (1 - bloom * 0.6)
        ..color = bloomColour.withValues(alpha: (1 - bloom) * bloomColour.a));
      canvas.drawOval(rect, Paint()..color = bloomColour.withValues(alpha: 0.18 * (1 - bloom) * bloomColour.a));
    }
    if (arcs.isEmpty) {
      if (idle case final grey?) {
        // On the arcs' own line, so nothing moves as the first job begins.
        canvas.drawOval(rect, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = idleStroke
          ..color = grey);
      }
      return;
    }
    final segs = segments(arcs.length);
    for (var i = 0; i < arcs.length; i += 1) {
      final arc = arcs[i];
      final (start, sweep) = segs[i];
      final colour = arc.drawn;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = arcs.length == 1 ? StrokeCap.butt : StrokeCap.round;
      // The track: the arc's own colour, faint.
      canvas.drawArc(rect, start, sweep, false, paint..color = colour.withValues(alpha: colour.a * 0.28));
      if (arc.full) {
        canvas.drawArc(rect, start, sweep, false, paint..color = colour);
      } else if (arc.fraction case final f?) {
        if (f > 0) canvas.drawArc(rect, start, sweep * f.clamp(0.0, 1.0), false, paint..color = colour);
      } else {
        // It cannot say how far: a third of its arc going round within it, or, still, two thirds of it drawn.
        final part = sweep * (arc.moving ? 0.38 : 0.66);
        final at = arc.moving ? (sweep - part) * (0.5 - 0.5 * math.cos(spin * 2 * math.pi)) : 0.0;
        if (arcs.length == 1 && arc.moving) {
          canvas.drawArc(rect, start + spin * 2 * math.pi, part, false, paint..color = colour);
        } else {
          canvas.drawArc(rect, start + at, part, false, paint..color = colour);
        }
      }
    }
  }

  @override
  bool shouldRepaint(ActivityRingPainter old) => true;
}

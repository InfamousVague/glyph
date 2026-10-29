/// The result chips (docs/ACTIVITY.md, Results; Matt, 2026-10-29: "A result chip slides in from the edge ("Banner ready
/// · View"), replacing most toasts; a batch gives one chip").
///
/// A job that ends with a result ([JobResult]) while the person is elsewhere - what it made is not what is on the
/// screen ([Job.shownHere]) - is said by a small chip in its kind's colour, sliding in from the window's end edge
/// under the header: its words and its action. A job that failed says its cause, red, with its fix. A batch is one
/// job (a notebook's banner run is one run), so it gives one chip. At most two at once, the newest on top, the oldest
/// let go for a third; a swipe sideways or the × puts one away, and each goes on its own after [chipFor].
///
/// They hang under the header, at the top: never over the dock at the foot, nor the keyboard.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/background_jobs.dart';
import 'activity_look.dart';

/// How long a chip stays.
const Duration chipFor = Duration(seconds: 6);

/// At most this many at once.
const int chipsAtOnce = 2;

/// One chip's words: what it says, its action and what the action does, and its colour's look.
@immutable
class ActivityChip {
  const ActivityChip({required this.id, required this.kind, required this.words, this.action, this.onAction, this.failed = false});

  /// The chip [job]'s end gives, or null for none: no result and no failure, or the person is looking at it.
  static ActivityChip? of(Job job) {
    if (!job.here) return null;
    if (job.shownHere?.call() ?? false) return null;
    if (job.state == JobState.failed) {
      return ActivityChip(id: job.id, kind: job.kind, words: job.cause ?? '${job.title} failed', action: job.fix?.label, onAction: job.fix?.onPress, failed: true);
    }
    final result = job.result;
    if (result == null) return null;
    return ActivityChip(id: job.id, kind: job.kind, words: result.words, action: result.onOpen == null ? null : result.action, onAction: result.onOpen);
  }

  final String id;
  final JobKind kind;
  final String words;
  final String? action;
  final VoidCallback? onAction;
  final bool failed;
}

/// The chips' layer: put where the chips hang, at the window's end under the header. Hears [record]'s ends.
class ActivityChips extends StatefulWidget {
  const ActivityChips({super.key, this.record});

  /// The app's [activity] unless given.
  final Activity? record;

  @override
  State<ActivityChips> createState() => ActivityChipsState();
}

class ActivityChipsState extends State<ActivityChips> {
  late final Activity _record = widget.record ?? activity;
  StreamSubscription<JobEvent>? _hearing;
  final List<(ActivityChip, int)> _chips = [];
  final Map<int, Timer> _going = {};
  int _made = 0;

  /// The chips showing, newest first.
  List<ActivityChip> get chips => [for (final (chip, _) in _chips) chip];

  @override
  void initState() {
    super.initState();
    _hearing = _record.events.listen(_heard);
  }

  void _heard(JobEvent event) {
    if (event.kind != JobEventKind.ended) return;
    final job = event.job;
    if (job == null) return;
    final chip = ActivityChip.of(job);
    if (chip == null || !mounted) return;
    setState(() {
      // The same job again is the one chip, said anew.
      _chips.removeWhere((each) {
        if (each.$1.id != chip.id) return false;
        _going.remove(each.$2)?.cancel();
        return true;
      });
      final n = _made++;
      _chips.insert(0, (chip, n));
      _going[n] = Timer(chipFor, () => _dismiss(n));
      while (_chips.length > chipsAtOnce) {
        final (_, old) = _chips.removeLast();
        _going.remove(old)?.cancel();
      }
    });
  }

  void _dismiss(int n) {
    _going.remove(n)?.cancel();
    if (!mounted) return;
    setState(() => _chips.removeWhere((each) => each.$2 == n));
  }

  @override
  void dispose() {
    _hearing?.cancel();
    for (final timer in _going.values) {
      timer.cancel();
    }
    _going.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_chips.isEmpty) return const SizedBox.shrink();
    final t = context.tokens;
    // Two stack as one: as wide as the wider, the same end edge, one over the other with a gap, their actions and
    // crosses in line (Matt, 2026-10-29: "result chips when two stack should stack cleanly").
    return IntrinsicWidth(
      child: Column(
      key: const ValueKey('activity-chips'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (chip, n)) in _chips.indexed)
          Padding(
            key: ValueKey('activity-chip:$n'),
            padding: EdgeInsets.only(bottom: i == _chips.length - 1 ? 0 : t.space(2)),
            child: Dismissible(
              key: ValueKey('activity-chip-swipe:$n'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => _dismiss(n),
              child: _SlideIn(child: ChipFace(chip: chip, fill: _chips.length > 1, onClose: () => _dismiss(n), onAction: chip.onAction == null ? null : () {
                _dismiss(n);
                chip.onAction!();
              })),
            ),
          ),
      ],
      ),
    );
  }
}

/// Slides in from the end edge as it is first drawn; still where the device asks for less motion.
class _SlideIn extends StatefulWidget {
  const _SlideIn({required this.child});
  final Widget child;

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (activityMoves(context)) {
      _in.forward();
    } else {
      _in.value = 1;
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SlideTransition(
      position: Tween(begin: Offset(rtl ? -1.2 : 1.2, 0), end: Offset.zero).animate(eased),
      child: FadeTransition(opacity: eased, child: widget.child),
    );
  }
}

/// A chip as it is drawn: a capsule of paper, a dot of its colour (red for a failure), its words, its action in its
/// colour, and ×.
class ChipFace extends StatelessWidget {
  const ChipFace({super.key, required this.chip, this.onAction, this.onClose, this.fill = false});

  final ActivityChip chip;

  /// As wide as it is given, its words taking the room, so that a chip stacked with a wider one puts its action and
  /// its cross at the same place.
  final bool fill;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colour = chip.failed ? jobColour(t, JobLook.needsYou) : kindColour(t, chip.kind);
    final action = chip.action;
    return Semantics(
      container: true,
      liveRegion: true,
      label: [chip.words, ?action].join(', '),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: t.lenOf('min(22rem, calc(100vw - var(--glacier-space-8)))')),
        child: Container(
          padding: EdgeInsets.fromLTRB(t.space(3), t.space(1) * 1.5, t.space(1), t.space(1) * 1.5),
          decoration: BoxDecoration(
            // Whole, so nothing of the page shows through the words (the 4% of text over 94% of the page left 2% clear).
            color: t.colorOf('color-mix(in srgb, var(--glacier-bg) 96%, var(--glacier-text) 4%)'),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colour.withValues(alpha: colour.a * 0.55)),
            boxShadow: const [BoxShadow(color: Color(0x2E000000), offset: Offset(0, 6), blurRadius: 18)],
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(key: const ValueKey('activity-chip:dot'), width: 9, height: 9, decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
                SizedBox(width: t.space(2)),
                Flexible(fit: fill ? FlexFit.tight : FlexFit.loose, child: Text(chip.words, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.text('sm', weight: 'medium', color: chip.failed ? colour : t.color('glacier-text')))),
                if (action != null && onAction != null) ...[
                  Text('  ·  ', style: t.text('sm', color: t.color('glacier-text-subtle'))),
                  GlacierPressable(
                    key: ValueKey('activity-chip:action:${chip.id}'),
                    onPressed: onAction,
                    semanticLabel: action,
                    builder: (context, state) => Text(action, style: t.text('sm', weight: 'semibold', color: colour)),
                  ),
                ],
                SizedBox(width: t.space(1)),
                GlacierPressable(
                  key: ValueKey('activity-chip:close:${chip.id}'),
                  onPressed: onClose,
                  semanticLabel: 'Dismiss',
                  builder: (context, state) => Padding(padding: EdgeInsets.all(t.space(1)), child: AppIcon(Lucide.x, size: 14, color: t.color('glacier-text-muted'))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

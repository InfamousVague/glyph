/// The tray under the ring (docs/ACTIVITY.md, Tray; Matt, 2026-10-29): the live rows first - each job's glyph, its
/// title, its live line ("Writing the summary, 2 of 3 parts", "Waiting for Wi-Fi"), a bar for how far, Stop and Open,
/// and where it runs ("on your Mac") - then **Today** ("3 summaries, 12 banners, 40 notes synced, 1 failed"), then
/// **Past 7 days** behind More. A failed job's row is red, with its cause in plain words and its one fix (Top up, Sign
/// in again, Retry) and a way to put it away.
///
/// **Update** comes first, while the app has one waiting (Matt, 2026-10-30: "show the updates stuff in the activity
/// drawer only now with a badge"): the version and what's new where the release says, its one action (Install,
/// Restart to update, Open), its download as the `update` job's row with its bar, and its failure as that row in red
/// with Retry. Settings › About's Check for updates opens the tray here ([ActivityTray.update]), which says where the
/// check stands when nothing waits ("Ghost.md 2.3.85 is up to date"). The tray is the one place the app speaks of its
/// own updates: there is no card on the home page, no chip, no toast.
///
/// Simple mode (GHST-103) keeps all of it but the devices and the past behind More, as every simple surface keeps the
/// rest behind More. The ring opens it as a card hung under itself on a wide window, and as a sheet from the foot on a
/// phone (activity_ring.dart); the same rows either way.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/widgets.dart' show AppEyebrow;
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/background_jobs.dart';
import 'activity_look.dart';
import 'job_mark.dart';

/// The day a past day is called by: "Yesterday", "Tuesday 27 October".
String pastDayWords(String day, DateTime today) {
  final parts = day.split('-').map(int.parse).toList();
  final at = DateTime(parts[0], parts[1], parts[2]);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (at == yesterday) return 'Yesterday';
  const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${weekdays[at.weekday - 1]} ${at.day} ${months[at.month - 1]}';
}

/// What a job costs: its estimate and the credits spent so far ("~72 Lovart credits · 18 spent"); [count] false leaves
/// the estimate's count out, where the line says how far already ("5 of 12").
String? costWords(Job job, {bool count = true}) {
  final estimate = job.estimate;
  final spent = job.spent;
  final said = estimate == null ? '' : (count ? estimate.words : JobEstimate(credits: estimate.credits, provider: estimate.provider, duration: estimate.duration).words);
  final words = [
    if (said.isNotEmpty) said,
    if (spent != null && spent > 0) '$spent spent',
  ];
  return words.isEmpty ? null : words.join(' · ');
}

/// A row's line under its title: what the job does now and how far, what it costs and has spent, and where it runs,
/// in one line ("5 of 12 · ~72 Lovart credits · 30 spent"). A running job with no words of its own for what it does
/// would say its title again ("Making header images, 5 of 12" under "Making header images"; Matt, 2026-10-29: "make
/// the line say just 5 of 12 · ~72 Lovart credits · 30 spent"), so it says how far alone, and the estimate leaves out
/// the count that says. A failed one says its cause, and its cost goes on a line of its own ([costWords]).
String trayLine(Job job, {String? where}) {
  final failed = job.state == JobState.failed;
  final bare = job.state == JobState.running && job.line == null && job.steps != null;
  final cost = failed ? null : costWords(job, count: job.steps == null);
  return [bare ? job.steps! : job.liveLine, ?cost, ?where].join(' · ');
}

/// The tray's rows for [record].
class ActivityTray extends StatefulWidget {
  const ActivityTray({super.key, required this.record, this.simple = false, this.onClose, this.sheet = false, this.update = false});

  final Activity record;
  final bool simple;
  final VoidCallback? onClose;

  /// Opened at the Update section (Settings › About's Check for updates): it shows whether or not one waits.
  final bool update;

  /// In a sheet from the foot, which pads and scrolls itself: the rows alone.
  final bool sheet;

  @override
  State<ActivityTray> createState() => _ActivityTrayState();
}

class _ActivityTrayState extends State<ActivityTray> {
  bool _more = false;

  @override
  void initState() {
    super.initState();
    widget.record.addListener(_heard);
    widget.record.log.addListener(_heard);
  }

  @override
  void dispose() {
    widget.record.removeListener(_heard);
    widget.record.log.removeListener(_heard);
    super.dispose();
  }

  void _heard() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final record = widget.record;
    final jobs = record.value;
    final today = record.log.today;
    final past = record.log.past;
    final devices = !widget.simple || _more;
    final offer = record.update;
    final updating = offer != null && (offer.badge || widget.update);
    // The update's download is drawn in its section, not again among the rest.
    final updateJob = updating ? jobs.where((job) => job.id == appUpdateJobId && job.here).firstOrNull : null;
    final rest = [for (final job in jobs) if (!identical(job, updateJob)) job];
    final children = <Widget>[
      Padding(
        padding: EdgeInsets.only(bottom: t.space(2)),
        child: Semantics(header: true, child: Text('Activity', style: t.text('md', weight: 'semibold', color: t.color('glacier-text')))),
      ),
      if (updating) ...[
        UpdateSection(offer: offer, job: updateJob, record: record),
        SizedBox(height: t.space(3)),
      ],
      // The update's download is something running: no "Nothing running now." under it.
      if (rest.isEmpty && updateJob == null)
        Padding(
          key: const ValueKey('activity-tray:idle'),
          padding: EdgeInsets.symmetric(vertical: t.space(2)),
          child: Text('Nothing running now.', style: t.text('sm', color: t.color('glacier-text-muted'))),
        )
      else
        for (final job in rest) ActivityRow(key: ValueKey('activity-row:${job.id}'), job: job, record: record, device: devices),
      SizedBox(height: t.space(3)),
      const AppEyebrow('Today'),
      SizedBox(height: t.space(1)),
      Text(
        today.words.isEmpty ? 'Nothing finished yet today.' : today.words,
        key: const ValueKey('activity-tray:today'),
        style: t.text('sm', color: today.words.isEmpty ? t.color('glacier-text-muted') : t.color('glacier-text')),
      ),
      for (final row in today.rows.take(widget.simple && !_more ? 3 : 6))
        Padding(
          padding: EdgeInsets.only(top: t.space(1)),
          child: Row(
            children: [
              SizedBox.square(dimension: 14, child: row.failed ? JobGlyph(kind: row.kind, look: JobLook.needsYou, size: 14) : JobGlyph(kind: row.kind, size: 14, moving: false, plugin: row.plugin)),
              SizedBox(width: t.space(2)),
              Expanded(
                child: Text(
                  [row.title, if (row.failed) row.cause ?? 'Failed' else ?row.tally].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.text('xs', color: row.failed ? jobColour(t, JobLook.needsYou) : t.color('glacier-text-muted')),
                ),
              ),
            ],
          ),
        ),
      if (_more && past.isNotEmpty) ...[
        SizedBox(height: t.space(3)),
        const AppEyebrow('Past 7 days'),
        for (final day in past)
          Padding(
            key: ValueKey('activity-tray:past:${day.day}'),
            padding: EdgeInsets.only(top: t.space(1)),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${pastDayWords(day.day, record.now)}  ', style: t.text('xs', weight: 'semibold', color: t.color('glacier-text'))),
                TextSpan(text: day.words, style: t.text('xs', color: t.color('glacier-text-muted'))),
              ]),
            ),
          ),
      ],
      if (_more && past.isEmpty)
        Padding(
          padding: EdgeInsets.only(top: t.space(3)),
          child: Text('Nothing in the past 7 days.', key: const ValueKey('activity-tray:past-none'), style: t.text('xs', color: t.color('glacier-text-muted'))),
        ),
      Padding(
        padding: EdgeInsets.only(top: t.space(2)),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TrayButton(key: const ValueKey('activity-tray:more'), label: _more ? 'Less' : 'More', onPressed: () => setState(() => _more = !_more)),
        ),
      ),
    ];
    final column = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    if (widget.sheet) return Padding(padding: EdgeInsets.symmetric(horizontal: t.space(1)), child: column);
    return SingleChildScrollView(padding: EdgeInsets.all(t.space(4)), child: column);
  }
}

/// One job in the tray: its glyph on a wash of its colour, its title and live line, its cost, its bar, its buttons.
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.job, required this.record, this.device = true});

  final Job job;
  final Activity record;

  /// Whether it says where it runs.
  final bool device;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final failed = job.state == JobState.failed;
    final colour = failed ? jobColour(t, JobLook.needsYou) : kindColour(t, job.kind);
    final cost = failed ? costWords(job) : null;
    final where = device ? job.deviceWords : null;
    final buttons = <Widget>[
      if (failed && job.fix != null) TrayButton(key: ValueKey('activity-row:fix:${job.id}'), label: job.fix!.label, colour: colour, filled: true, onPressed: job.fix!.onPress),
      if (!failed && job.onStop != null) TrayButton(key: ValueKey('activity-row:stop:${job.id}'), label: 'Stop', onPressed: job.onStop),
      if (job.onOpen != null) TrayButton(key: ValueKey('activity-row:open:${job.id}'), label: 'Open', onPressed: job.onOpen),
      if (failed) TrayButton(key: ValueKey('activity-row:dismiss:${job.id}'), label: 'Dismiss', onPressed: () => record.dismiss(job.id)),
    ];
    return Semantics(
      container: true,
      label: '${job.title}. ${job.liveLine}${where == null ? '' : ', $where'}',
      child: Container(
        margin: EdgeInsets.only(bottom: t.space(2)),
        padding: EdgeInsets.all(t.space(2)),
        decoration: BoxDecoration(
          color: failed ? colour.withValues(alpha: colour.a * 0.1) : null,
          borderRadius: BorderRadius.circular(t.radius('md')),
          border: failed ? Border.all(color: colour.withValues(alpha: colour.a * 0.5)) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Google Meet's mark is drawn in white on its own colour, its tile, where the row has one (Matt, 2026-10-30;
            // lib/plugins/brands.dart `marksInWhite`); every other job's glyph or mark sits on a wash of its kind's colour.
            if (!failed && marksOnTile(job.plugin, t))
              JobMark(plugin: job.plugin!, size: 30, colour: colour, tile: true, dim: !job.here || job.state != JobState.running)
            else
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: colour.withValues(alpha: colour.a * 0.14)),
                child: JobGlyph.of(job, size: 18),
              ),
            SizedBox(width: t.space(3)),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.text('sm', weight: 'semibold', color: failed ? colour : t.color('glacier-text'))),
                    SizedBox(height: t.space(1) * 0.5),
                    Text(
                      trayLine(job, where: where),
                      key: ValueKey('activity-row:line:${job.id}'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.text('xs', color: failed ? colour : t.color('glacier-text-muted')),
                    ),
                    if (cost != null) ...[
                      SizedBox(height: t.space(1) * 0.5),
                      Text(cost, key: ValueKey('activity-row:cost:${job.id}'), style: t.text('xs', color: t.color('glacier-text-subtle'))),
                    ],
                    if (job.state.live) ...[
                      SizedBox(height: t.space(1) * 1.5),
                      JobBar(fraction: job.state == JobState.running ? job.fraction : null, colour: colour, moving: job.state == JobState.running, dim: !job.here || job.state != JobState.running),
                    ],
                    if (buttons.isNotEmpty) ...[
                      SizedBox(height: t.space(2)),
                      Wrap(spacing: t.space(2), runSpacing: t.space(1), children: buttons),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tray's Update section (see the header): the update's line, what's new, its one action, and its download's row.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key, required this.offer, required this.record, this.job});

  final UpdateOffer offer;
  final Activity record;

  /// The update's job on the record: its download, or its failure.
  final Job? job;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colour = kindColour(t, JobKind.downloads);
    final failed = job?.state == JobState.failed;
    // A failure whose red row is there says Retry on it; the section's own Try again is for one put away.
    final action = failed ? null : offer.action;
    final onAction = offer.onAction;
    final notes = offer.notes;
    final message = offer.stage == UpdateStage.checkFailed || (offer.stage == UpdateStage.failed && job == null) ? offer.message : null;
    return Semantics(
      key: const ValueKey('activity-tray:update'),
      container: true,
      label: 'Update. ${offer.words}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppEyebrow('Update'),
          SizedBox(height: t.space(1)),
          ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: colour.withValues(alpha: colour.a * (offer.badge ? 0.14 : 0.08))),
                  child: AppIcon(offer.badge ? Lucide.arrowUp : Lucide.check, size: 16, color: offer.badge ? colour : t.color('app-ink-3'), strokeWidth: 2.4),
                ),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(offer.words, key: const ValueKey('activity-tray:update:words'), style: t.text('sm', weight: 'semibold', color: t.color('glacier-text'))),
                      if (notes != null) ...[
                        SizedBox(height: t.space(1) * 0.5),
                        Text(notes, key: const ValueKey('activity-tray:update:notes'), maxLines: 6, overflow: TextOverflow.ellipsis, style: t.text('xs', color: t.color('glacier-text-muted'))),
                      ],
                      if (message != null) ...[
                        SizedBox(height: t.space(1) * 0.5),
                        Text(message, key: const ValueKey('activity-tray:update:message'), maxLines: 3, overflow: TextOverflow.ellipsis, style: t.text('xs', color: t.color('glacier-text-muted'))),
                      ],
                      if (action != null && onAction != null) ...[
                        SizedBox(height: t.space(2)),
                        TrayButton(key: const ValueKey('activity-tray:update:action'), label: action, colour: offer.badge ? colour : null, filled: offer.badge, onPressed: onAction),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (job case final job?) ...[
            SizedBox(height: t.space(2)),
            ActivityRow(key: ValueKey('activity-row:${job.id}'), job: job, record: record),
          ],
        ],
      ),
    );
  }
}

/// How far a job is: a track of its colour, faint, and the part done; a third of it sweeping across while it cannot
/// say, still where the device asks for less motion.
class JobBar extends StatefulWidget {
  const JobBar({super.key, this.fraction, required this.colour, this.moving = true, this.dim = false});

  final double? fraction;
  final Color colour;
  final bool moving;
  final bool dim;

  @override
  State<JobBar> createState() => _JobBarState();
}

class _JobBarState extends State<JobBar> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(JobBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final moves = widget.fraction == null && widget.moving && activityMoves(context);
    if (moves && !_sweep.isAnimating) _sweep.repeat();
    if (!moves && _sweep.isAnimating) _sweep.stop();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = widget.dim ? widget.colour.withValues(alpha: widget.colour.a * 0.5) : widget.colour;
    return SizedBox(
      key: const ValueKey('job-bar'),
      height: 4,
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _sweep,
          builder: (context, _) {
            final w = box.maxWidth;
            final f = widget.fraction;
            final double start, width;
            if (f != null) {
              start = 0;
              width = w * f.clamp(0.0, 1.0);
            } else {
              width = w * 0.36;
              start = _sweep.isAnimating ? (w + width) * Curves.easeInOut.transform(_sweep.value) - width : 0;
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: colour.withValues(alpha: colour.a * 0.22))),
                  PositionedDirectional(start: start, top: 0, bottom: 0, width: width, child: ColoredBox(key: const ValueKey('job-bar:fill'), color: colour)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A small button in the tray: its word in a capsule, outlined, or [filled] in [colour] for a failed job's fix.
class TrayButton extends StatelessWidget {
  const TrayButton({super.key, required this.label, required this.onPressed, this.colour, this.filled = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final Color? colour;
  final bool filled;
  final LucideIcon? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) {
        final ink = colour ?? t.color('glacier-text');
        final fg = filled ? const Color(0xFFFFFFFF) : ink;
        return GlacierFocusRing(
          visible: state.focused,
          radius: 999,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
            decoration: BoxDecoration(
              color: filled ? ink : (state.pressed || state.hovered ? t.color('app-paper-2') : null),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: filled ? ink : t.color('glacier-border'), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[AppIcon(icon!, size: 13, color: fg), SizedBox(width: t.space(1))],
                Text(label, style: t.text('xs', weight: 'semibold', color: fg)),
              ],
            ),
          ),
        );
      },
    );
  }
}

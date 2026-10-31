/// The work on a ticket, under its properties in the panel (ticket_panel.dart; Matt, 2026-10-31, of the ticket
/// features: "time tracking" and "GitHub PR links"): its time, with Start and Stop and Add time…, and the pull requests
/// that name it, each a chip with its state and its checks.
///
/// - **Time** reads `spent:` from the front matter the panel draws (lib/book/time_log.dart), and the timer from the
///   app's timers (lib/book/timers.dart): Start on this device, the time so far and Stop while it runs here, or
///   "on your Mac" with Stop while it runs on another device. Add time… opens a sheet of its own. Shown in simple mode
///   too: timers are not one of its fancy things.
/// - **Pull requests** are the GitHub plugin's (lib/plugins/github/pull_links.dart), read when the panel is drawn and
///   again whenever they change; a chip opens its pull request. None, no row.
/// - In a view that cannot be edited the time is read, with no Start or Add.
/// - A card on a board gets the timer alone ([TicketCardTimer]): the time so far and Stop while it runs, a quiet Start
///   otherwise.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart' show HapticKind, fireMotor;

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../book/timers.dart';
import '../../core/days.dart' show isIsoDay;
import '../../core/durations.dart' show spentMinutes, spentWords;
import '../../core/front_matter.dart' show frontMatterValue;
import '../../plugins/github/pull_links.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../queries/query_layout.dart';
import '../queries/query_look.dart';

/// What the screen hands a ticket's panel for its work: the ticket, the app's timers, its pull requests, and the
/// ways to open a link and to look for more.
class TicketWorkOptions {
  const TicketWorkOptions({required this.noteId, required this.title, this.ticketKey, this.timers, this.pulls, this.pullsChanged, this.openUrl, this.lookForPulls, this.today});

  final String noteId;
  final String title;

  /// `HT-12`, where it has one.
  final String? ticketKey;

  /// The app's timers; null where there are none (a test's, a build without them), and then no timer is offered.
  final TicketTimers? timers;

  /// The pull requests that name it, newest first; null where its notebook names no repo.
  final List<LinkedPull> Function()? pulls;
  final Listenable? pullsChanged;
  final void Function(String url)? openUrl;

  /// Asked once as the panel is drawn: the ticket's own look on GitHub (`PullLinks.lookFor`).
  final VoidCallback? lookForPulls;

  /// Today, for Add time…'s day; the clock's where null.
  final String Function()? today;
}

/// The panel's work rows (see the header). [names] is the width of the panel's names, so its rows line up with them.
class TicketWork extends StatefulWidget {
  const TicketWork({super.key, required this.look, required this.front, required this.editable, required this.options, required this.names});

  final QueryLook look;
  final String front;
  final bool editable;
  final TicketWorkOptions options;
  final double names;

  @override
  State<TicketWork> createState() => _TicketWorkState();
}

class _TicketWorkState extends State<TicketWork> {
  Timer? _tick;
  TicketTimers? _timers;
  Listenable? _pullsHeard;

  QueryLook get look => widget.look;

  @override
  void initState() {
    super.initState();
    _listen();
    widget.options.lookForPulls?.call();
  }

  @override
  void didUpdateWidget(TicketWork old) {
    super.didUpdateWidget(old);
    if (old.options.timers != widget.options.timers || old.options.pullsChanged != widget.options.pullsChanged) {
      _unlisten();
      _listen();
    }
  }

  void _listen() {
    _timers = widget.options.timers?..addListener(_changed);
    _pullsHeard = widget.options.pullsChanged?..addListener(_changed);
    _ticking();
  }

  void _unlisten() {
    _timers?.removeListener(_changed);
    _pullsHeard?.removeListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    _ticking();
    setState(() {});
  }

  /// A running timer's time is drawn again every half minute.
  void _ticking() {
    final running = widget.options.timers?.on(widget.options.noteId) != null;
    if (running && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _unlisten();
    _tick?.cancel();
    super.dispose();
  }

  Widget _row(String name, Widget value) => Row(
        children: <Widget>[
          SizedBox(width: widget.names, child: Part('name', child: PageWords(name, look.sans(look.em, color: look.ink3), line: look.line, softWrap: false))),
          SizedBox(width: look.space(3)),
          Expanded(child: Container(constraints: BoxConstraints(minHeight: (2.25 * look.em).floorToDouble()), alignment: Alignment.centerLeft, child: value)),
        ],
      );

  Widget _tap({required String label, required VoidCallback? onTap, required Widget child, Key? key}) {
    if (onTap == null) return child;
    return Semantics(
      key: key,
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          fireMotor(HapticKind.selection);
          onTap();
        },
        child: child,
      ),
    );
  }

  /// A quiet chip: an icon and words on the panel's paper, the panel's `.give`.
  Widget _chip(String words, {LucideIcon? icon, Color? color, Color? dot, bool strong = false}) {
    final ink = color ?? look.ink2;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: look.space(2), vertical: look.space(1) / 2),
      decoration: ShapeDecoration(color: look.paper, shape: StadiumBorder(side: BorderSide(color: look.rule))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (dot != null) ...<Widget>[Container(width: 7, height: 7, decoration: ShapeDecoration(color: dot, shape: const CircleBorder())), SizedBox(width: look.space(1))],
          if (icon != null) ...<Widget>[AppIcon(icon, size: 12, strokeWidth: 2.2, color: ink), SizedBox(width: look.space(1))],
          Flexible(child: PageWords(words, look.sans(look.xs, color: ink, weight: strong ? 'semibold' : 'regular'), line: look.lineXs, softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _time() {
    final options = widget.options;
    final timers = options.timers;
    final running = timers?.on(options.noteId);
    final spent = spentMinutes(frontMatterValue(widget.front, 'spent'));
    final mine = running != null && running.device == timers!.device().id;
    String elapsed(RunningTimer timer) => timers!.elapsed(timer);
    final red = look.t.color('glacier-red-11');
    final parts = <Widget>[
      Part('spent', child: PageWords(spent == null || spent == 0 ? 'None yet' : spentWords(spent), look.sans(look.em, color: spent == null || spent == 0 ? look.ink4 : look.ink), line: look.line, softWrap: false)),
      if (running != null)
        _tap(
          key: const ValueKey('ticket-timer-stop'),
          label: 'Stop the timer, ${elapsed(running)}${mine ? '' : ' on your ${running.deviceName ?? 'other device'}'}',
          onTap: widget.editable ? () => unawaited(stopTimerAsking(context, timers!, running)) : null,
          child: Part('timerOn', child: _chip('${elapsed(running)}${mine ? '' : ' on your ${running.deviceName ?? 'other device'}'}', icon: Lucide.square, color: red, strong: true)),
        )
      else if (timers != null && widget.editable)
        _tap(
          key: const ValueKey('ticket-timer-start'),
          label: 'Start a timer',
          onTap: () => unawaited(timers.start(options.noteId, title: options.title, key: options.ticketKey)),
          child: Part('timerStart', child: _chip('Start', icon: Lucide.play)),
        ),
      if (timers != null && widget.editable)
        _tap(
          key: const ValueKey('ticket-add-time'),
          label: 'Add time',
          onTap: () => unawaited(addTime(context, timers, options.noteId, named: options.ticketKey ?? options.title, today: options.today?.call())),
          child: Part('addTime', child: PageWords('Add time…', look.sans(look.xs, color: look.ink3), line: look.lineXs, softWrap: false)),
        ),
    ];
    return Wrap(spacing: look.space(2), runSpacing: look.space(1), crossAxisAlignment: WrapCrossAlignment.center, children: parts);
  }

  Color _stateColor(PullState state) => switch (state) {
        PullState.open => look.t.color('glacier-green-9'),
        PullState.draft => look.ink4,
        PullState.merged => look.t.color('glacier-violet-9'),
        PullState.closed => look.t.color('glacier-red-9'),
      };

  Widget _pulls(List<LinkedPull> pulls) => Wrap(
        spacing: look.space(2),
        runSpacing: look.space(1),
        children: <Widget>[
          for (final linked in pulls)
            _tap(
              key: ValueKey('ticket-pull-${linked.pull.number}'),
              label: '${linked.pull.repo} pull request ${linked.pull.number}, ${linked.pull.state.word}${linked.checks == null ? '' : ', ${linked.checks!.words}'}: ${linked.pull.title}',
              onTap: switch (widget.options.openUrl) { final open? when linked.pull.url.isNotEmpty => () => open(linked.pull.url), _ => null },
              child: Part(
                'pull',
                child: _chip(
                  '${linked.words}${switch (linked.checks) { PullChecks.passing => ' ✓', PullChecks.failing => ' ✕', PullChecks.pending => ' …', null => '' }}',
                  dot: _stateColor(linked.pull.state),
                  color: linked.checks == PullChecks.failing ? look.t.color('glacier-red-11') : null,
                ),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final pulls = options.pulls?.call() ?? const <LinkedPull>[];
    final showTime = options.timers != null || (spentMinutes(frontMatterValue(widget.front, 'spent')) ?? 0) > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showTime) Part('time', child: _row('Time', _time())),
        if (pulls.isNotEmpty) Part('pulls', child: _row('Pull requests', _pulls(pulls))),
      ],
    );
  }
}

// ---- the card's timer ----------------------------------------------------------------------------------------------

/// The timer on a ticket's card (query_board.dart), told by the root once there are timers; null draws none.
Widget? Function(QueryLook look, String noteId, {required String title, String? ticketKey})? ticketCardTimer;

/// A card's timer: the time so far with Stop while it runs, a quiet Start otherwise.
class TicketCardTimer extends StatefulWidget {
  const TicketCardTimer({super.key, required this.look, required this.timers, required this.noteId, required this.title, this.ticketKey});

  final QueryLook look;
  final TicketTimers timers;
  final String noteId;
  final String title;
  final String? ticketKey;

  @override
  State<TicketCardTimer> createState() => _TicketCardTimerState();
}

class _TicketCardTimerState extends State<TicketCardTimer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.timers.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.timers.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final running = widget.timers.on(widget.noteId);
    final red = look.t.color('glacier-red-11');
    final words = running == null ? null : widget.timers.elapsed(running);
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        container: true,
        button: true,
        label: running == null ? 'Start a timer on ${widget.ticketKey ?? widget.title}' : 'Stop the timer, $words',
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('card-timer-${widget.noteId}'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            fireMotor(HapticKind.selection);
            if (running == null) {
              unawaited(widget.timers.start(widget.noteId, title: widget.title, key: widget.ticketKey));
            } else {
              unawaited(stopTimerAsking(context, widget.timers, running));
            }
          },
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: look.space(1) / 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppIcon(running == null ? Lucide.play : Lucide.square, size: 11, strokeWidth: 2.2, color: running == null ? look.ink4 : red),
                if (words != null) ...<Widget>[SizedBox(width: look.space(1)), PageWords(words, look.sans(look.xs, color: red, weight: 'semibold'), line: look.lineXs, softWrap: false)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- the sheets ---------------------------------------------------------------------------------------------------

/// A sheet over the app, as the questions are asked (lib/sheet/ask_first.dart): answers what [build]'s `done` is
/// given, or null for one put away.
Future<T?> showWorkSheet<T>(BuildContext context, Widget Function(void Function(T? answer) done) build) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future<T?>.value();
  final answer = Completer<T?>();
  late final OverlayEntry entry;
  void done(T? value) {
    if (answer.isCompleted) return;
    entry.remove();
    answer.complete(value);
  }

  entry = OverlayEntry(builder: (_) => build(done));
  overlay.insert(entry);
  return answer.future;
}

/// Stops [timer], asking first where it ran past ten hours (lib/book/timers.dart `confirmLong`, which the root points
/// here).
Future<void> stopTimerAsking(BuildContext context, TicketTimers timers, RunningTimer timer) async {
  timers.confirmLong ??= (timer, minutes) => askLongTimer(context, timer, minutes);
  await timers.stop(timer);
}

/// A timer of more than ten hours, stopped: was it all work? Log all of it, some typed, or nothing; put away, it runs on.
Future<LongTimerAnswer?> askLongTimer(BuildContext context, RunningTimer timer, int minutes) => showWorkSheet<LongTimerAnswer>(context, (done) => LongTimerSheet(timer: timer, minutes: minutes, onAnswer: done));

class LongTimerSheet extends StatefulWidget {
  const LongTimerSheet({super.key, required this.timer, required this.minutes, required this.onAnswer});
  final RunningTimer timer;
  final int minutes;
  final ValueChanged<LongTimerAnswer?> onAnswer;

  @override
  State<LongTimerSheet> createState() => _LongTimerSheetState();
}

class _LongTimerSheetState extends State<LongTimerSheet> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final some = spentMinutes(_typed);
    return Sheet(
      key: const ValueKey('long-timer'),
      label: 'The timer ran ${spentWords(widget.minutes)}',
      onClose: () => widget.onAnswer(null),
      children: [
        SheetTitle.text('The timer on ${widget.timer.named} ran ${spentWords(widget.minutes)}'),
        const SheetNote('That is longer than ten hours. Was it all work?'),
        SheetGroup(
          children: [
            SheetRow(key: const ValueKey('long-timer-all'), label: 'Log all ${spentWords(widget.minutes)}', onPress: () => widget.onAnswer((minutes: widget.minutes))),
            SheetField(key: const ValueKey('long-timer-some'), label: 'Log only', placeholder: '2h 30m', autoCorrect: false, onChange: (typed) => setState(() => _typed = typed), onSubmitted: (_) => some == null ? null : widget.onAnswer((minutes: some))),
            SheetRow(key: const ValueKey('long-timer-typed'), label: some == null ? 'Log what is typed' : 'Log ${spentWords(some)}', disabled: some == null, onPress: some == null ? null : () => widget.onAnswer((minutes: some))),
            SheetRow(key: const ValueKey('long-timer-none'), label: 'Log nothing', danger: true, onPress: () => widget.onAnswer((minutes: null))),
            SheetRow(key: const ValueKey('long-timer-keep'), label: 'Keep it running', onPress: () => widget.onAnswer(null)),
          ],
        ),
      ],
    );
  }
}

/// Add time…: how long, which day, and a few words, logged at once.
Future<void> addTime(BuildContext context, TicketTimers timers, String noteId, {required String named, String? today}) async {
  final said = await showWorkSheet<({int minutes, String? day, String note})>(context, (done) => AddTimeSheet(named: named, today: today, onAnswer: done));
  if (said == null) return;
  await timers.add(noteId, said.minutes, day: said.day, note: said.note);
}

class AddTimeSheet extends StatefulWidget {
  const AddTimeSheet({super.key, required this.named, this.today, required this.onAnswer});
  final String named;
  final String? today;
  final ValueChanged<({int minutes, String? day, String note})?> onAnswer;

  @override
  State<AddTimeSheet> createState() => _AddTimeSheetState();
}

class _AddTimeSheetState extends State<AddTimeSheet> {
  String _time = '', _day = '', _note = '';

  void _add() {
    final minutes = spentMinutes(_time);
    final day = _day.trim();
    if (minutes == null || minutes <= 0 || (day.isNotEmpty && !isIsoDay(day))) return;
    widget.onAnswer((minutes: minutes, day: day.isEmpty ? null : day, note: _note.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final minutes = spentMinutes(_time);
    final dayWrong = _day.trim().isNotEmpty && !isIsoDay(_day.trim());
    final ok = minutes != null && minutes > 0 && !dayWrong;
    return Shortcuts(
      shortcuts: const {SingleActivator(LogicalKeyboardKey.escape): DismissIntent()},
      child: Actions(
        actions: {DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => widget.onAnswer(null))},
        child: Sheet(
          key: const ValueKey('add-time'),
          label: 'Add time to ${widget.named}',
          onClose: () => widget.onAnswer(null),
          children: [
            SheetTitle.text('Add time to ${widget.named}'),
            SheetGroup(
              children: [
                SheetField(key: const ValueKey('add-time-time'), label: 'Time', placeholder: '1h 30m', autoFocus: true, autoCorrect: false, onChange: (typed) => setState(() => _time = typed), onSubmitted: (_) => _add()),
                SheetField(key: const ValueKey('add-time-day'), label: 'Day', placeholder: widget.today ?? 'Today', autoCorrect: false, inputMode: TextInputType.datetime, onChange: (typed) => setState(() => _day = typed), onSubmitted: (_) => _add()),
                SheetField(key: const ValueKey('add-time-note'), label: 'What', placeholder: 'Optional', onChange: (typed) => setState(() => _note = typed), onSubmitted: (_) => _add()),
              ],
            ),
            SheetNote(
              dayWrong
                  ? 'A day is written 2026-10-31.'
                  : minutes == null
                      ? 'Hours and minutes, like 1h 30m or 45m.'
                      : 'Logs ${spentWords(minutes)} under Time, and adds it to the ticket’s spent.',
            ),
            SheetGroup(
              children: [
                SheetRow(key: const ValueKey('add-time-add'), label: 'Add', disabled: !ok, onPress: ok ? _add : null),
                SheetRow(key: const ValueKey('add-time-cancel'), label: 'Cancel', onPress: () => widget.onAnswer(null)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

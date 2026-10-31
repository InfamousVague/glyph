/// A timer on a ticket (Matt, 2026-10-31, of the ticket features: "time tracking"): Start, and Stop logs the time in
/// the ticket's own words (time_log.dart: a line under `## Time`, and `spent:` its total).
///
/// - **One a device.** Each device of the account runs one timer at most; starting another stops the first and logs
///   it. Timers are kept by device in the synced settings ([ticketTimersKey], `{device: {note, title, key, start,
///   who, name}}`), so the one running on the Mac shows on the phone, in the ticket's panel and in the activity tray
///   ("Timer on HT-12 · on your Mac"), and either can stop it: whichever does logs it, once, and takes it out of the
///   map, which the other hears as its timer gone. Merged a device at a time, so two devices' timers never meet.
/// - **On the record of running work** (docs/ACTIVITY.md): this device's timer is a job, `timer:<note>`, its line the
///   time so far, put right every minute, with Stop; another device's is told as that device's.
/// - **A long one asks.** A timer left running for more than [longTimer] asks, when it is stopped, whether that was
///   all work ([TicketTimers.confirmLong]): keep it all, keep some, or log nothing.
/// - Manual time is [TicketTimers.add], "Add time…": the same line, written at once.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/summary_handoff.dart' show SummaryDevice;
import '../core/background_jobs.dart';
import '../core/days.dart' show isoDay;
import '../core/durations.dart' show spentWords;
import '../core/preferences.dart' show Preferences;
import 'time_log.dart';

/// The running timers, by device, in the synced settings.
const String ticketTimersKey = 'ticketTimers';

/// The source another device's timers are told to the record of running work under.
const String timersJobsSource = 'ticket-timers';

/// How long a timer runs before stopping it asks whether it was all work.
const Duration longTimer = Duration(hours: 10);

/// A timer running on one of the account's devices.
@immutable
class RunningTimer {
  const RunningTimer({required this.device, this.deviceName, required this.noteId, required this.title, this.key, required this.start, this.who = ''});

  static RunningTimer? fromJson(String device, Object? raw) {
    if (raw is! Map || raw['note'] is! String || raw['start'] is! num) return null;
    String? text(String k) => raw[k] is String && (raw[k] as String).isNotEmpty ? raw[k] as String : null;
    return RunningTimer(device: device, deviceName: text('name'), noteId: raw['note'] as String, title: text('title') ?? '', key: text('key'), start: (raw['start'] as num).toInt(), who: text('who') ?? '');
  }

  final String device;
  final String? deviceName;
  final String noteId;
  final String title;

  /// The ticket's key, `HT-12`, where it has one.
  final String? key;

  /// When it started, in ms.
  final int start;

  /// Whose time it is, as the log names them.
  final String who;

  /// What the ticket is called on a row: its key, else its title.
  String get named => key ?? (title.isEmpty ? 'a ticket' : title);

  int minutesAt(int now) => ((now - start) / 60000).round();

  Map<String, Object?> toJson() => {'note': noteId, 'title': title, if (key != null) 'key': key, 'start': start, if (who.isNotEmpty) 'who': who, if (deviceName != null) 'name': deviceName};

  @override
  bool operator ==(Object other) => other is RunningTimer && other.device == device && other.noteId == noteId && other.start == start && other.title == title && other.key == key && other.who == who && other.deviceName == deviceName;

  @override
  int get hashCode => Object.hash(device, noteId, start, title, key, who, deviceName);

  @override
  String toString() => 'RunningTimer($named on $device since $start)';
}

/// Every timer running, by device.
Map<String, RunningTimer> timersOf(Preferences prefs) {
  final raw = prefs.more[ticketTimersKey];
  if (raw is! Map) return const {};
  return {
    for (final MapEntry(:key, :value) in raw.entries)
      if (key is String) key: ?RunningTimer.fromJson(key, value),
  };
}

Preferences _withTimer(Preferences prefs, String device, RunningTimer? timer) {
  final raw = prefs.more[ticketTimersKey];
  final map = <String, Object?>{if (raw is Map) ...raw.cast<String, Object?>()};
  if (timer == null) {
    map.remove(device);
  } else {
    map[device] = timer.toJson();
  }
  return prefs.copyWith(more: {...prefs.more, ticketTimersKey: map});
}

/// Whether a timer that has run [minutes] asks before it is logged.
bool asksBeforeLogging(int minutes) => minutes > longTimer.inMinutes;

/// What the person said of a long timer: log [minutes] (all of it, or what they typed), or nothing (null minutes).
typedef LongTimerAnswer = ({int? minutes});

/// The timers, for the life of the app (see the header).
class TicketTimers extends ChangeNotifier {
  TicketTimers({required this.device, required this.preferences, required this.setPreferences, required this.write, required this.who, this.prefsChanged, int Function()? clock, this.confirmLong})
      : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    prefsChanged?.addListener(_heard);
    _heard();
  }

  final SummaryDevice Function() device;
  final Preferences Function() preferences;
  final void Function(Preferences Function(Preferences now) change) setPreferences;

  /// Changes a note's words: what a stop's log line is written with.
  final Future<void> Function(String noteId, String Function(String body) change) write;

  /// Who the person is, as the log names them.
  final String Function() who;

  /// Told when the synced settings change, so a timer started or stopped on another device is heard.
  final Listenable? prefsChanged;
  final int Function() clock;

  /// Asked when a timer of more than [longTimer] is stopped; null (or none given) leaves it running.
  Future<LongTimerAnswer?> Function(RunningTimer timer, int minutes)? confirmLong;

  Map<String, RunningTimer> _all = const {};

  /// Every timer running, this device's first.
  List<RunningTimer> get all {
    final me = device().id;
    return [?_all[me], for (final MapEntry(:key, :value) in _all.entries) if (key != me) value];
  }

  /// This device's timer, if one runs.
  RunningTimer? get mine => _all[device().id];

  /// The timer running on [noteId], this device's before another's; null for none.
  RunningTimer? on(String noteId) => all.where((timer) => timer.noteId == noteId).firstOrNull;

  /// How long [timer] has run, in words: `1h 12m`.
  String elapsed(RunningTimer timer) => spentWords(timer.minutesAt(clock()));

  void _heard() {
    final next = timersOf(preferences());
    final was = _all;
    if (mapEquals(next, was)) return;
    _all = next;
    final me = device().id;
    // This device's timer stopped elsewhere: its job goes with it.
    final mineWas = was[me];
    if (mineWas != null && next[me] != mineWas && !_ending.contains(mineWas.start)) activity.handle(_jobId(mineWas.noteId))?.stopped();
    _tell();
    notifyListeners();
  }

  static String _jobId(String noteId) => 'timer:$noteId';

  Timer? _ticking;

  /// The record of running work told: this device's timer as its job, the others' as theirs; and every minute again.
  void _tell() {
    final me = device().id;
    final now = clock();
    final mine = _all[me];
    if (mine != null) {
      final minutes = mine.minutesAt(now);
      activity.begin(
        _jobId(mine.noteId),
        kind: JobKind.audio,
        title: 'Timer on ${mine.named}',
        line: asksBeforeLogging(minutes) ? '${spentWords(minutes)}. Still going? Stop it to check.' : spentWords(minutes),
        personStarted: true,
        onStop: () => unawaited(stop()),
        onOpen: activityRoutes.noteOpener(mine.noteId),
      );
    }
    activity.elsewhere(timersJobsSource, [
      for (final MapEntry(:key, :value) in _all.entries)
        if (key != me)
          Job(
            id: _jobId(value.noteId),
            kind: JobKind.audio,
            title: 'Timer on ${value.named}',
            line: spentWords(value.minutesAt(now)),
            device: key,
            deviceName: value.deviceName,
            startedAt: DateTime.fromMillisecondsSinceEpoch(value.start),
            onOpen: activityRoutes.noteOpener(value.noteId),
          ),
    ]);
    _ticking?.cancel();
    _ticking = _all.isEmpty ? null : Timer(const Duration(minutes: 1), _tell);
  }

  /// A timer started on [noteId] on this device; this device's running one, on another ticket, is stopped and logged
  /// first. One already running on it goes on.
  Future<void> start(String noteId, {required String title, String? key}) async {
    final running = mine;
    if (running != null && running.noteId == noteId) return;
    if (running != null) await stop();
    final me = device();
    final timer = RunningTimer(device: me.id, deviceName: me.name, noteId: noteId, title: title, key: key, start: clock(), who: who());
    setPreferences((prefs) => _withTimer(prefs, me.id, timer));
    _heard();
  }

  /// Stops [which] (this device's where null; another device's too) and logs it in its ticket: answers the line
  /// logged, or null for nothing to stop, a long one left running, or one logged as nothing.
  Future<TimeEntry?> stop([RunningTimer? which]) async {
    final timer = which ?? mine;
    if (timer == null) return null;
    var minutes = timer.minutesAt(clock());
    if (asksBeforeLogging(minutes)) {
      final ask = confirmLong;
      final said = ask == null ? null : await ask(timer, minutes);
      if (said == null) return null;
      minutes = said.minutes ?? 0;
    }
    _ending.add(timer.start);
    setPreferences((prefs) => timersOf(prefs)[timer.device]?.start == timer.start ? _withTimer(prefs, timer.device, null) : prefs);
    final job = activity.handle(_jobId(timer.noteId)) ?? activity.begin(_jobId(timer.noteId), kind: JobKind.audio, title: 'Timer on ${timer.named}');
    try {
      if (minutes <= 0) {
        job.stopped();
        return null;
      }
      final entry = TimeEntry(day: isoDay(DateTime.fromMillisecondsSinceEpoch(clock())), minutes: minutes, who: timer.who);
      try {
        await write(timer.noteId, (body) => withTimeLogged(body, entry));
      } catch (failure) {
        job.failed('${spentWords(minutes)} on ${timer.named} was not logged: $failure');
        rethrow;
      }
      job.done(result: JobResult('Logged ${spentWords(minutes)} on ${timer.named}'), tally: const JobTally('timer logged', 'timers logged'), quiet: true);
      return entry;
    } finally {
      _ending.remove(timer.start);
      _heard();
    }
  }

  /// The timers this device is stopping now, by when they started: their jobs end as the stop says, not as gone.
  final Set<int> _ending = <int>{};

  /// [minutes] logged on [noteId] by hand ("Add time…"), on [day] (today where null), with a few words.
  Future<TimeEntry?> add(String noteId, int minutes, {String? day, String note = ''}) async {
    if (minutes <= 0) return null;
    final entry = TimeEntry(day: day ?? isoDay(DateTime.fromMillisecondsSinceEpoch(clock())), minutes: minutes, who: who(), note: note);
    await write(noteId, (body) => withTimeLogged(body, entry));
    return entry;
  }

  @override
  void dispose() {
    prefsChanged?.removeListener(_heard);
    _ticking?.cancel();
    activity.elsewhere(timersJobsSource, const []);
    super.dispose();
  }
}

/// The app's timers, told by the root once it has made them; null in a build or a test that has none.
final ValueNotifier<TicketTimers?> ticketTimers = ValueNotifier<TicketTimers?>(null);

/// The app's one record of the work it is doing (Matt, 2026-10-29: "better show users what background processes are
/// happening with vivid colors and iconography and more", then "Do them all"; docs/ACTIVITY.md), and the hint to the
/// device that keeps such work going.
///
/// THE RECORD ([Activity], the app's [activity]). Every job the app runs on its own - a banner run, a meeting's
/// write-up, a sync, a recording, a download, a post - is begun here where it really starts ([Activity.begin]), told
/// how far it is as it goes ([JobHandle.progress]), what it waits on ([JobHandle.waiting]) and how it ended
/// ([JobHandle.done], [JobHandle.failed], [JobHandle.stopped]). The ring in the header, the tray under it and the
/// result chips (lib/activity/) draw what is here; the OS surfaces (a phone's notifications, the Mac's Dock and menu
/// bar, an iPhone's Live Activities) hear [Activity.events]. What ended is counted into this device's log
/// ([ActivityLog]): Today, and the Past 7 days. docs/ACTIVITY.md, "The API", says how to use it.
///
/// THE DEVICE HALF ([BackgroundJobs]). A job the app runs on its own, told to the device it runs on, so the device
/// keeps it going (Matt, 2026-10-26: "Make the header generation async and a background task that runs while the app
/// is generating the images"). The first is Lovart's header images for the recent notes
/// (lib/plugins/lovart/banner_run.dart); the channel is named for any job, `ghost_md/jobs`.
///
/// - **Android** (android/…/ghost_md/BackgroundJobs.kt): `running` starts a foreground service, or tells the one
///   started what to say, as the meeting's recording and write-up hold the app up (capture/MeetingService.kt). Its
///   ongoing notification says the job's title and how far it is, with Stop, which comes back here as `stop`; a
///   partial wake lock is held with it, so the job goes on with the screen off or the app behind another. `ended`
///   lets the service go and posts a notification that says how it ended, as a meeting's "Written up" does.
/// - **The Mac app** (macos/Runner/MainFlutterWindow.swift): `running` keeps the app out of App Nap, which slows the
///   timers and fetches of an app whose window is behind others; `ended` lets it nap again. No notification: the
///   app's own toast says it.
/// - Anywhere else (a test, an iPhone, the web): nothing, and the job runs while the app does.
///
/// The same channel carries the record to the OS surfaces (lib/activity/activity_surfaces.dart: `activity`,
/// `activityLook`, and `activityStop` / `activityOpen` back): Android's progress notifications, the Mac's Dock ring
/// and menu bar item, an iPhone's Live Activities. [JobsHeard] is what hears the device on it.
///
/// Nothing is waited on: a channel that does not answer is a device without the half, never a job that cannot run.
/// The two halves are apart on purpose: the record is for the person to see, the device half for the device to hold
/// on, and a job that holds the device tells both.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'activity_log.dart';
import 'mac_app.dart' show runsAsMacApp;
import 'stored.dart';

export 'activity_log.dart';

/// The device, told of the app's jobs.
abstract interface class BackgroundJobs {
  /// The job [id] is running: [title] ("Making header images") and [text] ("12 of 100") on its notification, with
  /// how far it is where it says.
  Future<void> running(String id, {required String title, required String text, int? done, int? total});

  /// It ended: the device lets it go, and says [title] (with [text] under it) where it notifies; [quiet], it says
  /// nothing (a picture or two made, which the app shows itself). Others still running keep the device holding on.
  Future<void> ended(String id, {required String title, String? text, bool quiet = false});

  /// Who is told when the person stops the job from the device's own notification.
  void onStop(void Function(String id)? stop);
}

/// Nothing told: a test, and a build with no half for it.
class NoBackgroundJobs implements BackgroundJobs {
  const NoBackgroundJobs();

  @override
  Future<void> running(String id, {required String title, required String text, int? done, int? total}) async {}

  @override
  Future<void> ended(String id, {required String title, String? text, bool quiet = false}) async {}

  @override
  void onStop(void Function(String id)? stop) {}
}

/// The channel the jobs are told on.
const MethodChannel jobsChannel = MethodChannel('ghost_md/jobs');

/// The phone's and the Mac's half, over [jobsChannel].
class ChannelBackgroundJobs implements BackgroundJobs {
  ChannelBackgroundJobs({MethodChannel channel = jobsChannel, bool? here}) : _channel = channel, _here = here ?? (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || runsAsMacApp));

  final MethodChannel _channel;
  final bool _here;

  Future<void> _ask(String method, Map<String, Object?> arguments) async {
    if (!_here) return;
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // A build from before the half.
    } on PlatformException catch (failure) {
      debugPrint('[ghost] the device was not told of the job: ${failure.message}');
    }
  }

  @override
  Future<void> running(String id, {required String title, required String text, int? done, int? total}) =>
      _ask('running', {'id': id, 'title': title, 'text': text, 'done': ?done, 'total': ?total});

  @override
  Future<void> ended(String id, {required String title, String? text, bool quiet = false}) => _ask('ended', {'id': id, 'title': title, 'text': ?text, if (quiet) 'quiet': true});

  @override
  void onStop(void Function(String id)? stop) {
    if (!_here) return;
    JobsHeard.on(_channel).stops(this, stop);
  }
}

/// What the device says on a jobs channel, heard by everyone who asked: the phone's service notification's Stop
/// (`stop {id}`, the banner run's), and the OS surfaces' Stop and Open (lib/activity/activity_surfaces.dart). A
/// channel has one handler, so it is set here once for all of them: each [ChannelBackgroundJobs] the root makes would
/// otherwise take it from the one before.
class JobsHeard {
  JobsHeard._(this.channel);

  static final Map<String, JobsHeard> _on = {};

  /// The one for [channel]'s name.
  factory JobsHeard.on(MethodChannel channel) => _on.putIfAbsent(channel.name, () => JobsHeard._(channel));

  final MethodChannel channel;
  final Map<Object, void Function(String id)> _stops = {};
  Future<Object?> Function(MethodCall call)? _surfaces;

  /// [who] hears the service's Stop, or no longer does ([stop] null).
  void stops(Object who, void Function(String id)? stop) {
    if (stop == null) {
      _stops.remove(who);
    } else {
      _stops[who] = stop;
    }
    _listen();
  }

  /// Everything else the device says (`activityStop`, `activityOpen`), to the OS surfaces; null, nobody.
  set surfaces(Future<Object?> Function(MethodCall call)? heard) {
    _surfaces = heard;
    _listen();
  }

  void _listen() => channel.setMethodCallHandler(_stops.isEmpty && _surfaces == null ? null : _heard);

  Future<Object?> _heard(MethodCall call) async {
    final args = call.arguments;
    if (call.method == 'stop') {
      if (args is Map && args['id'] is String) {
        for (final stop in [..._stops.values]) {
          stop(args['id'] as String);
        }
      }
      return null;
    }
    return _surfaces?.call(call);
  }

  /// Forgets every channel's listeners: a test's fresh start.
  @visibleForTesting
  static void reset() {
    for (final heard in _on.values) {
      heard.channel.setMethodCallHandler(null);
    }
    _on.clear();
  }
}

// ---- the record -----------------------------------------------------------------------------------------------------

/// What a job is, which is the colour and the glyph it wears (docs/ACTIVITY.md, Kinds): sync blue, AI writing violet,
/// images amber-pink, audio teal, meetings orange, downloads and updates green.
enum JobKind {
  sync('Sync'),
  ai('Writing'),
  images('Pictures'),
  audio('Audio'),
  meetings('Meetings'),
  downloads('Downloads');

  const JobKind(this.word);

  /// The kind in a word, for a screen reader and the tray.
  final String word;
}

/// What a job is drawn as: its kind while it runs, and two states over any kind - something needs the person (a
/// still red dot), and waiting on something (its glyph dimmed and still).
enum JobLook { sync, ai, images, audio, meetings, downloads, needsYou, waiting }

/// Where a job is.
enum JobState {
  queued,
  running,
  waiting,
  done,
  failed;

  /// Still to end: in the ring.
  bool get live => this == queued || this == running || this == waiting;
}

/// What a waiting job waits on, in the words the tray says it in.
enum WaitingOn {
  wifi('Waiting for Wi-Fi'),
  charger('Waiting for the charger'),
  credits('Waiting for credits'),
  otherDevice('Waiting for your other device'),
  signIn('Waiting for you to sign in'),
  network('Waiting for the network'),
  model('Waiting for the model'),
  turn('Waiting its turn');

  const WaitingOn(this.words);

  final String words;

  /// Whether only the person can end the wait: the ring's red dot.
  bool get needsYou => this == signIn || this == credits;
}

/// The one thing a failed job offers: Top up (the provider's billing page), Sign in again (the plugin's setup) or
/// Retry.
enum JobFixKind {
  topUp('Top up'),
  signIn('Sign in again'),
  retry('Retry'),
  open('Open');

  const JobFixKind(this.label);

  final String label;
}

/// A failed job's one fix: what it is called and what a press does.
@immutable
class JobFix {
  const JobFix(this.kind, this.onPress, {String? label}) : _label = label;

  /// Top up, by the provider's billing link, opened by [open] (the app's own way of opening a link).
  factory JobFix.topUp(Uri billing, void Function(Uri link) open) => JobFix(JobFixKind.topUp, () => open(billing));

  final JobFixKind kind;
  final VoidCallback onPress;
  final String? _label;

  String get label => _label ?? kind.label;
}

/// What a job will cost, said before it starts where it is a lot ([asks]) and in the tray as it runs.
@immutable
class JobEstimate {
  const JobEstimate({this.credits, this.provider, this.duration, this.count, this.one, this.many});

  /// Its credits, and whose ("Lovart").
  final int? credits;
  final String? provider;

  /// How long it should take.
  final Duration? duration;

  /// How many things it makes, and what one and many are called: 12, banner, banners.
  final int? count;
  final String? one, many;

  /// Over about 20 credits or 2 minutes, a job asks first (docs/ACTIVITY.md, Cost).
  static const int askCredits = 20;
  static const Duration askDuration = Duration(minutes: 2);

  /// Whether the person is asked before it starts.
  bool get asks => (credits ?? 0) > askCredits || (duration ?? Duration.zero) > askDuration;

  /// "12 banners · ~72 Lovart credits · ~4 min".
  String get words => [
        if (count != null && one != null) '$count ${count == 1 ? one : (many ?? '${one}s')}',
        if (credits != null) '~$credits ${provider == null ? '' : '$provider '}credit${credits == 1 ? '' : 's'}',
        if (duration != null) '~${durationWords(duration!)}',
      ].join(' · ');
}

/// A short length of time: "40 s", "4 min", "1 h 10 min".
String durationWords(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds < 1 ? 1 : d.inSeconds} s';
  final minutes = (d.inSeconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// A size in words, for a download's steps: "640 KB", "45 MB", "1.2 GB".
String bytesWords(int bytes) {
  if (bytes < 1000000) return '${(bytes / 1000).round()} KB';
  if (bytes < 1000000000) return '${(bytes / 1000000).round()} MB';
  final gb = bytes / 1000000000;
  return '${gb < 10 ? gb.toStringAsFixed(1) : gb.round()} GB';
}

/// A download's steps: "45 MB of 190 MB".
String downloadSteps(int received, int total) => '${bytesWords(received)} of ${bytesWords(total)}';

/// What a finished job made, for its result chip and the tray's Open: "Banner ready", "View".
@immutable
class JobResult {
  const JobResult(this.words, {this.action = 'View', this.onOpen});

  final String words;
  final String action;
  final VoidCallback? onOpen;
}

/// What a job counts for in the log: one and many of what it made, and how many ("3 summaries", "40 notes synced").
@immutable
class JobTally {
  const JobTally(this.one, this.many, [this.count = 1]);

  final String one, many;
  final int count;

  String get words => '$count ${count == 1 ? one : many}';
}

/// One job as it is now: a value, so a listener can keep the last one and compare.
@immutable
class Job {
  const Job({
    required this.id,
    required this.kind,
    required this.title,
    this.state = JobState.running,
    this.fraction,
    this.steps,
    this.line,
    this.waitingOn,
    this.onStop,
    this.onOpen,
    this.device,
    this.deviceName,
    required this.startedAt,
    this.endedAt,
    this.personStarted = false,
    this.estimate,
    this.spent,
    this.cause,
    this.fix,
    this.result,
    this.tally,
    this.attempt = 0,
    this.retryAt,
    this.shownHere,
    this.placeWords,
    this.hiddenUntil,
    this.plugin,
  });

  /// Its name, the same for every pass of the same work: `lovart-banners`, `sync`, `summary:<note>`.
  final String id;
  final JobKind kind;

  /// What it is, in a few words: "Making header images", "Summary of Standup".
  final String title;
  final JobState state;

  /// How far, 0 to 1; null while nobody can say (an indeterminate bar).
  final double? fraction;

  /// How far in words: "2 of 3 parts".
  final String? steps;

  /// What it is doing now: "Writing the summary".
  final String? line;

  /// What it waits on, while it waits.
  final WaitingOn? waitingOn;

  /// Stop, where it can be stopped; and Open, where its result (or the work itself) can be looked at.
  final VoidCallback? onStop, onOpen;

  /// The device it runs on, by the summary handoff's id (lib/ai/summary_handoff.dart), and what a person calls it
  /// ("Mac"); null is this device.
  final String? device, deviceName;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Whether the person asked for it (a run started from Settings, a read-aloud): only such a job, and one that ran
  /// a while, ends with a chime.
  final bool personStarted;
  final JobEstimate? estimate;

  /// The credits spent so far.
  final int? spent;

  /// Why it failed, in plain words, and the one fix.
  final String? cause;
  final JobFix? fix;

  /// What it made.
  final JobResult? result;

  /// What it counts for in the log.
  final JobTally? tally;

  /// How many times it has been tried again after a blip, and when the next try is.
  final int attempt;
  final DateTime? retryAt;

  /// Whether the person is looking at what it makes as it ends (the note the banner lands in is open): then no chip.
  final bool Function()? shownHere;

  /// Where it runs, in words, for work that is on no device of the person's: the meeting bot's.
  final String? placeWords;

  /// Kept from the ring and the tray until then (a sync pass, a fetch: shown only once it has taken a while, or
  /// [JobHandle.show]n); null is shown from the start.
  final DateTime? hiddenUntil;

  /// The plugin whose work it is, by its manifest's id (`lovart`, `claude`, `elevenlabs`), said where the job begins
  /// and never guessed from its title: it then wears that plugin's mark in the tray, the log, its chip and the ring's
  /// middle in place of its kind's glyph (Matt, 2026-10-30: "use plugin vendor logo icons for activity updates related
  /// to plugins"; lib/activity/job_mark.dart). Null for the app's own work: a sync, a recording, an update.
  final String? plugin;

  /// Whether it runs on this device.
  bool get here => device == null;

  /// What the ring and the tray draw it as.
  JobLook get look {
    if (state == JobState.failed || (waitingOn?.needsYou ?? false)) return JobLook.needsYou;
    if (state == JobState.waiting || state == JobState.queued) return JobLook.waiting;
    return JobLook.values[kind.index];
  }

  /// Whether only the person can move it on.
  bool get needsYou => look == JobLook.needsYou;

  /// How long it took, once it ended.
  Duration? get took => endedAt?.difference(startedAt);

  /// "on your Mac", for a job elsewhere.
  String? get deviceWords => placeWords ?? (here ? null : 'on your ${deviceName == null || deviceName!.isEmpty ? 'other device' : deviceName}');

  /// The tray's live line: what it is doing and how far ("Writing the summary, 2 of 3 parts"), what it waits on
  /// ("Waiting for Wi-Fi"), or why it failed.
  String get liveLine {
    if (state == JobState.failed) return cause ?? 'Failed';
    if (state == JobState.waiting || state == JobState.queued) return line ?? waitingOn?.words ?? (state == JobState.queued ? 'Waiting its turn' : 'Waiting');
    final doing = line ?? title;
    return steps == null ? doing : '$doing, $steps';
  }

  Job copyWith({
    String? title,
    JobState? state,
    double? Function()? fraction,
    String? Function()? steps,
    String? Function()? line,
    WaitingOn? Function()? waitingOn,
    VoidCallback? Function()? onStop,
    VoidCallback? Function()? onOpen,
    DateTime? Function()? endedAt,
    JobEstimate? estimate,
    int? spent,
    String? Function()? cause,
    JobFix? Function()? fix,
    JobResult? Function()? result,
    JobTally? Function()? tally,
    int? attempt,
    DateTime? Function()? retryAt,
    bool? personStarted,
    DateTime? Function()? hiddenUntil,
    String? Function()? plugin,
  }) =>
      Job(
        id: id,
        kind: kind,
        title: title ?? this.title,
        state: state ?? this.state,
        fraction: fraction == null ? this.fraction : fraction(),
        steps: steps == null ? this.steps : steps(),
        line: line == null ? this.line : line(),
        waitingOn: waitingOn == null ? this.waitingOn : waitingOn(),
        onStop: onStop == null ? this.onStop : onStop(),
        onOpen: onOpen == null ? this.onOpen : onOpen(),
        device: device,
        deviceName: deviceName,
        startedAt: startedAt,
        endedAt: endedAt == null ? this.endedAt : endedAt(),
        personStarted: personStarted ?? this.personStarted,
        estimate: estimate ?? this.estimate,
        spent: spent ?? this.spent,
        cause: cause == null ? this.cause : cause(),
        fix: fix == null ? this.fix : fix(),
        result: result == null ? this.result : result(),
        tally: tally == null ? this.tally : tally(),
        attempt: attempt ?? this.attempt,
        retryAt: retryAt == null ? this.retryAt : retryAt(),
        shownHere: shownHere,
        placeWords: placeWords,
        hiddenUntil: hiddenUntil == null ? this.hiddenUntil : hiddenUntil(),
        plugin: plugin == null ? this.plugin : plugin(),
      );

  @override
  String toString() => 'Job($id, ${kind.name}, ${state.name}${fraction == null ? '' : ' ${(fraction! * 100).round()}%'}${here ? '' : ' on $deviceName'})';
}

/// What [Activity.events] says: a job began, moved, or ended; or the last live job ended and the ring blooms.
enum JobEventKind { started, changed, ended, allDone }

@immutable
class JobEvent {
  const JobEvent(this.kind, this.job);

  final JobEventKind kind;

  /// The job as it is after the event; null for [JobEventKind.allDone].
  final Job? job;

  @override
  String toString() => 'JobEvent(${kind.name}, $job)';
}

/// A job on the record, as the code that runs it holds it: every change to the job goes through here. A handle whose
/// job has ended does nothing, so the code that runs it never has to ask.
class JobHandle {
  JobHandle._(this._activity, this.id);

  final Activity _activity;
  final String id;

  /// The job now, or null once it has ended and gone from the record.
  Job? get job => _activity._jobs[id];

  /// Whether it is still to end.
  bool get live => job?.state.live ?? false;

  void _change(Job Function(Job job) change) {
    final now = job;
    if (now == null || !now.state.live) return;
    _activity._put(change(now), JobEventKind.changed);
  }

  /// How far it is: [done] of [total] (which also says "[done] of [total] [unit]" as its steps unless [steps] is
  /// given), or a [fraction]; [line] is what it is doing now. A waiting job told how far it is runs again.
  void progress({int? done, int? total, double? fraction, String? steps, String? unit, String? line}) => _change((job) {
        final f = fraction ?? (done != null && total != null && total > 0 ? (done / total).clamp(0.0, 1.0) : job.fraction);
        final words = steps ?? (done != null && total != null && total > 1 ? '$done of $total${unit == null ? '' : ' $unit'}' : job.steps);
        return job.copyWith(state: JobState.running, fraction: () => f, steps: () => words, line: line == null ? null : () => line, waitingOn: () => null, retryAt: () => null);
      });

  /// It runs again, or says what it is doing now: [line].
  void running({String? line}) => _change((job) => job.copyWith(state: JobState.running, waitingOn: () => null, retryAt: () => null, line: line == null ? null : () => line));

  /// It waits on [on] ([line] says it otherwise: "Trying again in 8 s").
  void waiting(WaitingOn on, {String? line, DateTime? retryAt}) => _change((job) => job.copyWith(state: JobState.waiting, waitingOn: () => on, line: () => line, retryAt: () => retryAt));

  /// It waits its turn behind another.
  void queued({String? line}) => _change((job) => job.copyWith(state: JobState.queued, line: () => line));

  /// Anything else about it: its title, its Stop and Open, its estimate, the credits spent so far.
  void update({String? title, VoidCallback? onStop, VoidCallback? onOpen, JobEstimate? estimate, int? spent}) =>
      _change((job) => job.copyWith(title: title, onStop: onStop == null ? null : () => onStop, onOpen: onOpen == null ? null : () => onOpen, estimate: estimate, spent: spent));

  /// [credits] more spent.
  void spend(int credits) => _change((job) => job.copyWith(spent: (job.spent ?? 0) + credits));

  /// Shown now, though it was begun to be shown only after a while ([Activity.begin]'s `showAfter`): a sync pass
  /// that has moved something.
  void show() {
    if (job?.hiddenUntil == null) return;
    _change((job) => job.copyWith(hiddenUntil: () => null));
  }

  /// The words it has written so far, where it writes as it goes (Claude streaming a meeting's summary): read in place,
  /// by what draws the work where it lands ([Activity.wordsOf]; lib/editor/ai/summary_writing.dart). Kept off the [Job]:
  /// a change every few letters would be told to the ring, the tray and the OS surfaces each time.
  void write(String sofar) => _activity._write(id, sofar);

  /// Whether the ring and the tray show it now.
  bool get shown => job != null && _activity._shows(job!);

  /// It ended well: [result] for its chip and Open, [tally] for the log (a run's 12 banners). [quiet] counts it and
  /// shows no chip and plays no chime.
  void done({JobResult? result, JobTally? tally, bool quiet = false}) => _activity._end(id, JobState.done, result: result, tally: tally, quiet: quiet);

  /// It failed: [cause] in plain words ("Lovart is out of credits"), and the one [fix]. It stays in the tray, red,
  /// until it is retried, dismissed, or begun again.
  void failed(String cause, {JobFix? fix, JobTally? tally}) => _activity._end(id, JobState.failed, cause: cause, fix: fix, tally: tally);

  /// The person stopped it, or it stopped with nothing to say: it goes, counted for what it made ([tally]).
  void stopped({JobTally? tally}) => _activity._end(id, JobState.done, tally: tally, quiet: true, stopped: true);
}

/// Whether [error] is the network blinking (a socket closed, a lookup that failed, a timeout), which a job tries again
/// on its own before it says it failed.
bool isNetworkBlip(Object error) {
  if (error is TimeoutException) return true;
  final name = error.runtimeType.toString();
  return name.contains('SocketException') || name.contains('ClientException') || name.contains('HandshakeException') || name.contains('HttpException');
}

/// How long a job waits before each try again after a blip: three tries again, then it fails.
const List<Duration> blipBackoff = [Duration(seconds: 2), Duration(seconds: 8), Duration(seconds: 30)];

/// Runs [attempt] for [job], trying again after a network blip ([blip]) on [backoff]'s waits, the job said waiting
/// for the network meanwhile ("Trying again in 8 s") and running again as each try starts. What the last try throws,
/// or anything that is not a blip, is thrown on, for the caller to fail the job with its own words.
Future<T> retrying<T>(JobHandle job, Future<T> Function() attempt, {bool Function(Object error) blip = isNetworkBlip, List<Duration> backoff = blipBackoff, Future<void> Function(Duration wait)? wait}) async {
  final sleep = wait ?? (Duration d) => Future<void>.delayed(d);
  for (var tries = 0;; tries += 1) {
    try {
      return await attempt();
    } catch (error) {
      if (tries >= backoff.length || !blip(error) || !job.live) rethrow;
      final pause = backoff[tries];
      // What it said before the blip, said again as it tries again.
      final before = job.job?.line;
      job._change((j) => j.copyWith(attempt: tries + 1));
      job.waiting(WaitingOn.network, line: 'Trying again in ${durationWords(pause)}', retryAt: job._activity.now.add(pause));
      await sleep(pause);
      if (!job.live) rethrow;
      job._change((j) => j.copyWith(state: JobState.running, waitingOn: () => null, retryAt: () => null, line: () => before));
    }
  }
}

/// The app's record of running work (see the header): a [ValueListenable] of the jobs to show (the live ones, and the
/// failed ones until dismissed, this device's and the account's other devices'), [events] for the OS surfaces, and
/// [log] of what ended.
class Activity extends ChangeNotifier implements ValueListenable<List<Job>> {
  Activity({DateTime Function()? clock, Stored Function()? store, this.longJob = const Duration(seconds: 30)})
      : _clock = clock ?? DateTime.now,
        log = ActivityLog(store: store, clock: clock);

  final DateTime Function() _clock;

  /// What ended is counted here.
  final ActivityLog log;

  /// How long a job the person started must have run for its end to chime.
  final Duration longJob;

  /// Called as a job the person started, that ran over [longJob], ends well or badly: the root plays the chime and
  /// the tap (lib/activity/activity_chime.dart). Never for sync, nor a job ended quietly or stopped.
  void Function(Job job)? onChime;

  final Map<String, Job> _jobs = {};
  final Map<String, List<Job>> _elsewhere = {};
  final StreamController<JobEvent> _events = StreamController<JobEvent>.broadcast(sync: true);
  List<Job>? _shown;
  int _blooms = 0;

  DateTime get now => _clock();

  /// Every change, as it happens: what the OS surfaces and the result chips hear.
  Stream<JobEvent> get events => _events.stream;

  /// How many times every live job has ended, the last well: the ring blooms once each time it grows.
  int get blooms => _blooms;

  /// The job that ended last on this device, as it ended: the bloom wears its colour.
  Job? get lastEnded => _lastEnded;
  Job? _lastEnded;

  /// The jobs to show, this device's first in the order begun, then the other devices'.
  @override
  List<Job> get value => _shown ??= List.unmodifiable([
        ..._jobs.values.where((job) => (job.state.live || job.state == JobState.failed) && _shows(job)),
        for (final jobs in _elsewhere.values) ...jobs,
      ]);

  /// Whether [job] is past the while it was kept back for.
  bool _shows(Job job) => job.hiddenUntil == null || !now.isBefore(job.hiddenUntil!);

  final Map<String, Timer> _showing = {};

  /// What each live job has written so far ([JobHandle.write]), by id: '' for nothing yet, and once it ends.
  final Map<String, ValueNotifier<String>> _words = {};

  /// The words the job [id] has written so far, as they come: '' until it writes, and again once it ends.
  ValueListenable<String> wordsOf(String id) => _words.putIfAbsent(id, () => ValueNotifier<String>(''));

  void _write(String id, String sofar) {
    if (!(_jobs[id]?.state.live ?? false)) return;
    (_words[id] ??= ValueNotifier<String>('')).value = sofar;
  }

  /// Shows a job kept back once its while is up, if it is still running then.
  void _showLater(String id, Duration after) {
    _showing.remove(id)?.cancel();
    _showing[id] = Timer(after, () {
      _showing.remove(id);
      final job = _jobs[id];
      if (job == null || !job.state.live || job.hiddenUntil == null) return;
      _put(job.copyWith(hiddenUntil: () => null), JobEventKind.started);
    });
  }

  /// The live ones alone.
  List<Job> get live => [for (final job in value) if (job.state.live) job];

  /// Whether nothing is running anywhere.
  bool get idle => !value.any((job) => job.state.live);

  /// Whether something needs the person: the ring's red dot.
  bool get needsYou => value.any((job) => job.needsYou);

  /// The job [id], while it is on the record.
  Job? operator [](String id) => _jobs[id] ?? [for (final jobs in _elsewhere.values) ...jobs].where((job) => job.id == id).firstOrNull;

  /// The handle of the job [id] that is live on this device, or null.
  JobHandle? handle(String id) => (_jobs[id]?.state.live ?? false) ? JobHandle._(this, id) : null;

  /// Begins the job [id], or, where it is already live, tells it these words again and hands back its handle: a
  /// second start of the same work is the same job. A failed one begun again starts afresh.
  ///
  /// A sync's bar fills and never sweeps (Matt, 2026-10-29: "Also don't spin the progress bar on the sync just make it
  /// fill as it's being synced"): one begun with no [fraction] is at 0 until it says how far it is.
  JobHandle begin(
    String id, {
    required JobKind kind,
    required String title,
    JobState state = JobState.running,
    String? line,
    WaitingOn? waitingOn,
    double? fraction,
    String? steps,
    VoidCallback? onStop,
    VoidCallback? onOpen,
    bool personStarted = false,
    JobEstimate? estimate,
    bool Function()? shownHere,
    Duration? showAfter,
    String? plugin,
  }) {
    final had = _jobs[id];
    if (had == null || !had.state.live) _words[id]?.value = '';
    if (had != null && had.state.live) {
      _put(had.copyWith(title: title, line: line == null ? null : () => line, onStop: onStop == null ? null : () => onStop, onOpen: onOpen == null ? null : () => onOpen, estimate: estimate, personStarted: personStarted || had.personStarted, plugin: plugin == null ? null : () => plugin), JobEventKind.changed);
      return JobHandle._(this, id);
    }
    _put(
      Job(
        id: id,
        kind: kind,
        title: title,
        state: state,
        line: line,
        waitingOn: waitingOn,
        fraction: fraction ?? (kind == JobKind.sync ? 0 : null),
        steps: steps,
        onStop: onStop,
        onOpen: onOpen,
        startedAt: now,
        personStarted: personStarted,
        estimate: estimate,
        shownHere: shownHere,
        hiddenUntil: showAfter == null ? null : now.add(showAfter),
        plugin: plugin,
      ),
      JobEventKind.started,
    );
    if (showAfter != null) _showLater(id, showAfter);
    return JobHandle._(this, id);
  }

  /// Takes a failed job out of the tray.
  void dismiss(String id) {
    final job = _jobs[id];
    if (job == null || job.state.live) return;
    _jobs.remove(id);
    _changed();
  }

  /// The jobs the account's other devices are doing, as [source] knows them (the summary handoff's claims): what was
  /// said before by the same source is replaced. Shown dimmed in the ring and labelled in the tray; never logged here,
  /// since the device doing them counts them.
  void elsewhere(String source, List<Job> jobs) {
    final before = _elsewhere[source] ?? const <Job>[];
    String sign(Job j) => '${j.id}|${j.state}|${j.line}|${j.fraction}|${j.title}';
    if (listEquals(before.map(sign).toList(), jobs.map(sign).toList())) return;
    final wasLive = !idle;
    if (jobs.isEmpty) {
      _elsewhere.remove(source);
    } else {
      _elsewhere[source] = List.unmodifiable(jobs);
    }
    _changed();
    for (final job in jobs) {
      _events.add(JobEvent(before.any((b) => b.id == job.id) ? JobEventKind.changed : JobEventKind.started, job));
    }
    for (final job in before) {
      if (!jobs.any((j) => j.id == job.id)) _events.add(JobEvent(JobEventKind.ended, job.copyWith(state: JobState.done, endedAt: () => now)));
    }
    if (wasLive && idle) _bloom();
  }

  void _put(Job job, JobEventKind kind) {
    final was = _jobs[job.id];
    _jobs[job.id] = job;
    _changed();
    // A job kept back is not told of until it shows; shown by [JobHandle.show], it is told as begun.
    if (!_shows(job)) return;
    _events.add(JobEvent(kind == JobEventKind.changed && was != null && !_shows(was) ? JobEventKind.started : kind, job));
  }

  void _end(String id, JobState state, {JobResult? result, JobTally? tally, String? cause, JobFix? fix, bool quiet = false, bool stopped = false}) {
    final had = _jobs[id];
    if (had == null || !had.state.live) return;
    _showing.remove(id)?.cancel();
    _words[id]?.value = '';
    // One kept back and never shown ends unseen, unless it failed: counted, told of to nobody, and no bloom for it.
    final seen = _shows(had) || state == JobState.failed;
    final ended = had.copyWith(
      state: state,
      endedAt: () => now,
      result: () => quiet ? null : result,
      tally: () => tally,
      cause: () => cause,
      fix: () => fix,
      waitingOn: () => null,
      retryAt: () => null,
      fraction: () => state == JobState.done && !stopped ? 1.0 : had.fraction,
      hiddenUntil: () => seen ? null : had.hiddenUntil,
    );
    if (state == JobState.done) {
      _jobs.remove(id);
    } else {
      _jobs[id] = ended;
    }
    log.record(ended);
    _changed();
    if (!seen) return;
    _lastEnded = ended;
    _events.add(JobEvent(JobEventKind.ended, ended));
    if (!quiet && ended.personStarted && ended.kind != JobKind.sync && (ended.took ?? Duration.zero) >= longJob) onChime?.call(ended);
    if (idle && state == JobState.done) _bloom();
  }

  void _bloom() {
    _blooms += 1;
    _events.add(const JobEvent(JobEventKind.allDone, null));
    notifyListeners();
  }

  void _changed() {
    _shown = null;
    notifyListeners();
  }

  /// The app's own update as the tray's Update section says it, and the ring's badge while one waits (Matt, 2026-10-30:
  /// "show the updates stuff in the activity drawer only now with a badge and when an update is available show the
  /// badge"): told by the app's [Updates] (lib/core/updates.dart) at every change, null where the build has none. Not
  /// a job: an update found waits on the person, which no job does for days; its download is the `update` job.
  UpdateOffer? get update => _update;
  UpdateOffer? _update;
  set update(UpdateOffer? next) {
    if (next == _update) return;
    _update = next;
    _changed();
  }

  /// How many times the tray has been asked open at the Update section ([showUpdate]): the ring opens itself each time
  /// this grows.
  int get updateAsks => _updateAsks;
  int _updateAsks = 0;

  /// Opens the tray at its Update section: Settings › About's Check for updates, which says nothing of its own.
  void showUpdate() {
    _updateAsks += 1;
    _updateWanted = true;
    notifyListeners();
  }

  /// Whether the tray was asked open at the Update section and is not yet closed again: simple mode's plain pages,
  /// which float the ring only while it has something to say, float it for this as well, open.
  bool get updateWanted => _updateWanted;
  bool _updateWanted = false;

  /// The tray opened at the Update section is closed.
  void updateSeen() {
    if (!_updateWanted) return;
    _updateWanted = false;
    notifyListeners();
  }

  /// Everything forgotten but the log: a test's fresh record, and a sign-out's.
  void clear() {
    for (final timer in _showing.values) {
      timer.cancel();
    }
    _showing.clear();
    for (final words in _words.values) {
      words.value = '';
    }
    _jobs.clear();
    _elsewhere.clear();
    _changed();
  }

  @override
  void dispose() {
    for (final timer in _showing.values) {
      timer.cancel();
    }
    _events.close();
    super.dispose();
  }
}

/// The app's own update's download on the record (lib/core/updates.dart `Updates.updateJobId`): drawn in the tray's
/// Update section rather than among the rest.
const String appUpdateJobId = 'update';

/// Where the app's own update stands, as the tray's Update section says it ([Activity.update]). The first four are
/// said only when the section is asked for (Settings › About's Check for updates); from [available] on an update waits,
/// and the ring wears its badge.
enum UpdateStage {
  notChecked,
  checking,
  upToDate,
  checkFailed,
  available,
  downloading,
  installing,
  needsPermission,
  ready,
  restarting,
  failed;

  /// An update is out and not yet running: the ring's badge.
  bool get waiting => index >= available.index;
}

/// The update the tray's section says, with its one action: Install, Restart to update, Open (Android's installer
/// put away), Check again. Its download is the `update` job on the record, drawn in the section as a row of its own.
@immutable
class UpdateOffer {
  const UpdateOffer({required this.stage, this.version, this.running, this.notes, this.message, this.onInstall, this.onRestart, this.onCheck});

  final UpdateStage stage;

  /// The version offered ("2.3.86"), and the one running.
  final String? version, running;

  /// What's new in it, where the release says.
  final String? notes;

  /// Why it did not install, or why a check found nothing out.
  final String? message;

  /// Downloads and installs it (the phone's installer, or the Mac's new app put in place); the Mac's restart into it;
  /// another look.
  final VoidCallback? onInstall, onRestart, onCheck;

  /// Whether the ring wears its badge.
  bool get badge => stage.waiting;

  String get _v => version == null ? 'Ghost.md' : 'Ghost.md $version';

  /// The section's line: "Ghost.md 2.3.86 is ready".
  String get words => switch (stage) {
        UpdateStage.notChecked => 'Not checked for updates yet',
        UpdateStage.checking => 'Checking for updates…',
        UpdateStage.upToDate => running == null ? 'Ghost.md is up to date' : 'Ghost.md $running is up to date',
        UpdateStage.checkFailed => 'Couldn’t check for updates',
        UpdateStage.available => '$_v is ready',
        UpdateStage.downloading => 'Downloading $_v',
        UpdateStage.installing => '$_v is waiting on Android',
        UpdateStage.needsPermission => 'Let Ghost.md install apps, then come back',
        UpdateStage.ready => '$_v is downloaded',
        UpdateStage.restarting => 'Restarting into $_v',
        UpdateStage.failed => '$_v didn’t install',
      };

  /// The one action's word, or null for none (while it downloads or restarts, or a failure whose row has Retry).
  String? get action => switch (stage) {
        UpdateStage.available || UpdateStage.needsPermission => 'Install',
        UpdateStage.installing => 'Open',
        UpdateStage.ready => 'Restart to update',
        UpdateStage.failed => 'Try again',
        UpdateStage.notChecked || UpdateStage.checkFailed || UpdateStage.upToDate => 'Check again',
        UpdateStage.checking || UpdateStage.downloading || UpdateStage.restarting => null,
      };

  /// What the action does.
  VoidCallback? get onAction => switch (stage) {
        UpdateStage.ready => onRestart,
        UpdateStage.available || UpdateStage.needsPermission || UpdateStage.installing || UpdateStage.failed => onInstall,
        _ => onCheck,
      };

  @override
  bool operator ==(Object other) =>
      other is UpdateOffer && other.stage == stage && other.version == version && other.running == running && other.notes == notes && other.message == message && other.onInstall == onInstall && other.onRestart == onRestart && other.onCheck == onCheck;

  @override
  int get hashCode => Object.hash(stage, version, running, notes, message, onInstall, onRestart, onCheck);
}

/// How a job's Open and fix reach the rest of the app, told by the root as it starts (lib/root/ghost_root.dart): so
/// code deep in a plugin that runs a job need not know how a note is opened. Each is null until told, and a job then
/// has no Open.
class ActivityRoutes {
  /// Opens the note [id].
  void Function(String id)? openNote;

  /// Whether the note [id] is the one on screen.
  bool Function(String id)? showing;

  /// Opens a link in the app's own way (a provider's billing page).
  void Function(Uri link)? openLink;

  /// Opens a plugin's page in Settings (its setup, to sign in again).
  void Function(String pluginId)? openPlugin;

  /// Open for the note [id], where the app can open one.
  VoidCallback? noteOpener(String id) => openNote == null ? null : () => openNote?.call(id);

  /// Whether the note [id] is on screen, asked as a job ends.
  bool Function() noteShown(String id) => () => showing?.call(id) ?? false;

  /// Top up at [billing].
  JobFix topUp(Uri billing, {String? label}) => JobFix(JobFixKind.topUp, () => openLink?.call(billing), label: label);

  /// Sign in again at [pluginId]'s page.
  JobFix signIn(String pluginId) => JobFix(JobFixKind.signIn, () => openPlugin?.call(pluginId));
}

/// The app's routes for its jobs.
final ActivityRoutes activityRoutes = ActivityRoutes();

/// The app's record. A test puts its own in place ([useActivity]) and back.
Activity activity = Activity();

/// Makes [next] the app's record.
void useActivity(Activity next) => activity = next;

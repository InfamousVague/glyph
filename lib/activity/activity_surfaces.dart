/// The app's running work shown by the device itself (docs/ACTIVITY.md, OS surfaces; Matt, 2026-10-29: "Android
/// progress notifications (and Samsung's Now Bar where offered) for recording, write-ups, banner runs and uploads; the
/// Mac's Dock icon progress ring and badge; a Mac menu bar item with the ring and a mini tray; iPhone Live Activities
/// (Dynamic Island, lock screen) for write-ups and uploads").
///
/// It hears the record ([Activity.events], lib/core/background_jobs.dart) and tells the device over the jobs channel
/// (`ghost_md/jobs`, beside the foreground service's and App Nap's `running` / `ended`, which are as they were):
///
/// - `activity {event, job?, jobs}`: `event` is `started`, `changed`, `ended` or `allDone`; `job` is the job as it is
///   after ([surfaceJob]), and `jobs` every job this device's surface shows now, so the device can always make its
///   surface what it is told, whatever it missed. Only the jobs the surface shows are told ([SurfaceDevice]).
/// - `activityLook {calm, menuBarAlways}`: Calm (the colours as ink) and the Mac's "Always show in the menu bar"
///   (Settings › Appearance › Activity), told as the app starts and as either changes. The first word on a start, so
///   a device drops what an earlier run of the app left (a Live Activity outlives the app).
/// - Back from the device, `activityStop {id}` (its Stop: the job's own [Job.onStop]) and `activityOpen {id}` (a tap:
///   the job's [Job.onOpen], or what it made once it has ended).
///
/// Which jobs each device shows:
///
/// - **Android**: the banner run, a recording's upload with its share, and any other job the person started that has
///   run [promoteAfter] (10 s): a model's or the update's download, a read-aloud, a Slack post. Never a recording or
///   its write-up, which the meeting's own service notification says (capture/MeetingService.kt), nor sync.
/// - **The Mac**: every job the ring in the header shows, this device's and the account's other devices' (dimmed).
/// - **An iPhone**: a meeting's write-up, a summary, and a recording's upload.
///
/// A job's moves are told at most every [throttle] (a download's bytes come many times a second): its state, look or
/// title changing is told at once.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/background_jobs.dart';
import '../core/host_platform.dart';
import '../core/iphone_app.dart' show runsAsIPhoneApp;
import '../core/mac_app.dart' show runsAsMacApp;
import '../core/preferences.dart';

/// Which device's surfaces are told.
enum SurfaceDevice {
  android,
  mac,
  iphone,

  /// None: a test of the app, the web, Windows and Linux.
  none;

  /// This device's.
  static SurfaceDevice get here {
    if (kIsWeb) return none;
    if (runsAsMacApp) return mac;
    if (runsAsIPhoneApp) return iphone;
    // A test of the app says it is a phone (`defaultTargetPlatform`) on a Mac: no phone is told.
    if (defaultTargetPlatform == TargetPlatform.android && Platform.isAndroid) return android;
    return none;
  }
}

/// The ids of the jobs whose own service already says them on an Android phone: the meeting's recording and its
/// write-up (capture/MeetingService.kt, recordings/RecordingAlerts.kt).
bool saidByMeetingService(String id) => id == 'meeting-recording' || id.startsWith('write-up:');

/// Whether [job] is on [device]'s surface: see the header. [promoted] is the set of person-started jobs that have
/// run long enough for a phone's notification.
bool onSurface(SurfaceDevice device, Job job, {Set<String> promoted = const {}}) {
  if (!job.state.live && job.state != JobState.failed) return false;
  switch (device) {
    case SurfaceDevice.none:
      return false;
    case SurfaceDevice.mac:
      return true;
    case SurfaceDevice.android:
      if (!job.here || !job.state.live || saidByMeetingService(job.id) || job.kind == JobKind.sync) return false;
      return job.id == 'lovart-banners' || job.id.startsWith('share-audio:') || promoted.contains(job.id);
    case SurfaceDevice.iphone:
      if (!job.here || !job.state.live) return false;
      return job.id.startsWith('write-up:') || job.id.startsWith('summary:') || job.id.startsWith('share-audio:');
  }
}

/// Whether [job] may become a phone's notification once it has run a while: one the person started, here.
bool promotable(Job job) => job.here && job.personStarted && job.state.live && job.kind != JobKind.sync && !saidByMeetingService(job.id);

/// The kinds' colours as assets/css/app.css has them (`--activity-*`), paper and dark: a device draws them itself.
const Map<JobLook, (int, int)> surfaceColours = {
  JobLook.sync: (0xFF0A6FE0, 0xFF4EA1FF),
  JobLook.ai: (0xFF8A3DBF, 0xFFC77DFF),
  JobLook.images: (0xFFD6336C, 0xFFFF7AA8),
  JobLook.audio: (0xFF14806F, 0xFF5FE0CF),
  JobLook.meetings: (0xFFC9560B, 0xFFFF9A4D),
  JobLook.downloads: (0xFF23873F, 0xFF4CD571),
  JobLook.needsYou: (0xFFD1342B, 0xFFFF6B61),
  // The ink's quietest grey (`--app-ink-3`, oklch 0.56 and 0.6).
  JobLook.waiting: (0xFF747474, 0xFF818181),
};

/// A job as a device is told it. [calm] leaves the colours out: the device draws it in its own ink.
Map<String, Object?> surfaceJob(Job job, {bool calm = false}) {
  final colours = calm ? null : surfaceColours[job.look];
  final f = job.fraction;
  return {
    'id': job.id,
    'kind': job.kind.name,
    'look': job.look.name,
    'state': job.state.name,
    'title': job.title,
    'line': job.liveLine,
    if (f != null) 'fraction': f.clamp(0.0, 1.0),
    if (job.steps != null) 'steps': job.steps,
    if (colours != null) 'colour': colours.$1,
    if (colours != null) 'colourDark': colours.$2,
    'stoppable': job.onStop != null && job.here && job.state.live,
    'openable': job.onOpen != null || job.result?.onOpen != null,
    'here': job.here,
    if (job.deviceWords != null) 'device': job.deviceWords,
    'personStarted': job.personStarted,
    'startedAt': job.startedAt.millisecondsSinceEpoch,
    if (job.cause != null) 'cause': job.cause,
    if (job.result != null) 'result': job.result!.words,
  };
}

/// Hears [record] and tells [device] (see the header).
class ActivitySurfaces {
  ActivitySurfaces({
    Activity? record,
    MethodChannel channel = jobsChannel,
    SurfaceDevice? device,
    ValueListenable<Preferences>? prefs,
    this.promoteAfter = const Duration(seconds: 10),
    this.throttle = const Duration(milliseconds: 500),
  })  : _record = record,
        _channel = channel,
        device = device ?? SurfaceDevice.here,
        _prefs = prefs;

  final Activity? _record;
  final MethodChannel _channel;
  final ValueListenable<Preferences>? _prefs;

  /// Whose surfaces.
  final SurfaceDevice device;

  /// How long a job the person started runs before a phone shows it.
  final Duration promoteAfter;

  /// The least time between two words about one job's progress.
  final Duration throttle;

  Activity get record => _record ?? activity;
  Preferences get _now => (_prefs ?? preferences).value;

  StreamSubscription<JobEvent>? _heard;
  (bool, bool)? _look;

  /// What was told last of each job on the surface, by id.
  final Map<String, Map<String, Object?>> _told = {};

  /// A job's move held back by [throttle], and its timer.
  final Map<String, Job> _held = {};
  final Map<String, Timer> _holding = {};

  /// The person-started jobs waiting [promoteAfter], and those past it.
  final Map<String, Timer> _promoting = {};
  final Set<String> _promoted = {};

  /// The last jobs that ended, for a tap that comes after: their Open.
  final LinkedHashMap<String, Job> _endedJobs = LinkedHashMap();

  bool get _calm => _look?.$1 ?? _now.calm;

  /// Starts hearing the record and the device. Nothing on a device with no surfaces.
  void start() {
    if (device == SurfaceDevice.none || _heard != null) return;
    _heard = record.events.listen(_event);
    JobsHeard.on(_channel).surfaces = _fromDevice;
    (_prefs ?? preferences).addListener(_tellLook);
    if (device == SurfaceDevice.mac) record.addListener(_dismissed);
    _look = null;
    _tellLook();
    // What runs already (a job begun before the root): told as begun.
    for (final job in record.value) {
      if (_shows(job)) _send('started', job);
    }
  }

  void dispose() {
    _heard?.cancel();
    _heard = null;
    (_prefs ?? preferences).removeListener(_tellLook);
    record.removeListener(_dismissed);
    JobsHeard.on(_channel).surfaces = null;
    for (final timer in [..._holding.values, ..._promoting.values]) {
      timer.cancel();
    }
    _holding.clear();
    _promoting.clear();
  }

  void _tellLook() {
    final now = _now;
    final look = (now.calm, now.menuBarAlways);
    if (look == _look) return;
    final calmChanged = _look != null && _look!.$1 != look.$1;
    _look = look;
    _ask('activityLook', {'calm': look.$1, 'menuBarAlways': look.$2});
    // Calm takes the colours away (or gives them back) from what shows now.
    if (calmChanged) {
      for (final id in [..._told.keys]) {
        final job = record[id];
        if (job != null && _shows(job)) _send('changed', job);
      }
    }
  }

  /// A failed job taken out of the tray (no event says it): off the Mac's menu too.
  void _dismissed() {
    final gone = [for (final MapEntry(:key, :value) in _told.entries) if (value['state'] == JobState.failed.name && record[key] == null) key];
    if (gone.isEmpty) return;
    for (final id in gone) {
      _told.remove(id);
    }
    _ask('activity', {'event': 'changed', 'jobs': _jobs()});
  }

  bool _shows(Job job) => onSurface(device, job, promoted: _promoted);

  void _event(JobEvent event) {
    final job = event.job;
    if (event.kind == JobEventKind.allDone) {
      if (device == SurfaceDevice.mac) _ask('activity', {'event': 'allDone', 'jobs': _jobs()});
      return;
    }
    if (job == null) return;
    if (event.kind == JobEventKind.ended) {
      _jobEnded(job);
      return;
    }
    if (device == SurfaceDevice.android && !_promoted.contains(job.id) && !_promoting.containsKey(job.id) && promotable(job)) {
      _promoting[job.id] = Timer(promoteAfter, () {
        _promoting.remove(job.id);
        final now = record[job.id];
        if (now == null || !promotable(now)) return;
        _promoted.add(job.id);
        _send('started', now);
      });
    }
    if (!_shows(job)) {
      // Off the surface while still running (an elsewhere job the source no longer says): gone from it.
      if (_told.containsKey(job.id)) _send('ended', job, gone: true);
      return;
    }
    final before = _told[job.id];
    if (before == null) {
      _send('started', job);
      return;
    }
    final now = surfaceJob(job, calm: _calm);
    final moved = before['state'] != now['state'] || before['look'] != now['look'] || before['title'] != now['title'] || before['stoppable'] != now['stoppable'];
    if (moved) {
      _send('changed', job);
      return;
    }
    _held[job.id] = job;
    _holding[job.id] ??= Timer(throttle, () => _flush(job.id));
  }

  void _flush(String id) {
    _holding.remove(id);
    final job = _held.remove(id);
    if (job == null || !_told.containsKey(id)) return;
    final now = record[id];
    if (now == null || !_shows(now)) return;
    _send('changed', now);
  }

  void _jobEnded(Job job) {
    _promoting.remove(job.id)?.cancel();
    _promoted.remove(job.id);
    _holding.remove(job.id)?.cancel();
    _held.remove(job.id);
    _endedJobs[job.id] = job;
    while (_endedJobs.length > 16) {
      _endedJobs.remove(_endedJobs.keys.first);
    }
    // Only what was on the surface is told it ended; on the Mac a failed one stays, red, until dismissed.
    if (!_told.containsKey(job.id)) {
      if (device == SurfaceDevice.mac && job.state == JobState.failed) _send('started', job);
      return;
    }
    _send('ended', job, gone: !(device == SurfaceDevice.mac && job.state == JobState.failed));
  }

  void _send(String event, Job job, {bool gone = false}) {
    final told = surfaceJob(job, calm: _calm);
    _holding.remove(job.id)?.cancel();
    _held.remove(job.id);
    if (gone) {
      _told.remove(job.id);
    } else {
      _told[job.id] = told;
    }
    _ask('activity', {'event': event, 'job': told, 'jobs': _jobs()});
  }

  /// Every job the surface shows now, as last told.
  List<Map<String, Object?>> _jobs() => [..._told.values];

  Future<Object?> _fromDevice(MethodCall call) async {
    final args = call.arguments;
    final id = args is Map && args['id'] is String ? args['id'] as String : null;
    if (id == null) return null;
    switch (call.method) {
      case 'activityStop':
        final job = record[id];
        if (job != null && job.here && job.state.live) job.onStop?.call();
        return job?.onStop != null;
      case 'activityOpen':
        final job = record[id] ?? _endedJobs[id];
        final open = job?.onOpen ?? job?.result?.onOpen;
        open?.call();
        return open != null;
    }
    return null;
  }

  Future<void> _ask(String method, Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // A build from before the surfaces.
    } on PlatformException catch (failure) {
      debugPrint('[ghost] the device was not told of the activity: ${failure.message}');
    }
  }
}

/// The app's, started by the root (lib/root/ghost_root.dart).
ActivitySurfaces? activitySurfaces;

/// Starts the app's surfaces on this device, once.
void startActivitySurfaces() {
  final surfaces = activitySurfaces ??= ActivitySurfaces();
  surfaces.start();
}

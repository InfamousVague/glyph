/// Import from Notion as a job of the app's own (Matt, 2026-11-04: "Add functionality in the notion plugin to import
/// a whole notion into ghost since we should have 1 to 1 functionality"; docs/NOTION_IMPORT.md): started from the
/// plugin's page (notion_pane.dart), run here for the app's life, so it goes on when the page is closed.
///
/// - **On the record** (lib/core/background_jobs.dart): `notion-import` in the ring and the tray, "142 of 380 pages"
///   with the page it is on, Stop, and its chip as it ends. On a phone the device is told too (Android's foreground
///   service with Stop on its notification), so the import goes on with the screen off.
/// - **Over the plugin's sign-in**: every call is [notionAnswer] (the device's token, refreshed once on a 401), paced
///   and paged by the importer's [NotionReader]; every file is [notionDownload], through the plugin's host.
/// - **Where it went** is kept in the plugin's storage (`glyph-notion-import`): the workspace, its name and when, so
///   the next run is "Sync again" into the same place. Which note came from which page is in the notes themselves
///   (`notion-id:`), so a run after a reinstall or on another device still updates rather than duplicates.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/background_jobs.dart';
import '../../core/workspaces.dart' show Workspace, WorkspaceStore;
import '../../importer/import_report.dart';
import '../../importer/import_target.dart';
import '../../importer/notion/notion_import.dart';
import '../../importer/notion/notion_source.dart';
import '../details_cache.dart' show failureWords;
import 'client.dart';
import 'manifest.dart';

/// The job's id on the app's record.
const String notionImportJobId = 'notion-import';

const String _importKey = 'glyph-notion-import';

/// Where the last import went: its workspace and when it ran; and Keep in sync's own (Matt, 2026-11-04: "we need a
/// way to sync changes and update in real time"): whether it is on, the newest `last_edited_time` seen (the mark the
/// next check reads down to), when Notion was last checked, and what went wrong last, in words.
@immutable
class NotionImportPlace {
  const NotionImportPlace({required this.workspaceId, required this.name, required this.at, this.mark, this.live = true, this.checked, this.error, this.both = 0});
  final String workspaceId;
  final String name;

  /// Milliseconds since the epoch.
  final int at;

  /// Notion's `last_edited_time` of the newest page read; null before Keep in sync, when the import's time stands in.
  final String? mark;

  /// Keep in sync: on once an import has run, until switched off.
  final bool live;

  /// When Notion was last checked, in milliseconds; and what that check could not do, or null.
  final int? checked;
  final String? error;

  /// How many pages the last sync found changed in both, Ghost.md's kept.
  final int both;

  /// The mark a check reads down to: [mark], else the import's own time as Notion writes one.
  String get since => mark ?? DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).toIso8601String();

  static NotionImportPlace? fromJson(Object? raw) {
    if (raw is! Map || raw['workspace'] is! String || raw['name'] is! String || raw['at'] is! num) return null;
    return NotionImportPlace(
      workspaceId: raw['workspace'] as String,
      name: raw['name'] as String,
      at: (raw['at'] as num).toInt(),
      mark: raw['mark'] is String ? raw['mark'] as String : null,
      live: raw['live'] != false,
      checked: raw['checked'] is num ? (raw['checked'] as num).toInt() : null,
      error: raw['error'] is String ? raw['error'] as String : null,
      both: raw['both'] is num ? (raw['both'] as num).toInt() : 0,
    );
  }

  NotionImportPlace copyWith({String? mark, bool? live, int? checked, String? Function()? error, int? both}) => NotionImportPlace(
        workspaceId: workspaceId,
        name: name,
        at: at,
        mark: mark ?? this.mark,
        live: live ?? this.live,
        checked: checked ?? this.checked,
        error: error == null ? this.error : error(),
        both: both ?? this.both,
      );

  Map<String, Object?> toJson() => {'workspace': workspaceId, 'name': name, 'at': at, 'mark': ?mark, 'live': live, 'checked': ?checked, 'error': ?error, if (both > 0) 'both': both};
}

/// How often Keep in sync checks Notion while the app is open.
const Duration notionSyncEvery = Duration(minutes: 2);

/// How many pages a sync changes before it shows in the tray: fewer are quiet.
const int notionSyncQuietMost = 5;

/// Where an import is.
sealed class NotionImportState {
  const NotionImportState();
}

class NotionImportIdle extends NotionImportState {
  const NotionImportIdle();
}

/// Under way: [total] is 0 while Notion is still being read for what there is.
class NotionImportRunning extends NotionImportState {
  const NotionImportRunning({this.done = 0, this.total = 0, this.on});
  final int done;
  final int total;
  final String? on;
}

class NotionImportDone extends NotionImportState {
  const NotionImportDone(this.report, {this.stopped = false});
  final ImportReport report;
  final bool stopped;
}

class NotionImportFailed extends NotionImportState {
  const NotionImportFailed(this.why);
  final String why;
}

/// The one import, for the app's life ([notionImport]); a test makes its own over a fake Notion.
class NotionImportJob extends ValueNotifier<NotionImportState> {
  NotionImportJob({NotionCall? call, NotionDownload? download, BackgroundJobs? background, this.gap = notionGap, Future<void> Function(Duration wait)? sleep})
      : _call = call ?? ((method, path, [body]) => notionAnswer(method, path, body)),
        _download = download ?? notionDownload,
        _background = background,
        _sleep = sleep,
        super(const NotionImportIdle());

  final NotionCall _call;
  final NotionDownload _download;
  final Duration gap;
  final Future<void> Function(Duration wait)? _sleep;
  BackgroundJobs? _background;
  bool _stop = false;

  /// The device's half, made the first time an import runs (a test hands its own).
  BackgroundJobs get _device {
    final made = _background ??= ChannelBackgroundJobs();
    return made;
  }

  NotionReader _reader() => NotionReader(_call, download: _download, gap: gap, sleep: _sleep);

  bool get running => value is NotionImportRunning;

  /// Where the last import went, or null before the first.
  NotionImportPlace? get last => NotionImportPlace.fromJson(host.storage.get<Object?>(_importKey, null));

  /// The workspace [last] names, while it is still there.
  Workspace? lastIn(WorkspaceStore workspaces) {
    final place = last;
    if (place == null) return null;
    for (final w in workspaces.value.list) {
      if (w.id == place.workspaceId) return w;
    }
    return null;
  }

  void _keep(NotionImportPlace place) {
    host.storage.set(_importKey, place.toJson());
    notifyListeners();
  }

  /// A sync under way (Keep in sync's, or Sync now's quick one).
  bool get syncing => _syncing;
  bool _syncing = false;

  /// What the last sync brought, for the page: null before one changed anything.
  ImportReport? get lastSync => _lastSync;
  ImportReport? _lastSync;

  /// Keep in sync on or off.
  void setLive(bool on) {
    final place = last;
    if (place == null) return;
    _keep(place.copyWith(live: on));
    if (on) unawaited(sync());
  }

  /// Checks Notion for what changed since the last mark and brings it in place, quietly: one search where nothing
  /// changed, a chip in the tray only where more than [notionSyncQuietMost] pages did. Never while an import runs,
  /// never two at once. Into the workspace the import went into; where it is gone, Keep in sync says so and stops.
  Future<void> sync({ImportTarget? target, WorkspaceStore? workspaces}) async {
    final to = target ?? _target?.call();
    final among = workspaces ?? _workspaces;
    final place = last;
    if (running || _syncing || to == null || among == null || place == null) return;
    final into = lastIn(among);
    if (into == null) {
      _keep(place.copyWith(live: false, checked: _now(), error: () => 'The workspace ${place.name} is gone, so Keep in sync is off. Import again to bring Notion in.'));
      return;
    }
    _syncing = true;
    notifyListeners();
    var mark = place.since;
    JobHandle? job;
    try {
      final report = await syncNotion(_reader(), to, into: into, mark: mark, newest: (newest) => mark = newest, progress: (p) {
        if (job == null && p.total > notionSyncQuietMost) {
          job = activity.begin(notionImportJobId, kind: JobKind.downloads, title: 'Syncing from Notion', line: 'Reading what changed', plugin: manifest.id);
        }
        if (p.total > 0) job?.progress(done: p.done, total: p.total, steps: '${p.done} of ${p.total} pages', line: p.on);
      });
      if (report != null) _lastSync = report;
      job?.done(result: report == null ? null : JobResult(importDoneSaid(report), action: 'Open'), tally: JobTally('page synced', 'pages synced', report == null ? 0 : report.notes + report.notebooks + report.updated));
      _keep((last ?? place).copyWith(mark: mark, checked: _now(), error: () => null, both: report?.conflicts ?? 0));
    } catch (failure) {
      final why = failureWords(failure);
      job?.failed(why);
      _keep((last ?? place).copyWith(checked: _now(), error: () => why));
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  int _now() => notionNow();

  ImportTarget Function()? _target;
  WorkspaceStore? _workspaces;
  Timer? _timer;
  _Resumed? _resumed;

  /// Keep in sync, for the app's life (the root hands where imports write): a check now, every [notionSyncEvery]
  /// while the app is open, and as it comes back to the front, each while the switch is on and Notion signed in.
  void keepInSync({required ImportTarget Function() target, required WorkspaceStore workspaces, Duration every = notionSyncEvery}) {
    _target = target;
    _workspaces = workspaces;
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => _tick());
    if (_resumed == null) {
      _resumed = _Resumed(_tick);
      WidgetsBinding.instance.addObserver(_resumed!);
    }
    _tick();
  }

  /// Stops [keepInSync]'s checks.
  void stopKeeping() {
    _timer?.cancel();
    _timer = null;
    final resumed = _resumed;
    if (resumed != null) WidgetsBinding.instance.removeObserver(resumed);
    _resumed = null;
    _target = null;
    _workspaces = null;
  }

  void _tick() {
    final place = last;
    if (place == null || !place.live || !notionAccountNow().connected) return;
    unawaited(sync());
  }

  /// How much Notion shows the sign-in.
  Future<NotionShared> look() => notionShared(_reader());

  /// Stops after the page it is on; what came in stays.
  void stop() => _stop = true;

  /// Begins the import through [target]: into [into], or a new workspace called Notion. Answers when it ends; its
  /// state says how it went.
  Future<void> start(ImportTarget target, {Workspace? into}) async {
    if (running) return;
    _stop = false;
    value = const NotionImportRunning();
    final again = into != null && into.id == last?.workspaceId;
    final title = again ? 'Syncing from Notion' : 'Importing from Notion';
    final job = activity.begin(notionImportJobId, kind: JobKind.downloads, title: title, line: 'Reading what Notion shares', personStarted: true, onStop: stop, plugin: manifest.id);
    _device.onStop((id) {
      if (id == notionImportJobId) stop();
    });
    unawaited(_device.running(notionImportJobId, title: title, text: 'Reading what Notion shares'));
    try {
      String? newest;
      final report = await importNotion(_reader(), target, into: into, stopped: () => _stop, newest: (mark) => newest = mark, progress: (p) {
        value = NotionImportRunning(done: p.done, total: p.total, on: p.on);
        if (p.total > 0) {
          job.progress(done: p.done, total: p.total, steps: '${p.done} of ${p.total} pages', line: p.on);
          unawaited(_device.running(notionImportJobId, title: title, text: '${p.done} of ${p.total} pages', done: p.done, total: p.total));
        }
      });
      final id = report.groupId;
      final before = last;
      if (id != null) {
        // Keep in sync stays as it was set for the same place, and is on for a new one.
        final same = before != null && before.workspaceId == id;
        _keep(NotionImportPlace(workspaceId: id, name: report.groupName ?? notionWorkspaceName, at: _now(), mark: newest ?? before?.mark, live: same ? before.live : true, checked: _now()));
      }
      value = NotionImportDone(report, stopped: _stop);
      final made = report.notes + report.notebooks + report.updated;
      if (_stop) {
        job.stopped(tally: JobTally('page imported', 'pages imported', made));
      } else {
        job.done(result: JobResult(importDoneSaid(report), action: 'Open'), tally: JobTally('page imported', 'pages imported', made));
      }
      unawaited(_device.ended(notionImportJobId, title: _stop ? 'Notion import stopped' : 'Notion import done', text: importDoneSaid(report)));
    } catch (failure) {
      final why = failureWords(failure);
      value = NotionImportFailed(why);
      final signedOut = failure is NotionImportFailure && failure.status == 401;
      job.failed(why, fix: signedOut ? activityRoutes.signIn(manifest.id) : null);
      unawaited(_device.ended(notionImportJobId, title: 'Notion import stopped', text: why));
    } finally {
      _device.onStop(null);
    }
  }

  /// Back to the start: what the page shows after its result is read.
  void clear() {
    if (!running) value = const NotionImportIdle();
  }
}

/// Hears the app come back to the front.
class _Resumed with WidgetsBindingObserver {
  _Resumed(this._heard);
  final VoidCallback _heard;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _heard();
  }
}

/// The app's one Notion import.
final NotionImportJob notionImport = NotionImportJob();

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

import '../../core/metrics.dart' show trackPlugin;
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/background_jobs.dart';
import '../../account/ui_state.dart' show accountFailureText;
import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/library.dart' show NoteLibrary;
import '../../core/note_folders.dart' show folderFor;
import '../../core/workspaces.dart' show Workspace, WorkspaceStore, isOrgWorkspace, workspaceFamily;
import '../../orgs/types.dart' show Org;
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
  const NotionImportPlace({required this.workspaceId, required this.name, required this.at, this.mark, this.live = true, this.checked, this.error, this.both = 0, this.made = false});
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

  /// Whether the import made the workspace itself (a new workspace, or a new organization's), so taking the import
  /// away may take an empty workspace with it. A place kept before this was said reads as made where its name is the
  /// import's own (`Notion`, `Notion 2`) and it is not an organization's.
  final bool made;

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
      made: raw['made'] == true,
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
        made: made,
      );

  Map<String, Object?> toJson() => {'workspace': workspaceId, 'name': name, 'at': at, 'mark': ?mark, 'live': live, 'checked': ?checked, 'error': ?error, if (both > 0) 'both': both, if (made) 'made': true};
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
      // The anonymous usage stats (lib/core/metrics.dart): a sync pass and how many pages it changed, as a bucket.
      // A pass that changed nothing (most of them, every two minutes) is not counted.
      final changed = report == null ? 0 : report.notes + report.notebooks + report.updated;
      if (changed > 0) trackPlugin('notion', 'sync_run', count: changed, ok: true);
      job?.done(result: report == null ? null : JobResult(importDoneSaid(report), action: 'Open'), tally: JobTally('page synced', 'pages synced', report == null ? 0 : report.notes + report.notebooks + report.updated));
      _keep((last ?? place).copyWith(mark: mark, checked: _now(), error: () => null, both: report?.conflicts ?? 0));
    } catch (failure) {
      final why = failureWords(failure);
      trackPlugin('notion', 'sync_run', ok: false);
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

  /// What Notion calls the workspace signed in to: the sign-in's own name for it, else the integration's
  /// (`GET users/me`, its `bot.workspace_name`), else "Notion".
  Future<String> notionWorkspaceTitle() async {
    try {
      final said = (await notionAccount()).workspaceName?.trim();
      if (said != null && said.isNotEmpty) return said;
    } catch (_) {
      // No sign-in to read: asked of Notion instead.
    }
    try {
      final me = await _reader().ask('GET', 'users/me');
      final bot = me is Map ? me['bot'] : null;
      final name = bot is Map ? '${bot['workspace_name'] ?? ''}'.trim() : '';
      if (name.isNotEmpty) return name;
    } catch (_) {
      // Notion did not say: the plain name.
    }
    return notionWorkspaceName;
  }

  /// Import into a new organization (Matt, 2026-11-04: "I want the import to start a new org"): named for the Notion
  /// workspace, made by [makeOrg] (the app's own `Orgs.createOrg`, so its key, owner and workspace are made as any
  /// new organization's are), then imported into its workspace, which Sync now and Keep in sync go to after. Not
  /// signed in to Ghost.md ([makeOrg] null), or the organization refused: said in words, and nothing imported.
  Future<void> startInNewOrg(ImportTarget target, {required Future<Org> Function(String name)? makeOrg, required WorkspaceStore workspaces}) async {
    if (running || _syncing) return;
    if (makeOrg == null) {
      value = const NotionImportFailed('A new organization needs your Ghost.md account. Sign in under Settings › Account, or pick a workspace under Where it goes.');
      return;
    }
    value = const NotionImportRunning();
    final name = await notionWorkspaceTitle();
    final Org org;
    try {
      org = await makeOrg(name);
    } catch (failure) {
      value = NotionImportFailed('Ghost.md couldn’t make the organization “$name”: ${accountFailureText(failure)} Nothing was imported.');
      return;
    }
    final into = workspaces.ensureOrgWorkspace(org);
    value = const NotionImportIdle();
    await start(target, into: into, madeHere: true);
  }

  /// Takes away what the last import brought (Matt, 2026-11-04: "also delete the notes from my most recent notion
  /// import"): every note in its workspace (and the folders in it) whose front matter says `notion-id:`, into the
  /// trash the app's own Delete uses, so each can be put back; never deleted for good. Notes without `notion-id:`, the
  /// person's own, stay. Then the folders it emptied go, the workspace too where the import made it and nothing is
  /// left in it (never an organization's), and Keep in sync is off. Answers how many notes went to the trash.
  Future<int> removeImported({required NoteLibrary library, required WorkspaceStore workspaces}) async {
    if (running || _syncing) throw StateError('Wait for the import to finish first.');
    final place = last;
    if (place == null) throw StateError('Nothing has been imported from Notion on this device.');
    final trash = workspaces.trash;
    if (trash == null) throw StateError('The trash isn’t ready, so nothing was moved.');
    final ws = lastIn(workspaces);
    var moved = 0;
    if (ws != null) {
      final list = workspaces.value.list;
      final family = workspaceFamily(list, ws.id);
      final filed = workspaces.value.of;
      final root = folderFor(ws, list);
      final emptied = <String>{};
      final now = _now();
      for (final note in library.value) {
        if (note.inTrash || trash.isTrashed(note.id)) continue;
        if (notionIdOf(frontMatterValue(note.body, 'notion-id')) == null) continue;
        final here = filed[note.id];
        final inside = (here != null && family.contains(here)) || (root != null && (note.path ?? '').startsWith('$root/'));
        if (!inside) continue;
        trash.trashNote(note.id, now);
        if (here != null) emptied.add(here);
        moved += 1;
      }
      // The folders it emptied, the deepest first: each with nothing left in it and no folder left inside it.
      bool bare(String id) => workspaces.notesInWorkspace(id).isEmpty && !workspaces.value.list.any((w) => w.parent == id);
      for (final id in family.reversed) {
        if (id == ws.id || !emptied.contains(id) && !workspaceFamily(list, id).any(emptied.contains)) continue;
        if (bare(id) && !isOrgWorkspace(id)) workspaces.removeWorkspace(id);
      }
      final ours = place.made || RegExp(r'^Notion( \d+)?$').hasMatch(ws.name);
      if (ours && !isOrgWorkspace(ws.id) && bare(ws.id)) workspaces.removeWorkspace(ws.id);
    }
    _keep(place.copyWith(live: false, error: () => null));
    trackPlugin('notion', 'import_removed', count: moved);
    _lastSync = null;
    if (value is! NotionImportRunning) value = const NotionImportIdle();
    return moved;
  }

  /// How much Notion shows the sign-in.
  Future<NotionShared> look() => notionShared(_reader());

  /// Stops after the page it is on; what came in stays.
  void stop() => _stop = true;

  /// Begins the import through [target]: into [into], or a new workspace called Notion. Answers when it ends; its
  /// state says how it went.
  Future<void> start(ImportTarget target, {Workspace? into, bool madeHere = false}) async {
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
    trackPlugin('notion', 'import_started', choice: again ? 'again' : 'new');
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
        _keep(NotionImportPlace(workspaceId: id, name: report.groupName ?? notionWorkspaceName, at: _now(), mark: newest ?? before?.mark, live: same ? before.live : true, checked: _now(), made: report.madeGroup || madeHere || (same && before.made)));
      }
      value = NotionImportDone(report, stopped: _stop);
      final made = report.notes + report.notebooks + report.updated;
      trackPlugin('notion', _stop ? 'import_stopped' : 'import_finished', count: made, ok: true);
      if (_stop) {
        job.stopped(tally: JobTally('page imported', 'pages imported', made));
      } else {
        job.done(result: JobResult(importDoneSaid(report), action: 'Open'), tally: JobTally('page imported', 'pages imported', made));
      }
      unawaited(_device.ended(notionImportJobId, title: _stop ? 'Notion import stopped' : 'Notion import done', text: importDoneSaid(report)));
    } catch (failure) {
      final why = failureWords(failure);
      value = NotionImportFailed(why);
      trackPlugin('notion', 'import_failed', ok: false);
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

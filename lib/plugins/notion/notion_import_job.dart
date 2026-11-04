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

import 'package:flutter/foundation.dart';

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

/// Where the last import went: its workspace and when it ran.
@immutable
class NotionImportPlace {
  const NotionImportPlace({required this.workspaceId, required this.name, required this.at});
  final String workspaceId;
  final String name;

  /// Milliseconds since the epoch.
  final int at;

  static NotionImportPlace? fromJson(Object? raw) {
    if (raw is! Map || raw['workspace'] is! String || raw['name'] is! String || raw['at'] is! num) return null;
    return NotionImportPlace(workspaceId: raw['workspace'] as String, name: raw['name'] as String, at: (raw['at'] as num).toInt());
  }

  Map<String, Object?> toJson() => {'workspace': workspaceId, 'name': name, 'at': at};
}

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
      final report = await importNotion(_reader(), target, into: into, stopped: () => _stop, progress: (p) {
        value = NotionImportRunning(done: p.done, total: p.total, on: p.on);
        if (p.total > 0) {
          job.progress(done: p.done, total: p.total, steps: '${p.done} of ${p.total} pages', line: p.on);
          unawaited(_device.running(notionImportJobId, title: title, text: '${p.done} of ${p.total} pages', done: p.done, total: p.total));
        }
      });
      final id = report.groupId;
      if (id != null) host.storage.set(_importKey, NotionImportPlace(workspaceId: id, name: report.groupName ?? notionWorkspaceName, at: DateTime.now().millisecondsSinceEpoch).toJson());
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

/// The app's one Notion import.
final NotionImportJob notionImport = NotionImportJob();

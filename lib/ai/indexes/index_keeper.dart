/// The keeper of every index this device writes (docs/AI_INDEXES.md §3, §5). Matt, 2026-11-02: "for any folder or
/// org, the AI keeps an index note (what's here, the key decisions, who owns what) and updates it as notes change.
/// New teammates read one page instead of fifty."
///
/// It finds the indexes in the notes themselves: a folder's page whose front matter says `index: on` (so an index a
/// teammate turned on is seen here as it syncs). It hears the library (the notes-changed signal), and a few seconds
/// after a change, and once a minute, refreshes each index that is dirty ([indexDirty]), due by its `index-every`, and
/// **this device's to write** (`index-by:`, the one-writer rule of §5): another device's index is only read here,
/// until the person presses Take over. Never two refreshes at once. A failed refresh waits its gap (at least 15
/// minutes) before it is tried again on its own.
///
/// Each refresh is a job on the app's record of running work (lib/core/background_jobs.dart, kind `ai`), with Stop;
/// a person's own Refresh or Rebuild is one they started (its end chimes), an automatic one is quiet.
///
/// The write goes through [IndexKeeper.write], which the root makes its `_changeNote` (an open page's editor takes
/// it as an edit), and changes only the section: the page is read again at the write, the section put in it, and
/// the person's words as they are then are kept. The settings are written the same way.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/background_jobs.dart';
import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/note.dart';
import 'index_ai.dart';
import 'index_build.dart';
import 'index_scope.dart';
import 'index_section.dart';

/// What an index's card draws.
@immutable
class IndexStatus {
  const IndexStatus({
    this.on = false,
    this.pageId,
    this.every = IndexEvery.hourly,
    this.mine = true,
    this.byName,
    this.updated,
    this.by,
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.error,
    this.dirty = false,
    this.why,
    this.count = 0,
  });

  final bool on;

  /// The folder's page, where it has one.
  final String? pageId;
  final IndexEvery every;

  /// Whether this device writes it (§5); false, [byName]'s does.
  final bool mine;
  final String? byName;

  /// When it was last brought up to date, and by which AI.
  final DateTime? updated;
  final String? by;

  final bool running;
  final int done, total;

  /// How the last refresh here failed, in words.
  final String? error;

  /// Whether a note changed after it was written.
  final bool dirty;

  /// Why no AI can write it here; null where one can.
  final String? why;

  /// How many notes it covers.
  final int count;
}

/// The keeper (see the header).
class IndexKeeper extends ChangeNotifier {
  IndexKeeper({
    required this.notes,
    required this.get,
    required this.write,
    required this.makePage,
    required this.pick,
    required this.deviceId,
    required this.deviceName,
    DateTime Function()? clock,
    Activity? record,
    this.settle = const Duration(seconds: 5),
    this.every = const Duration(minutes: 1),
  })  : _clock = clock ?? DateTime.now,
        _record = record;

  /// The library's notes, heard for changes.
  final ValueListenable<List<Note>> notes;

  /// A note read whole.
  final Future<Note?> Function(String id) get;

  /// Changes a note's words through [change], given them as they are then.
  final Future<void> Function(String id, String Function(String body) change) write;

  /// Makes a page for [folder] (titled [title]) where it has none, and answers it; null where it could not.
  final Future<Note?> Function(String folder, String title) makePage;

  /// Who writes an index now ([pickIndexAi]).
  final IndexAiPick Function() pick;

  /// This device (lib/ai/summary_handoff.dart `thisDevice`).
  final String deviceId, deviceName;

  final DateTime Function() _clock;
  final Activity? _record;
  Activity get _activity => _record ?? activity;

  /// How long after a change the keeper looks, and how often it looks anyway.
  final Duration settle, every;

  Timer? _soon, _beat;
  bool _started = false;
  final Map<String, _Run> _runs = {};
  final Map<String, String> _errors = {};
  final Map<String, DateTime> _failedAt = {};

  /// Starts hearing the notes, and looking once a [every].
  void start() {
    if (_started) return;
    _started = true;
    notes.addListener(_heard);
    _beat = Timer.periodic(every, (_) => unawaited(tick()));
    _heard();
  }

  void _heard() {
    _soon?.cancel();
    _soon = Timer(settle, () => unawaited(tick()));
    notifyListeners();
  }

  @override
  void dispose() {
    if (_started) notes.removeListener(_heard);
    _soon?.cancel();
    _beat?.cancel();
    for (final run in _runs.values) {
      run.stop();
    }
    super.dispose();
  }

  // ---- reading -------------------------------------------------------------------------------------------------------

  /// The page of [folder] among [all]: its `index.md`; at an organization's top its `Home.md` or a note saying
  /// `type: teamspace`; else the note named as the folder is (lib/core/page_tree.dart, "A folder's page").
  static Note? pageOf(String folder, Iterable<Note> all) {
    final inIt = [
      for (final note in all)
        if (note.path != null && !note.inTrash && folderOf(note.path!) == folder) note,
    ];
    Note? named(String file) => inIt.where((n) => n.path!.substring(n.path!.lastIndexOf('/') + 1).toLowerCase() == file).firstOrNull;
    final parts = folder.split('/');
    final orgTop = parts.length == 2 && parts.first == 'orgs';
    return named('index.md') ??
        (orgTop ? (named('home.md') ?? inIt.where((n) => frontMatterValue(n.body, 'type')?.trim().toLowerCase() == 'teamspace').firstOrNull) : null) ??
        named('${parts.last.toLowerCase()}.md');
  }

  /// Every folder with an index on, by its page.
  Map<String, Note> get indexed => {
        for (final note in notes.value)
          if (note.path != null && !note.inTrash && note.body.startsWith('---') && note.body.contains('index:') && IndexSettings.of(note.body).on) folderOf(note.path!): note,
      };

  /// What [folder]'s card draws.
  IndexStatus status(String folder) {
    final page = pageOf(folder, notes.value);
    final settings = IndexSettings.of(page?.body);
    final run = _runs[folder];
    final span = page == null ? null : readSection(page.body).span;
    final covered = page == null ? const <Note>[] : notesIn(folder, notes.value, pageId: page.id);
    return IndexStatus(
      on: settings.on,
      pageId: page?.id,
      every: settings.every,
      mine: settings.by == null || settings.by == deviceId,
      byName: settings.byName,
      updated: span?.updated,
      by: span?.by,
      running: run != null,
      done: run?.done ?? 0,
      total: run?.total ?? 0,
      error: _errors[folder],
      dirty: settings.on && page != null && indexDirty(page.body, covered),
      why: pick().why,
      count: covered.length,
    );
  }

  /// What a refresh of [folder] would read and take, for the question before a big one; null with no AI or page.
  JobEstimate? estimate(String folder, {bool full = false}) {
    final ai = pick().ai;
    final page = pageOf(folder, notes.value);
    if (ai == null) return null;
    final covered = notesIn(folder, notes.value, pageId: page?.id);
    return indexEstimate(page == null ? covered : notesToRead(page.body, covered, full: full), ai);
  }

  // ---- the settings --------------------------------------------------------------------------------------------------

  Future<Note?> _page(String folder, String title) async => pageOf(folder, notes.value) ?? await makePage(folder, title);

  Future<void> _settings(String folder, String title, IndexSettings Function(IndexSettings now) change) async {
    final page = await _page(folder, title);
    if (page == null) throw const IndexRefused('The folder’s page could not be made.');
    await write(page.id, (body) => change(IndexSettings.of(body)).writeInto(body));
    notifyListeners();
  }

  /// Turns [folder]'s index on, this device its writer; the folder's page made where it has none. The first build is
  /// the caller's to start ([refresh]), once any question of its cost is answered.
  Future<void> turnOn(String folder, {required String title, IndexEvery? every}) =>
      _settings(folder, title, (now) => now.copyWith(on: true, every: every ?? now.every, by: deviceId, byName: deviceName));

  /// Turns it off: no more refreshes; the section the page has stays as it is, the person's to keep or delete.
  Future<void> turnOff(String folder, {required String title}) async {
    _runs[folder]?.stop();
    await _settings(folder, title, (now) => const IndexSettings());
  }

  /// How often it is refreshed.
  Future<void> setEvery(String folder, IndexEvery every, {required String title}) => _settings(folder, title, (now) => now.copyWith(every: every));

  /// Makes this device its writer (§5).
  Future<void> takeOver(String folder, {required String title}) => _settings(folder, title, (now) => now.copyWith(by: deviceId, byName: deviceName));

  // ---- refreshing ----------------------------------------------------------------------------------------------------

  /// Stops [folder]'s refresh, if one runs.
  void stop(String folder) => _runs[folder]?.stop();

  /// Whether [folder]'s index, written at [updated] and refreshed [each], may be refreshed now.
  bool due(DateTime? updated, IndexEvery each, DateTime now) {
    if (updated == null) return true;
    if (each == IndexEvery.nightly) {
      final local = updated.toLocal();
      final today = DateTime(now.year, now.month, now.day);
      return now.hour >= 3 && local.isBefore(today.add(const Duration(hours: 3)));
    }
    return now.difference(updated) >= each.gap;
  }

  /// Refreshes every index that is this device's, dirty and due; once at a time.
  Future<void> tick() async {
    if (_runs.isNotEmpty) return;
    final now = _clock();
    for (final MapEntry(key: folder, value: page) in indexed.entries) {
      final settings = IndexSettings.of(page.body);
      if (settings.by != null && settings.by != deviceId) continue;
      final failed = _failedAt[folder];
      if (failed != null && now.difference(failed) < (settings.every.gap < const Duration(minutes: 15) ? const Duration(minutes: 15) : settings.every.gap)) continue;
      final span = readSection(page.body).span;
      if (span != null && !due(span.updated, settings.every, now)) continue;
      if (!indexDirty(page.body, notesIn(folder, notes.value, pageId: page.id))) continue;
      if (pick().ai == null) return;
      await refresh(folder, title: titleOf(page));
      return;
    }
  }

  /// Refreshes [folder]'s index now: incrementally, or every note again for [full]. [person] for the person's own
  /// press. Answers why it did not, or null once written (or stopped).
  Future<String?> refresh(String folder, {required String title, bool full = false, bool person = false}) async {
    if (_runs.containsKey(folder)) return 'The index is being updated.';
    final chosen = pick();
    final ai = chosen.ai;
    if (ai == null) return chosen.why;
    final run = _runs[folder] = _Run(ai);
    _errors.remove(folder);
    notifyListeners();
    final started = _clock();
    final job = _activity.begin('index:$folder', kind: JobKind.ai, title: 'Updating the index of $title', line: ai.name, onStop: run.stop, personStarted: person);
    try {
      final listed = pageOf(folder, notes.value);
      final page = listed == null ? null : await get(listed.id);
      if (page == null) throw const IndexRefused('The folder has no page for its index.');
      final settings = IndexSettings.of(page.body);
      if (!settings.on) throw const IndexRefused('The index is off.');
      if (settings.by != null && settings.by != deviceId) throw IndexRefused('The index is kept by ${settings.byName ?? 'another device'}. Take over to update it here.');
      final built = await buildIndex(
        folderTitle: title,
        pageBody: page.body,
        notes: notesIn(folder, notes.value, pageId: page.id),
        ai: ai,
        now: started,
        full: full,
        stopped: () => run.stopped,
        onProgress: (done, total) {
          run
            ..done = done
            ..total = total;
          job.progress(done: done, total: total, unit: 'parts');
          notifyListeners();
        },
      );
      lastRead = built.read;
      final section = readSection(built.body).span!;
      final words = built.body.substring(section.start, section.end);
      var refused = false;
      await write(page.id, (body) {
        // Read again at the write: another device may have taken it over meanwhile, and the person may have typed.
        final now = IndexSettings.of(body);
        if (!now.on || (now.by != null && now.by != deviceId)) {
          refused = true;
          return body;
        }
        return withSection(body, words) ?? body;
      });
      if (refused) throw const IndexRefused('The index was turned off or taken over while it was being updated.');
      _failedAt.remove(folder);
      job.done(result: const JobResult('Index updated', action: 'Open'), quiet: !person);
      return null;
    } on IndexStopped {
      job.stopped();
      return null;
    } catch (failure) {
      if (run.stopped) {
        job.stopped();
        return null;
      }
      final words = failure is IndexRefused ? failure.message : 'The index was not updated: $failure';
      _errors[folder] = words;
      _failedAt[folder] = _clock();
      job.failed(words);
      return words;
    } finally {
      _runs.remove(folder);
      notifyListeners();
    }
  }

  /// The ids of the notes the last refresh read again: what a test asks of the incremental rule.
  @visibleForTesting
  List<String> lastRead = const [];
}

class _Run {
  _Run(this.ai);

  final IndexAi ai;
  int done = 0, total = 0;
  bool stopped = false;

  void stop() {
    stopped = true;
    ai.cancel();
  }
}

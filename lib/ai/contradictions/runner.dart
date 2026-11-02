/// The contradiction finder's run, in the background (docs/CONTRADICTIONS.md, "How it runs"; Matt, 2026-11-02:
/// "Contradiction finder: spots when a newer note disagrees with an older one … and flags the stale one inline").
///
/// A [ContradictionRunner] holds the findings of every scope (one [FindingsBook] a file, findings.dart), the person's
/// settings ([ContradictionSettings], the device's own), and the run: the candidate pairs (candidates.dart), asked six to
/// a request of whichever AI is connected (ai.dart), every answer read strictly (compare.dart), and what was found kept in
/// the files as each request ends, so a Stop or a closed app loses nothing found.
///
/// **Never two scopes in one prompt**: the pairs are grouped by their scope (personal notes, or one organization's)
/// before they are cut into requests, and an organization's notes are only read at all with Organization notes on.
///
/// **On its own** only once the person has run it by hand ([ContradictionSettings.ranOnce]), which is where a big run's
/// cost is asked (lib/plugins/contradictions/contradictions_pane.dart). Then: When a note is saved, two minutes after
/// the last save, the pairs with the saved notes in them ([noteSaved]); Nightly, once a day after three in the morning
/// or at the first open after that ([tick]).
///
/// **In the activity tray** as the job `contradictions` (lib/core/background_jobs.dart): "Checking for contradictions",
/// how many pairs of how many, Stop; and at its end how many notes may be out of date, with View.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/background_jobs.dart';
import '../../core/note.dart' show Note;
import '../../core/stored.dart';
import 'ai.dart';
import 'candidates.dart';
import 'compare.dart';
import 'findings.dart';

/// The job's id in the activity tray.
const String contradictionsJobId = 'contradictions';

/// Where the settings are kept, on this device.
const String contradictionsSettingsKey = 'glyph-contradictions-settings';

/// Where a book is kept when the library has no folder to put its file in: this, then the book's id.
const String contradictionsBookKey = 'glyph-contradictions-book:';

/// How long after the last save a run When a note is saved waits.
const Duration savedQuiet = Duration(minutes: 2);

/// When it runs on its own.
enum ContradictionSchedule {
  off('Off'),
  saved('When a note is saved'),
  nightly('Nightly');

  const ContradictionSchedule(this.label);
  final String label;
}

/// The person's settings for the finder, this device's.
@immutable
class ContradictionSettings {
  const ContradictionSettings({this.schedule = ContradictionSchedule.nightly, this.threshold = defaultThreshold, this.byFolder = false, this.orgs = false, this.ranOnce = false, this.lastRun});

  final ContradictionSchedule schedule;

  /// The confidence a finding needs: 0.7, 0.8 or 0.9.
  final double threshold;

  /// "Within each folder only": personal notes compared within their top folder.
  final bool byFolder;

  /// "Organization notes": each organization's notes compared with its own. Off until turned on.
  final bool orgs;

  /// Run by hand once: what lets it run on its own.
  final bool ranOnce;
  final DateTime? lastRun;

  ContradictionSettings copyWith({ContradictionSchedule? schedule, double? threshold, bool? byFolder, bool? orgs, bool? ranOnce, DateTime? lastRun}) => ContradictionSettings(
        schedule: schedule ?? this.schedule,
        threshold: threshold ?? this.threshold,
        byFolder: byFolder ?? this.byFolder,
        orgs: orgs ?? this.orgs,
        ranOnce: ranOnce ?? this.ranOnce,
        lastRun: lastRun ?? this.lastRun,
      );

  Map<String, Object?> toJson() => {'schedule': schedule.name, 'threshold': threshold, 'byFolder': byFolder, 'orgs': orgs, 'ranOnce': ranOnce, 'lastRun': ?lastRun?.toUtc().toIso8601String()};

  static ContradictionSettings fromJson(Object? json) {
    if (json is! Map) return const ContradictionSettings();
    final threshold = json['threshold'];
    return ContradictionSettings(
      schedule: ContradictionSchedule.values.where((s) => s.name == json['schedule']).firstOrNull ?? ContradictionSchedule.nightly,
      threshold: threshold is num && threshold >= 0.5 && threshold <= 1 ? threshold.toDouble() : defaultThreshold,
      byFolder: json['byFolder'] == true,
      orgs: json['orgs'] == true,
      ranOnce: json['ranOnce'] == true,
      lastRun: DateTime.tryParse('${json['lastRun']}'),
    );
  }
}

/// How a run ended.
enum RunEnd { done, stopped, failed, nobody, nothing, busy }

/// The finder (see the header).
class ContradictionRunner extends ChangeNotifier {
  ContradictionRunner({
    required this.notes,
    required this.pickAi,
    FindingsFile Function(ContradictionScope scope)? fileFor,
    Stored? store,
    DateTime Function()? clock,
    Activity? activity,
    this.enabled,
    this.onOpen,
    this.writeNote,
  })  : _fileFor = fileFor,
        _store = store,
        _clock = clock ?? DateTime.now,
        _activity = activity {
    _settings = ContradictionSettings.fromJson((_store ?? stored).read<Object?>(contradictionsSettingsKey, null));
  }

  /// The library's notes now.
  final List<Note> Function() notes;

  /// Who to ask, asked at the start of each run (ai.dart `appContradictionAi`).
  final Future<ContradictionAi?> Function() pickAi;

  final FindingsFile Function(ContradictionScope scope)? _fileFor;
  final Stored? _store;
  final DateTime Function() _clock;
  final Activity? _activity;

  /// Whether the plugin is on: nothing runs on its own otherwise.
  final bool Function()? enabled;

  /// What View on the job's end opens (the plugin's page).
  final VoidCallback? onOpen;

  /// Writes a closed note: [change] made of its words. For Mark superseded from the page's list.
  final Future<void> Function(String noteId, String Function(String body) change)? writeNote;

  Activity get activity => _activity ?? globalActivity();

  late ContradictionSettings _settings;
  ContradictionSettings get settings => _settings;

  final Map<String, FindingsBook> _books = {};
  final Map<String, ContradictionScope> _bookScopes = {};
  bool _loaded = false;

  bool _running = false;
  bool get running => _running;
  bool _stopping = false;
  void Function()? _cancel;

  int _done = 0, _total = 0;
  int get done => _done;
  int get total => _total;

  /// What stopped the last run, in words; null after one that ended well.
  String? _problem;
  String? get problem => _problem;

  /// Told every time the findings change: the editor's marks are asked for again (lib/plugins/contradictions/).
  VoidCallback? onFindings;

  void setSettings(ContradictionSettings next) {
    _settings = next;
    (_store ?? stored).write(contradictionsSettingsKey, next.toJson());
    notifyListeners();
  }

  FindingsFile _file(ContradictionScope scope) => _fileFor?.call(scope) ?? StoredFindingsFile('$contradictionsBookKey${scope.bookId}', _store);

  /// The books of the scopes [notes] are in, read once each.
  Future<void> load() async {
    final scopes = <String, ContradictionScope>{};
    for (final note in notes()) {
      final scope = scopeOfPath(note.path);
      scopes.putIfAbsent(scope.bookId, () => scope);
    }
    scopes.putIfAbsent('personal', () => const ContradictionScope.personal());
    var changed = false;
    for (final MapEntry(key: id, value: scope) in scopes.entries) {
      if (_books.containsKey(id)) continue;
      _bookScopes[id] = scope;
      _books[id] = FindingsBook.decode(await _file(scope).read());
      changed = true;
    }
    if (!_loaded || changed) {
      _loaded = true;
      _findingsChanged();
    }
  }

  /// Every open finding whose notes are both still here, newest first.
  List<Finding> get open {
    final here = {for (final n in notes()) if (!n.inTrash) n.id};
    final all = [
      for (final book in _books.values)
        for (final f in book.open)
          if (here.contains(f.olderId) && here.contains(f.newerId)) f,
    ]..sort((a, b) => b.found.compareTo(a.found));
    return all;
  }

  /// The open findings on [noteId]'s lines.
  List<Finding> openOn(String noteId) => [for (final f in open) if (f.olderId == noteId) f];

  /// How many notes may be out of date.
  int get staleNotes => {for (final f in open) f.olderId}.length;

  FindingsBook _bookOf(Finding finding) {
    for (final book in _books.values) {
      if (book.findings.any((f) => f.key == finding.key)) return book;
    }
    return const FindingsBook();
  }

  Future<void> _settle(Finding finding, FindingState state) async {
    for (final MapEntry(key: id, value: book) in _books.entries.toList()) {
      if (!book.findings.any((f) => f.key == finding.key)) continue;
      final next = book.setting(finding.key, state);
      _books[id] = next;
      await _file(_bookScopes[id]!).write(next.encode());
    }
    _findingsChanged();
  }

  /// "Not a conflict": never shown again, nor found again.
  Future<void> dismiss(Finding finding) => _settle(finding, FindingState.dismissed);

  /// The finding marked superseded, once its line is written ([withSuperseded], by the editor or by [writeNote]).
  Future<void> superseded(Finding finding) => _settle(finding, FindingState.superseded);

  /// Mark superseded for a note that is not open: its words changed through [writeNote], then the finding settled.
  Future<void> markSuperseded(Finding finding) async {
    final write = writeNote;
    if (write != null) await write(finding.olderId, (body) => withSuperseded(body, finding, _clock()));
    await superseded(finding);
  }

  /// Whether [finding] is still open (a test's question, and the sheet's).
  bool isOpen(Finding finding) => _bookOf(finding).findings.any((f) => f.key == finding.key && f.state == FindingState.open);

  void _findingsChanged() {
    notifyListeners();
    onFindings?.call();
  }

  bool _orgAllowed(ContradictionScope scope) => scope.personal || _settings.orgs;

  /// The pairs a run would ask about now ([touching]: only those with one of these notes in them).
  Future<List<CandidatePair>> plan({Set<String>? touching}) async {
    await load();
    final checked = {for (final book in _books.values) ...book.checked};
    return candidatePairs(notes(), byFolder: _settings.byFolder, checked: checked, touching: touching, allowed: _orgAllowed);
  }

  /// What a run of [pairs] would cost: how many, and how long with [ai].
  JobEstimate estimate(int pairs, ContradictionAi ai) {
    final requests = (pairs / pairsPerRequest).ceil();
    return JobEstimate(count: pairs, one: 'note pair', many: 'note pairs', duration: ai.perRequest * requests);
  }

  /// One run (see the header). [personStarted] for Check now, which also lets it run on its own from then on.
  Future<RunEnd> run({Set<String>? touching, bool personStarted = false, List<CandidatePair>? pairs}) async {
    if (_running) return RunEnd.busy;
    _running = true;
    _stopping = false;
    _problem = null;
    _done = 0;
    _total = 0;
    notifyListeners();
    JobHandle? job;
    try {
      final ai = await pickAi();
      if (ai == null) {
        _problem = 'nobody';
        return RunEnd.nobody;
      }
      final todo = pairs ?? await plan(touching: touching);
      if (personStarted) setSettings(_settings.copyWith(ranOnce: true));
      // Notes gone since a finding was made take their findings with them.
      final ids = {for (final n in notes()) n.id};
      for (final id in _books.keys.toList()) {
        _books[id] = _books[id]!.keepingNotes(ids);
      }
      if (todo.isEmpty) {
        setSettings(_settings.copyWith(lastRun: _clock()));
        return RunEnd.nothing;
      }
      _total = todo.length;
      job = activity.begin(contradictionsJobId, kind: JobKind.ai, title: 'Checking for contradictions', line: 'With ${ai.name}', onStop: stop, onOpen: onOpen, personStarted: personStarted, estimate: estimate(todo.length, ai), plugin: 'contradictions');
      job.progress(done: 0, total: _total, unit: 'pairs');
      notifyListeners();

      // By scope first, then six to a request: a prompt never holds two scopes' notes.
      final byScope = <ContradictionScope, List<CandidatePair>>{};
      for (final pair in todo) {
        byScope.putIfAbsent(scopeOfPath(pair.older.path, byFolder: _settings.byFolder), () => []).add(pair);
      }
      var found = 0;
      for (final MapEntry(key: scope, value: scoped) in byScope.entries) {
        for (var at = 0; at < scoped.length; at += pairsPerRequest) {
          if (_stopping) {
            job.stopped(tally: JobTally('note pair checked', 'note pairs checked', _done));
            return RunEnd.stopped;
          }
          final batch = scoped.sublist(at, (at + pairsPerRequest).clamp(0, scoped.length));
          final asked = ai.ask(system: compareSystem, prompt: comparePrompt(batch));
          _cancel = asked.cancel;
          final String answer;
          try {
            answer = await asked.answer;
          } catch (failure) {
            if (_stopping) {
              job.stopped(tally: JobTally('note pair checked', 'note pairs checked', _done));
              return RunEnd.stopped;
            }
            _problem = '$failure';
            job.failed('$failure', fix: JobFix(JobFixKind.retry, () => unawaited(run(personStarted: true))));
            return RunEnd.failed;
          } finally {
            _cancel = null;
          }
          final book = _books[scope.bookId] ?? const FindingsBook();
          final fresh = [for (final f in readFindings(answer, batch, now: _clock(), threshold: _settings.threshold)) if (!book.settled(f)) f];
          final next = book.adding(fresh, checked: {for (final p in batch) p.checkKey: p.revisions});
          found += next.open.length - book.open.length;
          _books[scope.bookId] = next;
          _bookScopes[scope.bookId] = scope.org == null ? const ContradictionScope.personal() : ContradictionScope.org(scope.org!);
          await _file(_bookScopes[scope.bookId]!).write(next.encode());
          _done += batch.length;
          job.progress(done: _done, total: _total, unit: 'pairs');
          _findingsChanged();
        }
      }
      setSettings(_settings.copyWith(lastRun: _clock()));
      final stale = staleNotes;
      job.done(
        result: JobResult(found == 0 ? 'No new contradictions' : (stale == 1 ? '1 note may be out of date' : '$stale notes may be out of date'), onOpen: onOpen),
        tally: JobTally('note pair checked', 'note pairs checked', _done),
        quiet: found == 0 && !personStarted,
      );
      return RunEnd.done;
    } finally {
      _running = false;
      _stopping = false;
      notifyListeners();
    }
  }

  /// Stops the run after the request in flight, which is cancelled.
  void stop() {
    if (!_running) return;
    _stopping = true;
    _cancel?.call();
    notifyListeners();
  }

  // ---- on its own ------------------------------------------------------------------------------------------------

  final Set<String> _saved = {};
  Timer? _quiet;
  final Map<String, int> _seen = {};

  bool get _mayRunAlone => _settings.ranOnce && (enabled?.call() ?? true);

  /// The library's notes changed: those edited since are remembered, and When a note is saved runs [savedQuiet] after
  /// the last of them.
  void notesChanged() {
    final now = notes();
    final first = _seen.isEmpty;
    var unread = false;
    for (final note in now) {
      final was = _seen[note.id];
      _seen[note.id] = note.revision;
      if (!first && was != note.revision) _saved.add(note.id);
      // A scope whose book is not read yet (an organization's notes arriving after launch): read it.
      if (was == null && _loaded && !_books.containsKey(scopeOfPath(note.path).bookId)) unread = true;
    }
    if (unread) unawaited(load());
    if (_saved.isEmpty || _settings.schedule != ContradictionSchedule.saved || !_mayRunAlone) return;
    _quiet?.cancel();
    _quiet = Timer(savedQuiet, () {
      final touching = {..._saved};
      _saved.clear();
      unawaited(run(touching: touching));
    });
  }

  /// A note saved by [id] (for a caller that knows which).
  void noteSaved(String id) {
    _saved.add(id);
    notesChanged();
  }

  /// Whether Nightly is due at [now]: never run, or last run a day before and it is past three in the morning, or more
  /// than a day and a half since.
  bool nightlyDue(DateTime now) {
    final last = _settings.lastRun?.toLocal();
    if (last == null) return true;
    final since = now.difference(last);
    if (since >= const Duration(hours: 36)) return true;
    final today = DateTime(now.year, now.month, now.day);
    return last.isBefore(today) && now.hour >= 3;
  }

  /// Asked every quarter of an hour while the app runs, and at its start: Nightly runs when it is due.
  void tick() {
    if (_running || _settings.schedule != ContradictionSchedule.nightly || !_mayRunAlone) return;
    if (nightlyDue(_clock())) unawaited(run());
  }

  Timer? _ticker;

  /// Starts the quarter-hourly [tick].
  void start() {
    _ticker ??= Timer.periodic(const Duration(minutes: 15), (_) => tick());
    notesChanged();
    unawaited(load().then((_) => tick()));
  }

  @override
  void dispose() {
    _quiet?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}

/// The app's activity (lib/core/background_jobs.dart `activity`), asked when used so a test's is the one used.
Activity globalActivity() => activity;

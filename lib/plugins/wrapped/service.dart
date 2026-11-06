/// Wrapped as the app holds it (docs/WRAPPED.md): the state kept in the Library ([WrappedStore]), the pass on the
/// Activity tray, the counts, and the review's lists with what each press does. The root makes it once the library is
/// read ([WrappedService.current]); the plugin's page, the home card, the sidebar's row and the story read it.
///
/// When it runs. Never on its own the first time: a run starts on a press of Make my Wrapped, which first says what it
/// will send and about what it costs (lib/activity/activity_cost.dart `askJobCost`), since it spends the person's own
/// key. Once asked for, a run goes on across launches until it has read every note ([WrappedState.wanted]); Make my
/// Wrapped again later reads only the notes that changed. The plugin switched off stops it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../activity/activity_cost.dart' show askJobCost;
import '../../ai/contradictions/findings.dart' show Finding;
import '../../ai/contradictions/runner.dart' show ContradictionRunner;
import '../../assistant/assistant.dart' show AssistantChoice;
import '../../core/background_jobs.dart';
import '../../core/library.dart';
import '../../core/metrics.dart' show MetricEvent, countBucket, durationBucket, track;
import '../../core/note.dart';
import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/note_text.dart' show noteTitle;
import '../../core/phone_notices.dart' show NoticesHost, NoticesState;
import '../../book/journal.dart' show withEntry;
import '../../core/book.dart' show isJournalBody;
import '../../core/trash.dart';
import '../../core/workspaces.dart';
import '../cleanup/ai.dart';
import '../cleanup/records.dart' show CleanupRecord;
import '../cleanup/text.dart' show duplicateGroups;
import '../contradictions/contradictions.dart' show contradictionRunner;
import '../note_decay/decay.dart' show noteDecay;
import 'actions.dart';
import 'manifest.dart';
import 'pass.dart';
import 'review.dart' show wrappedOpenNote;
import 'state.dart';
import 'stats.dart';
import 'todos.dart';
import 'weekly.dart';

/// The job a pass is on the Activity tray as.
const String wrappedJobId = 'wrapped';

/// The job a weekly report's AI part is on the tray as: neither holds the other back as "the app is busy".
const String wrappedWeeklyJobId = 'wrapped-weekly';

/// The most notes a weekly report reads again for their gists: the most recently edited of the week's.
const int weeklyMostGists = 60;

/// A note not edited for this long is taken for stale without the AI, where it is short too.
const Duration staleAfter = Duration(days: 270);

/// A note not edited for this long can be "the one you forgot".
const Duration forgottenAfter = Duration(days: 90);

/// One open to-do as the review lists it.
typedef TodoRow = ({WrappedTodo todo, String title, int written});

/// One stale note as the review lists it, and why.
typedef StaleRow = ({Note note, String title, String why});

/// See the library doc.
class WrappedService extends ChangeNotifier {
  WrappedService({
    required this.library,
    required this.workspaces,
    required this.trash,
    WrappedStore? store,
    this.choice,
    bool Function()? on,
    Listenable? switches,
    bool Function()? localOnly,
    Future<List<CleanupAi>> Function()? ais,
    Activity? activity,
    BackgroundJobs? background,
    bool Function()? busy,
    DateTime Function()? clock,
    Future<void> Function(Duration wait)? wait,
    WrappedPacing? pacing,
    this.onOpen,
    this.plugins,
    ContradictionRunner? Function()? contradictions,
    NoticesHost? notices,
    int Function()? firstWeekday,
    bool Function()? notesRead,
  })  : store = store ?? WrappedStore(),
        _on = on ?? (() => true),
        _switches = switches,
        _localOnly = localOnly ?? (() => false),
        _ais = ais,
        _activity = activity,
        _background = background ?? const NoBackgroundJobs(),
        _busy = busy,
        _clock = clock ?? DateTime.now,
        _wait = wait,
        _pacing = pacing,
        _contradictions = contradictions ?? (() => contradictionRunner.value),
        _notices = notices,
        _firstWeekday = firstWeekday ?? (() => DateTime.monday),
        _notesRead = notesRead ?? (() => true),
        editing = WrappedEditing(library: library, workspaces: workspaces, trash: trash, clock: clock) {
    this.store.addListener(notifyListeners);
    _switches?.addListener(_switched);
  }

  /// The app's, once the root has made it; null in a build or a test without one.
  static WrappedService? current;

  final NoteLibrary library;
  final WorkspaceStore workspaces;
  final Trash trash;
  final WrappedStore store;
  final AssistantChoice? choice;
  final WrappedEditing editing;
  final bool Function() _on;
  final Listenable? _switches;
  final bool Function() _localOnly;
  final Future<List<CleanupAi>> Function()? _ais;
  final Activity? _activity;
  final BackgroundJobs _background;
  final bool Function()? _busy;
  final DateTime Function() _clock;
  final Future<void> Function(Duration wait)? _wait;
  final WrappedPacing? _pacing;
  final ContradictionRunner? Function() _contradictions;
  final NoticesHost? _notices;
  final int Function() _firstWeekday;

  /// Whether the library has been read: before, an empty list would be taken for an empty week.
  final bool Function() _notesRead;

  /// Opens the Wrapped page: the tray's View.
  final VoidCallback? onOpen;

  /// How many plugins are on, for the counts.
  final int Function()? plugins;

  Activity get _record => _activity ?? activity;
  WrappedState get state => store.value;
  bool get on => _on();

  WrappedStop? _stop;
  bool _running = false;
  bool _held = false;
  int _done = 0, _total = 0;
  String? _problem;
  WrappedEstimate? _estimate;
  List<CleanupAi> _connected = const [];
  bool _aisRead = false;

  bool get running => _running;

  /// Held while the app is busy.
  bool get held => _held;
  int get done => _done;
  int get total => _total;

  /// How far the run is, 0 to 1.
  double get fraction => _total == 0 ? 0 : (_done / _total).clamp(0, 1);
  String? get problem => _problem;
  WrappedEstimate? get estimate => _estimate;
  bool get aisRead => _aisRead;

  /// The AI a run would ask: the one picked on the page ("Which AI") where it is connected, else the app's own choice
  /// for the assistant, else the first (Cleanup's rule, cleanup/ai.dart `defaultAiId`).
  CleanupAi? get ai {
    final id = defaultAiId(_connected, choice: choice, chosen: state.chosenAi, localOnly: _localOnly());
    return _connected.where((a) => a.id == id).firstOrNull;
  }

  /// The AIs that can be asked now, as last read ([readAis]).
  List<CleanupAi> get ais => _connected;

  /// "Which AI": [id] asked from now on, kept in Wrapped's file; its estimate made again.
  void chooseAi(String id) {
    store.change((now) => now.copyWith(chosenAi: () => id));
    final ai = this.ai;
    final notes = passNotes;
    _estimate = ai == null ? null : wrappedEstimate(notesToRead(notes, state.reads), notes.length, ai, pacing: _pacing);
    notifyListeners();
  }

  void _switched() {
    if (!on) {
      stop();
      _weeklyStop?.stop();
      _weeklyTimer?.cancel();
    } else {
      if (state.wanted && !_running) unawaited(resume());
      // Switched on (or back on): the weekly report looked at, and timed from now.
      unawaited(lookWeekly());
    }
    notifyListeners();
  }

  // ---- the notes ---------------------------------------------------------------------------------------------------

  /// Whether [note] is the person's own: filed in no folder, or one of theirs (never an organization's).
  bool _own(Note note) {
    final at = workspaces.value.of[note.id];
    return at == null || workspaces.orgOf(at) == null;
  }

  /// The person's own notes out of the Trash, archived ones too: what the counts read. The weekly reports and their
  /// journal are the app's own, and left out.
  List<Note> get ownNotes => [
        for (final note in library.value)
          if (!trashedNote(note, trash.value) && _own(note) && !isWeeklyNote(note)) note,
      ];

  /// The notes a pass reads: the person's own, out of the Archive too.
  List<WrappedNote> get passNotes {
    final list = workspaces.value.list;
    return [
      for (final note in ownNotes)
        if (note.archivedAt == null || note.archivedAt == 0)
          WrappedNote(
            id: note.id,
            title: noteTitle(note.body),
            body: note.body,
            updatedAt: note.updatedAt,
            createdAt: note.createdAt,
            folderId: workspaces.value.of[note.id],
            folder: workspaces.value.of[note.id] == null ? '' : workspacePathName(list, workspaces.value.of[note.id]!),
          ),
    ];
  }

  List<WrappedFolder> get _folders => [
        for (final w in workspaces.value.list)
          if (workspaces.orgOf(w.id) == null && !w.id.startsWith('org-')) (id: w.id, path: workspacePathName(workspaces.value.list, w.id)),
      ];

  /// The counts for [period] (the state's own unless given).
  WrappedStats stats([WrappedPeriod? period]) {
    final list = workspaces.value.list;
    return wrappedStats(ownNotes, period ?? state.period, now: _clock(), folderOf: (id) => workspaces.value.of[id] == null ? null : workspacePathName(list, workspaces.value.of[id]!), plugins: plugins?.call() ?? 0);
  }

  void setPeriod(WrappedPeriod period) => store.change((now) => now.copyWith(period: period));

  /// The story opened: a Wrapped is no longer fresh, and it is counted.
  void seen() {
    store.change((now) => now.copyWith(seen: _clock()));
    track(MetricEvent.wrappedViewed, {'period': state.period.wire});
  }

  // ---- the run -------------------------------------------------------------------------------------------------------

  /// Reads which AIs can be asked now, and the estimate for a run with the one chosen.
  Future<void> readAis() async {
    try {
      _connected = await (_ais ?? () => connectedAis(choice: choice, localOnly: _localOnly()))();
    } catch (_) {
      _connected = const [];
    }
    _aisRead = true;
    final ai = this.ai;
    final notes = passNotes;
    _estimate = ai == null ? null : wrappedEstimate(notesToRead(notes, state.reads), notes.length, ai, pacing: _pacing);
    notifyListeners();
  }

  /// Why Make my Wrapped cannot run now, or null.
  String? get cannotMake {
    if (!on) return 'Turn Wrapped on in Settings › Plugins first.';
    if (_aisRead && ai == null) return _localOnly() ? 'Local only is on, and there is no model on this device yet.' : 'No AI is connected yet. Connect one in Settings › AI, or make your Wrapped with the counts alone.';
    return null;
  }

  /// Make my Wrapped (see the library doc): the estimate asked about in [context] (always the first time), then the
  /// run. Without an AI the counts alone are the Wrapped. Answers whether it ran.
  Future<bool> make([BuildContext? context]) async {
    if (_running || !on) return false;
    await readAis();
    final ai = this.ai;
    if (ai == null) {
      // The counts need no AI: the Wrapped is made of them alone.
      store.change((now) => now.copyWith(finished: () => _clock(), wanted: false));
      return true;
    }
    final estimate = _estimate!;
    final job = estimate.job(first: !state.made);
    if (job.asks) {
      final yes = context != null && context.mounted && await askJobCost(context, job, title: 'Make your Wrapped with ${ai.name}?');
      if (!yes) return false;
    }
    store.change((now) => now.copyWith(wanted: true, began: () => _clock(), aiName: ai.name));
    track(MetricEvent.wrappedStarted, {'notes': countBucket(estimate.notes), 'period': state.period.wire, 'provider': _provider(ai)});
    await _run(ai);
    return true;
  }

  /// Goes on with a run that was asked for and not finished: as the app opens, and as the plugin is switched back on.
  Future<void> resume() async {
    if (_running || !on || !state.wanted) return;
    await readAis();
    final ai = this.ai;
    if (ai == null) return;
    await _run(ai);
  }

  String _provider(CleanupAi ai) => ai.local ? 'local' : (const {'claude', 'openai', 'gemini', 'aster'}.contains(ai.id) ? ai.id : 'custom');

  bool _busyNow() => _busy?.call() ?? _record.value.any((job) => job.state.live && job.id != wrappedJobId && job.id != wrappedWeeklyJobId);

  Future<void> _run(CleanupAi ai) async {
    final stop = _stop = WrappedStop();
    _running = true;
    _problem = null;
    final began = _clock();
    final notes = passNotes;
    final toRead = notesToRead(notes, state.reads);
    _done = 0;
    _total = toRead.length;
    notifyListeners();
    final job = _record.begin(
      wrappedJobId,
      kind: JobKind.ai,
      title: 'Making your Wrapped',
      line: 'Reading with ${ai.name}',
      onStop: this.stop,
      onOpen: onOpen,
      personStarted: true,
      estimate: _estimate?.job(first: false),
      plugin: ai.plugin ?? wrappedId,
    );
    _background.onStop((id) {
      if (id == wrappedJobId) this.stop();
    });
    unawaited(_background.running(wrappedJobId, title: 'Making your Wrapped', text: '0 of ${toRead.length} notes'));
    void told(int done, int total, {bool held = false}) {
      _done = done;
      _held = held;
      if (held) {
        job.waiting(WaitingOn.turn, line: 'Paused while the app is busy');
      } else {
        job.running(line: 'Reading with ${ai.name}');
        job.progress(done: done, total: total, unit: 'notes');
        unawaited(_background.running(wrappedJobId, title: 'Making your Wrapped', text: '$done of $total notes', done: done, total: total));
      }
      notifyListeners();
    }

    try {
      final read = await readNotes(
        toRead: toRead,
        ai: ai,
        pacing: _pacing,
        busy: _busyNow,
        progress: told,
        stop: stop,
        wait: _wait,
        now: _clock,
        kept: (reads) => store.change((now) => now.copyWith(reads: {...now.reads, ...reads})),
      );
      if (read.end == PassEnd.failed) {
        _problem = read.problem;
        job.failed(read.problem ?? 'The AI didn’t answer.');
        return;
      }
      if (read.end == PassEnd.stopped) {
        job.stopped(tally: JobTally('note', 'notes', read.read));
        return;
      }
      // The library's ask, from the gists, and the duplicates the app finds itself.
      LibraryRead library = const LibraryRead();
      try {
        library = await readLibraryWith(ai, notes, state.reads, _folders, pacing: _pacing, stop: stop);
      } catch (failure) {
        if (stop.stopped) {
          job.stopped(tally: JobTally('note', 'notes', read.read));
          return;
        }
        _problem = '$failure'.replaceFirst('Exception: ', '');
      }
      final found = duplicateGroups([for (final n in notes) (id: n.id, title: n.title, body: n.body, updatedAt: n.updatedAt)]);
      final merges = [for (final group in found) WrappedSuggestion(kind: SuggestionKind.merge, notes: group, why: 'The same words twice', found: true)];
      final inFound = {for (final g in found) ...g};
      store.change((now) {
        final reads = {...now.reads};
        for (final id in library.gems) {
          if (reads[id] case final read?) reads[id] = WrappedRead(hash: read.hash, gist: read.gist, themes: read.themes, stale: read.stale, staleWhy: read.staleWhy, gem: true, at: read.at);
        }
        return now.copyWith(
          wanted: false,
          finished: () => _clock(),
          reads: {for (final MapEntry(:key, :value) in reads.entries) if (notes.any((n) => n.id == key)) key: value},
          themes: library.themes.isEmpty ? now.themes : library.themes,
          suggestions: [...merges, for (final s in library.suggestions) if (s.kind != SuggestionKind.merge || !s.notes.any(inFound.contains)) s],
        );
      });
      track(MetricEvent.wrappedFinished, {'notes': countBucket(notes.length), 'took': durationBucket(_clock().difference(began))});
      job.done(result: JobResult('Your Wrapped is ready', action: 'View', onOpen: onOpen), tally: JobTally('note', 'notes', read.read));
    } catch (failure) {
      _problem = '$failure';
      job.failed('$failure');
    } finally {
      _running = false;
      _held = false;
      _stop = null;
      _background.onStop(null);
      unawaited(_background.ended(wrappedJobId, title: state.wanted ? 'Wrapped paused' : 'Your Wrapped is ready', quiet: state.wanted));
      notifyListeners();
    }
  }

  /// Stops the run; what it read so far is kept, and the run goes on when Make my Wrapped is pressed again.
  void stop() => _stop?.stop();

  /// Stops it and asks for nothing more: Stop on the page, so the next launch does not take it up again.
  void stopForGood() {
    stop();
    store.change((now) => now.copyWith(wanted: false));
  }

  // ---- the review's lists --------------------------------------------------------------------------------------------

  bool _dismissed(String key) => state.dismissed.contains(key);
  bool _later(String id) => (state.later[id] ?? 0) > _clock().millisecondsSinceEpoch;

  /// Every open to-do in the person's own notes, the oldest note's first, less those kept.
  List<TodoRow> get todos {
    final rows = <TodoRow>[
      for (final note in ownNotes)
        if (note.archivedAt == null || note.archivedAt == 0)
          for (final todo in openTodos(note.id, note.body))
            if (!_dismissed('todo:${todo.key}')) (todo: todo, title: noteTitle(note.body), written: note.createdAt),
    ];
    rows.sort((a, b) => a.written != b.written ? a.written.compareTo(b.written) : a.todo.line.compareTo(b.todo.line));
    return rows;
  }

  /// The stale notes: what the AI took for stale, what Note decay alerts marks where it is on, and short notes nobody
  /// has opened in nine months; less those kept and those put off till later.
  List<StaleRow> get stale {
    final now = _clock().millisecondsSinceEpoch;
    final decay = noteDecay;
    final decayed = <String, String>{
      if (decay != null && decay.on)
        for (final page in decay.pages()) page.note.id: page.signals.first.reason,
    };
    final rows = <StaleRow>[];
    for (final note in ownNotes) {
      if (note.archivedAt != null && note.archivedAt != 0) continue;
      if (_dismissed('stale:${note.id}') || _later(note.id)) continue;
      final read = state.reads[note.id];
      final old = now - note.updatedAt > staleAfter.inMilliseconds;
      final why = read != null && read.stale && read.hash == WrappedNote(id: note.id, title: '', body: note.body, updatedAt: 0, createdAt: 0).hash
          ? (read.staleWhy.isEmpty ? 'Looks abandoned' : read.staleWhy)
          : decayed[note.id] ?? (old && noteWords(note.body) < 40 ? 'Short, and not edited in ${((now - note.updatedAt) / 86400000 / 30).round()} months' : null);
      if (why != null) rows.add((note: note, title: noteTitle(note.body), why: why));
    }
    rows.sort((a, b) => a.note.updatedAt.compareTo(b.note.updatedAt));
    return rows;
  }

  /// The suggestions still to answer: not dismissed, every note still here and out of the Trash.
  List<WrappedSuggestion> get suggestions {
    final here = {for (final n in ownNotes) n.id};
    return [
      for (final s in state.suggestions)
        if (!_dismissed('suggestion:${s.id}') && s.notes.every(here.contains)) s,
    ];
  }

  /// What may be out of date, from the contradiction finder where it is on (lib/ai/contradictions/).
  ContradictionRunner? get contradictions => _contradictions();

  /// The notes the person may have forgotten, oldest edit first: the AI's gems not opened in three months; with no AI,
  /// the longest note not edited in a year.
  List<Note> get forgotten {
    final now = _clock().millisecondsSinceEpoch;
    final notes = ownNotes;
    final gems = [
      for (final note in notes)
        if ((state.reads[note.id]?.gem ?? false) && now - note.updatedAt > forgottenAfter.inMilliseconds) note,
    ]..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    if (gems.isNotEmpty) return gems.take(3).toList();
    final old = [for (final note in notes) if (now - note.updatedAt > const Duration(days: 365).inMilliseconds && noteWords(note.body) >= 60) note]
      ..sort((a, b) => noteWords(b.body).compareTo(noteWords(a.body)));
    return old.take(1).toList();
  }

  /// The themes: the AI's, else the period's top tags.
  List<String> themes([WrappedStats? stats]) => state.themes.isNotEmpty ? state.themes : [for (final t in (stats ?? this.stats()).topTags.take(5)) '#${t.name}'];

  /// The gist the pass wrote for [noteId], or empty.
  String gistOf(String noteId) => state.reads[noteId]?.gist ?? '';

  // ---- the presses ---------------------------------------------------------------------------------------------------

  void _counted(WrappedActionKind kind, int count) => track(MetricEvent.wrappedAction, {'kind': kind.wire, 'count': countBucket(count)});

  WrappedDone _kept(WrappedDone done) {
    final record = done.record;
    if (record != null) {
      store.change((now) => now.copyWith(records: [record, ...now.records].take(WrappedState.mostRecords).toList()));
    }
    return done;
  }

  /// [todos] checked off, through the note's own write.
  Future<WrappedDone> checkOff(List<WrappedTodo> todos) async {
    final done = _kept(await editing.todos(todos, remove: false));
    _counted(WrappedActionKind.checkOff, done.done);
    return done;
  }

  /// [todos] taken out of their notes.
  Future<WrappedDone> removeTodos(List<WrappedTodo> todos) async {
    final done = _kept(await editing.todos(todos, remove: true));
    _counted(WrappedActionKind.removeTodo, done.done);
    return done;
  }

  /// [todos] kept as they are, and never listed again while their words stay.
  void keepTodos(List<WrappedTodo> todos) {
    store.change((now) => now.copyWith(dismissed: {...now.dismissed, for (final t in todos) 'todo:${t.key}'}));
    _counted(WrappedActionKind.keep, todos.length);
  }

  Future<WrappedDone> archive(List<String> ids) async {
    final done = _kept(await editing.stale(ids, toTrash: false));
    _counted(WrappedActionKind.archive, done.done);
    return done;
  }

  Future<WrappedDone> putInTrash(List<String> ids) async {
    final done = _kept(await editing.stale(ids, toTrash: true));
    _counted(WrappedActionKind.trash, done.done);
    return done;
  }

  /// A stale note kept as it is.
  void keepNotes(List<String> ids) {
    store.change((now) => now.copyWith(dismissed: {...now.dismissed, for (final id in ids) 'stale:$id'}));
    _counted(WrappedActionKind.keep, ids.length);
  }

  /// A stale note put off for a month: it is read again with the next Wrapped, and listed again after.
  void later(List<String> ids) {
    final until = _clock().add(const Duration(days: 30)).millisecondsSinceEpoch;
    store.change((now) {
      final reads = {...now.reads}..removeWhere((id, _) => ids.contains(id));
      return now.copyWith(later: {...now.later, for (final id in ids) id: until}, reads: reads);
    });
    _counted(WrappedActionKind.later, ids.length);
  }

  /// [s] applied, by Cleanup's apply; dismissed once done, so it is not offered again.
  Future<WrappedDone> apply(WrappedSuggestion s) async {
    final done = _kept(await editing.suggestion(s));
    if (done.record != null) store.change((now) => now.copyWith(dismissed: {...now.dismissed, 'suggestion:${s.id}'}));
    _counted(switch (s.kind) { SuggestionKind.merge => WrappedActionKind.merge, SuggestionKind.link => WrappedActionKind.link, _ => WrappedActionKind.move }, done.done);
    return done;
  }

  /// [s] dismissed, and remembered.
  void dismiss(WrappedSuggestion s) {
    store.change((now) => now.copyWith(dismissed: {...now.dismissed, 'suggestion:${s.id}'}));
    _counted(WrappedActionKind.dismiss, 1);
  }

  /// A contradiction marked superseded, or not a conflict, by the finder's own (lib/ai/contradictions/runner.dart).
  Future<void> superseded(Finding finding) async {
    await contradictions?.markSuperseded(finding);
    _counted(WrappedActionKind.superseded, 1);
  }

  Future<void> notConflict(Finding finding) async {
    await contradictions?.dismiss(finding);
    _counted(WrappedActionKind.notConflict, 1);
  }

  /// The press [recordId] taken back, whole.
  Future<String> undo(String recordId) async {
    final record = state.records.where((r) => r.id == recordId).firstOrNull;
    if (record == null || record.undone) return 'Already undone.';
    final back = await editing.undo(record);
    store.change((now) => now.copyWith(records: [for (final r in now.records) r.id == recordId ? undoneRecord(r) : r]));
    _counted(WrappedActionKind.undo, back.undone);
    return back.left.isEmpty ? 'Undone.' : 'Undone, but ${back.left.join('; ')}.';
  }

  /// The last press that can still be taken back.
  CleanupRecord? get lastRecord => state.records.where((r) => !r.undone).firstOrNull;

  /// Kept Clear: the reads forgotten, so the next Make my Wrapped reads every note again.
  void forgetReads() => store.change((now) => now.copyWith(reads: const {}, themes: const [], suggestions: const []));

  // ---- the weekly report (weekly.dart) ---------------------------------------------------------------------------------

  Timer? _weeklyTimer;
  bool _weeklyMaking = false;
  WrappedStop? _weeklyStop;

  WeeklySettings get weeklySettings => state.weekly.settings;

  /// The first day of the week where the device is (weekly.dart `firstWeekdayOf`).
  int get firstWeekday => _firstWeekday();

  /// Whether a weekly report is being made now.
  bool get weeklyMaking => _weeklyMaking;

  /// The weekly report's choices changed: kept, and the next look timed again.
  void setWeekly(WeeklySettings settings) {
    store.change((now) => now.copyWith(weekly: now.weekly.copyWith(settings: settings)));
    _scheduleWeekly();
  }

  /// The last report, while its note is still in the library and out of the Trash.
  WeeklyReport? get weeklyReport {
    final report = state.weekly.report;
    if (report == null) return null;
    final note = library.noteOf(report.noteId);
    return note == null || trashedNote(note, trash.value) ? null : report;
  }

  /// A report made in the last week: the home card reads "This week" while there is one.
  WeeklyReport? get thisWeek {
    final report = weeklyReport;
    if (report == null || !on || !weeklySettings.on) return null;
    return _clock().difference(report.made) < const Duration(days: 7) ? report : null;
  }

  /// The AI the weekly report would ask, where its summary is on; null for the counts alone.
  CleanupAi? get weeklyAi => weeklySettings.ai ? ai : null;

  /// Whether the weekly report needs the person's yes before it spends their key: a cloud AI not yet allowed.
  bool get weeklyAsks {
    final ai = weeklyAi;
    return ai != null && !ai.local && !state.weekly.allowed.contains(ai.id);
  }

  /// The notes of the week from [start] the report's AI part reads (the week's, newest edit first) and those it must
  /// read again for a gist (no read yet, or words changed), at most [weeklyMostGists].
  ({List<WrappedNote> notes, List<WrappedNote> toGist}) _weeklyNotes(WeeklyCounts counts) {
    final byId = {for (final n in passNotes) n.id: n};
    final notes = [for (final id in counts.touched) ?byId[id]].take(weeklyMostGists).toList();
    return (notes: notes, toGist: notesToRead(notes, state.reads));
  }

  /// The counts of the week from [start], as the notes are now, against what the last report saw.
  WeeklyCounts weeklyCountsFor(DateTime start) => weeklyCounts(ownNotes, start: start, todosBefore: state.weekly.todos, revsBefore: state.weekly.revs, dismissed: state.dismissed, staleAfter: staleAfter);

  /// About what this week's report costs with the AI, for the page: "~6k tokens · about $0.02 a week".
  String? get weeklyCostWords {
    final ai = weeklyAi;
    if (ai == null) return null;
    final counts = weeklyCountsFor(weekStartOf(_clock(), firstWeekday));
    final (:notes, :toGist) = _weeklyNotes(counts);
    return weeklyEstimate(ai, toGist: toGist.length, notes: notes.length, todos: counts.unfinished.length + counts.todosOpen, pacing: _pacing).words;
  }

  /// The weekly report looked at (see weekly.dart): as the app opens, comes back, and every hour while it runs. The
  /// week due is made once: not when made here before, nor when its note is in the library already (made on another
  /// device and synced). A week missed is made at the next look. Answers the report made, if one was.
  Future<WeeklyReport?> lookWeekly() async {
    _scheduleWeekly();
    if (!on || !weeklySettings.on || _weeklyMaking || _running || !store.read || !_notesRead()) return null;
    final start = dueWeek(_clock(), weeklySettings, firstWeekday);
    if (start == null) return null;
    final key = weekKeyOf(start);
    if (state.weekly.made(key)) return null;
    final there = library.value.where((n) => weekOfNote(n) == key && !trashedNote(n, trash.value)).firstOrNull;
    if (there != null) {
      store.change((now) => now.copyWith(weekly: now.weekly.copyWith(weeks: _withWeek(now.weekly.weeks, key))));
      return null;
    }
    return makeWeekly(start);
  }

  List<String> _withWeek(List<String> weeks, String key) {
    final next = [...weeks.where((w) => w != key), key];
    return next.length > WeeklyState.mostWeeks ? next.sublist(next.length - WeeklyState.mostWeeks) : next;
  }

  void _scheduleWeekly() {
    _weeklyTimer?.cancel();
    if (!on || !weeklySettings.on) return;
    final now = _clock();
    final until = nextDue(now, weeklySettings, firstWeekday).difference(now);
    final wait = until.inMilliseconds.clamp(1000, const Duration(hours: 1).inMilliseconds);
    _weeklyTimer = Timer(Duration(milliseconds: wait), () => unawaited(lookWeekly()));
  }

  /// Makes the report of the week from [start] (see weekly.dart): the counts, the AI's part where it is on and
  /// allowed, the note filed in the reports' journal, and a notification where the device lets the app notify and the
  /// person asked for one. A week with nothing written or edited makes no note. Null when none was made.
  Future<WeeklyReport?> makeWeekly(DateTime start) async {
    if (_weeklyMaking) return null;
    final key = weekKeyOf(start);
    if (state.weekly.made(key)) return null;
    _weeklyMaking = true;
    notifyListeners();
    try {
      await readAis();
      final counts = weeklyCountsFor(start);
      final snapshot = weeklySnapshot(library.value.where((n) => !trashedNote(n, trash.value) && _own(n)).toList());
      if (counts.empty) {
        store.change((now) => now.copyWith(weekly: now.weekly.copyWith(weeks: _withWeek(now.weekly.weeks, key), todos: snapshot.todos, revs: snapshot.revs)));
        return null;
      }
      final ai = weeklyAi;
      final asked = ai != null && !weeklyAsks ? await _weeklyAsk(ai, counts) : null;
      // A second look meanwhile is held by [_weeklyMaking]; the week is written down as made with its note, so one
      // that failed to be filed is tried again at the next look.
      final noteId = await _fileReport(weeklyMarkdown(counts, ai: asked, aiName: ai?.name, titleOf: _titleOf), weekTitle(start));
      final report = WeeklyReport(week: key, noteId: noteId, made: _clock(), line: counts.line, summary: asked?.summary ?? '', steps: asked?.steps ?? const [], ai: asked != null && !asked.isEmpty, numbers: counts.numbers);
      store.change((now) => now.copyWith(weekly: now.weekly.copyWith(weeks: _withWeek(now.weekly.weeks, key), todos: snapshot.todos, revs: snapshot.revs, report: () => report)));
      track(MetricEvent.wrappedWeeklyMade, {'notes': countBucket(counts.written + counts.edited), 'todos': countBucket(counts.todosDone), 'steps': countBucket(report.steps.length)});
      await _notifyWeekly(report);
      return report;
    } catch (failure) {
      debugPrint('[glyph] Wrapped’s weekly report was not made: $failure');
      return null;
    } finally {
      _weeklyMaking = false;
      notifyListeners();
    }
  }

  String _titleOf(String id) {
    final note = library.noteOf(id);
    return note == null ? '' : noteTitle(note.body).trim();
  }

  /// The AI's part: gists for the week's notes that have none or changed, then the one small ask. Null where it
  /// failed or was stopped: the report is the counts alone.
  Future<WeeklyAi?> _weeklyAsk(CleanupAi ai, WeeklyCounts counts) async {
    final (:notes, :toGist) = _weeklyNotes(counts);
    final stop = _weeklyStop = WrappedStop();
    final job = _record.begin(wrappedWeeklyJobId, kind: JobKind.ai, title: 'Your week in notes', line: 'Writing with ${ai.name}', onStop: stop.stop, onOpen: onOpen, plugin: ai.plugin ?? wrappedId);
    try {
      if (toGist.isNotEmpty) {
        final read = await readNotes(
          toRead: toGist,
          ai: ai,
          pacing: _pacing,
          busy: _busyNow,
          stop: stop,
          wait: _wait,
          now: _clock,
          kept: (reads) => store.change((now) => now.copyWith(reads: {...now.reads, ...reads})),
        );
        if (read.end != PassEnd.done) {
          read.end == PassEnd.stopped ? job.stopped() : job.failed(read.problem ?? 'The AI didn’t answer.');
          return null;
        }
      }
      final todos = [...counts.unfinished];
      for (final row in todosOf(counts.touched)) {
        if (todos.length >= weeklyMostTodos) break;
        if (!todos.any((t) => t.key == row.key)) todos.add(row);
      }
      final asking = ai.ask(weeklySystem, weeklyPrompt(counts, notes, state.reads, todos), maxTokens: 900);
      final answer = readWeeklyAnswer(await asking.done, notes, todos);
      job.done(result: JobResult('Your week in notes is ready', action: 'View', onOpen: onOpen));
      return answer;
    } catch (failure) {
      job.failed('$failure'.replaceFirst('Exception: ', ''));
      return null;
    } finally {
      _weeklyStop = null;
    }
  }

  /// The open to-dos of [ids]' notes, for the AI to say which look finished.
  List<WeeklyTodo> todosOf(List<String> ids) => [
        for (final id in ids)
          if (library.noteOf(id) case final note?)
            for (final todo in openTodos(id, note.body))
              if (!state.dismissed.contains('todo:${todo.key}')) (key: todo.key, noteId: id, title: noteTitle(note.body).trim(), words: todo.words.trim()),
      ];

  /// The reports' journal: the one marked `wrapped: weekly`, made where there is none; then [body] as a new note, and
  /// its line added to the journal's index. Answers the report's id.
  Future<String> _fileReport(String body, String title) async {
    Note? journal = library.value.where((n) => isJournalBody(n.body) && frontMatterValue(n.body, weeklyJournalKey)?.trim() == 'weekly' && !trashedNote(n, trash.value)).firstOrNull;
    journal ??= await library.createNote(weeklyJournalBody());
    final made = await library.createNote(body);
    for (var tries = 0; tries < 3; tries += 1) {
      final now = library.noteOf(journal!.id) ?? journal;
      try {
        await library.update(now.id, withEntry(now.body, title), now.revision);
        break;
      } catch (_) {
        // Changed meanwhile (a sync, the journal open): read again and try once more.
        journal = await library.get(now.id) ?? now;
      }
    }
    return made.id;
  }

  Future<void> _notifyWeekly(WeeklyReport report) async {
    final host = _notices;
    if (host == null || !weeklySettings.notify) return;
    try {
      if (await host.state() == NoticesState.blocked) return;
      await host.post((id: 'wrapped-weekly-${report.week}', title: 'Your week in notes is ready', text: report.line.isEmpty ? null : report.line, link: 'ghostmd://note/${report.noteId}'));
    } catch (_) {
      // A phone that cannot post says nothing: the home card says it instead.
    }
  }

  /// The person's yes to spending their key each week ([weeklyAsks]), asked as the main pass asks (askJobCost, always
  /// the first time), and the last report given its AI part at once. Answers whether it was allowed.
  Future<bool> allowWeeklyAi(BuildContext context) async {
    await readAis();
    final ai = weeklyAi;
    if (ai == null) return false;
    final report = weeklyReport;
    final start = report == null ? weekStartOf(_clock(), firstWeekday) : weekOfKey(report.week)!;
    final counts = weeklyCountsFor(start);
    final (:notes, :toGist) = _weeklyNotes(counts);
    final cost = weeklyEstimate(ai, toGist: toGist.length, notes: notes.length, todos: counts.todosOpen, pacing: _pacing);
    if (!ai.local) {
      if (!context.mounted) return false;
      final yes = await askJobCost(context, JobEstimate(count: 1, one: 'report', many: 'reports', duration: const Duration(minutes: 1), cost: cost.words, asksAlways: true), title: 'Write your weekly report with ${ai.name}?');
      if (!yes) return false;
    }
    store.change((now) => now.copyWith(weekly: now.weekly.copyWith(allowed: {...now.weekly.allowed, ai.id})));
    if (report != null && !report.ai) await _addAiTo(report, ai);
    return true;
  }

  /// [report], made from the counts alone, given the AI's part: its note written over, the person's edits kept.
  Future<void> _addAiTo(WeeklyReport report, CleanupAi ai) async {
    final start = weekOfKey(report.week);
    if (start == null || _weeklyMaking) return;
    _weeklyMaking = true;
    notifyListeners();
    try {
      final counts = weeklyCountsFor(start).withNumbers(report.numbers);
      final asked = await _weeklyAsk(ai, counts);
      if (asked == null || asked.isEmpty) return;
      final note = await library.get(report.noteId);
      if (note == null) return;
      await library.update(note.id, withWeeklyAi(note.body, asked, titleOf: _titleOf), note.revision);
      store.change((now) => now.copyWith(weekly: now.weekly.copyWith(report: () => report.copyWith(summary: asked.summary, steps: asked.steps, ai: true))));
    } catch (failure) {
      debugPrint('[glyph] the weekly report’s summary was not added: $failure');
    } finally {
      _weeklyMaking = false;
      notifyListeners();
    }
  }

  /// View report: the note opened (the root's way), the report marked seen, and counted.
  void viewWeekly() {
    final report = weeklyReport;
    if (report == null) return;
    if (!report.viewed) store.change((now) => now.copyWith(weekly: now.weekly.copyWith(report: () => report.copyWith(viewed: true))));
    track(MetricEvent.wrappedWeeklyViewed, {'steps': countBucket(report.steps.length)});
    wrappedOpenNote?.call(report.noteId, null);
  }

  void _setStep(int index, WeeklyStep Function(WeeklyStep step) change) {
    final report = state.weekly.report;
    if (report == null || index < 0 || index >= report.steps.length) return;
    final steps = [...report.steps];
    steps[index] = change(steps[index]);
    store.change((now) => now.copyWith(weekly: now.weekly.copyWith(report: () => report.copyWith(steps: steps))));
  }

  /// Next step [index] done by Wrapped's own press: the to-dos checked off, the notes archived, the link added. Its
  /// record kept on the step, so Undo takes it back. A step to look at a note opens it.
  Future<WrappedDone> applyStep(int index) async {
    final step = weeklyReport?.steps.elementAtOrNull(index);
    if (step == null) return WrappedDone();
    final done = switch (step.kind) {
      WeeklyStepKind.checkOff => await checkOff([
          for (final row in todos)
            if (step.todos.contains(row.todo.key)) row.todo,
        ]),
      WeeklyStepKind.archive => await archive(step.notes),
      WeeklyStepKind.link => await apply(WrappedSuggestion(kind: SuggestionKind.link, notes: step.notes, why: step.words)),
      WeeklyStepKind.look => WrappedDone(),
    };
    if (step.kind == WeeklyStepKind.look && step.notes.isNotEmpty) wrappedOpenNote?.call(step.notes.first, null);
    if (done.record != null) _setStep(index, (s) => s.copyWith(record: () => done.record!.id));
    return done;
  }

  /// Next step [index]'s press taken back whole.
  Future<String> undoStep(int index) async {
    final record = weeklyReport?.steps.elementAtOrNull(index)?.record;
    if (record == null) return 'Nothing to undo.';
    final said = await undo(record);
    _setStep(index, (s) => s.copyWith(record: () => null));
    return said;
  }

  /// Next step [index] put away.
  void dismissStep(int index) => _setStep(index, (s) => s.copyWith(dismissed: true));

  @override
  void dispose() {
    _weeklyTimer?.cancel();
    _weeklyStop?.stop();
    _stop?.stop();
    store.removeListener(notifyListeners);
    _switches?.removeListener(_switched);
    super.dispose();
  }
}

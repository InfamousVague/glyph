/// A cleanup as the app holds it (docs/CLEANUP.md): the folder chosen, the AI, the passes, the run in flight, the plan
/// under review and what was ticked, the last run applied, and the records. The plugin's page (cleanup_pane.dart) draws
/// it and the root makes it once the library is read ([CleanupService.current]); a folder's menu chooses its folder and
/// opens the page.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../activity/activity_cost.dart' show askJobCost;
import '../../assistant/assistant.dart' show AssistantChoice;
import '../../core/background_jobs.dart';
import '../../core/library.dart';
import '../../core/trash.dart';
import '../../core/workspaces.dart';
import '../types.dart' show PluginStorage;
import 'ai.dart';
import 'apply.dart';
import 'manifest.dart';
import 'plan.dart';
import 'records.dart';
import 'run.dart';

/// Where a cleanup is.
enum CleanupStage {
  /// Choosing the folder, the AI and the passes.
  choosing,

  /// Asking the AI, on the Activity tray.
  running,

  /// The plan on the review screen.
  review,

  /// Applying the ticked items.
  applying,

  /// Applied: what was done, with Undo.
  applied,
}

/// See the library doc.
class CleanupService extends ChangeNotifier {
  CleanupService({
    required this.library,
    required this.workspaces,
    required this.trash,
    this.choice,
    CleanupRecords? records,
    PluginStorage? storage,
    bool Function()? localOnly,
    Future<List<CleanupAi>> Function()? ais,
    Activity? activity,
    DateTime Function()? clock,
    this.onOpen,
  })  : records = records ?? CleanupRecords(storage: storage),
        _storage = storage,
        _localOnly = localOnly ?? (() => false),
        _ais = ais,
        _activity = activity,
        _clock = clock ?? DateTime.now {
    final kept = storage?.get<Object?>(cleanupOptionsKey, null);
    if (kept is Map) {
      _options = CleanupOptions.fromJson(kept['options']);
      if (kept['ai'] is String) _aiChosen = kept['ai'] as String;
    }
    this.records.addListener(notifyListeners);
  }

  /// The app's, once the root has made it; null in a build or a test without one.
  static CleanupService? current;

  final NoteLibrary library;
  final WorkspaceStore workspaces;
  final Trash trash;

  /// The app's choice of AI, for the AIs connected and the one chosen to begin with.
  final AssistantChoice? choice;
  final CleanupRecords records;
  final PluginStorage? _storage;
  final bool Function() _localOnly;
  final Future<List<CleanupAi>> Function()? _ais;
  final Activity? _activity;
  final DateTime Function() _clock;

  /// Opens the plugin's page: the tray's Open.
  final VoidCallback? onOpen;

  Activity get _record => _activity ?? activity;

  String? _folderId;
  CleanupOptions _options = const CleanupOptions();
  String? _aiChosen;
  List<CleanupAi> _connected = const [];
  bool _aisRead = false;
  CleanupStage _stage = CleanupStage.choosing;
  CleanupPlan? _plan;
  Set<String> _ticked = const {};
  CleanupApplied? _last;
  String? _problem;
  CleanupStop? _stop;
  CleanupEstimate? _estimate;
  String? _progress;

  String? get folderId => _folderId;
  CleanupOptions get options => _options;
  List<CleanupAi> get ais => _connected;
  bool get aisRead => _aisRead;
  CleanupStage get stage => _stage;
  CleanupPlan? get plan => _plan;
  Set<String> get ticked => _ticked;
  CleanupApplied? get last => _last;
  String? get problem => _problem;
  CleanupEstimate? get estimate => _estimate;

  /// What the run is doing now, for the page: "Reading 40 of 120 notes with Claude".
  String? get progress => _progress;
  bool get localOnly => _localOnly();

  /// The folder chosen, as the list has it now.
  Workspace? get folder => _folderId == null ? null : workspaces.value.list.where((w) => w.id == _folderId).firstOrNull;

  /// The AI that will be asked: the one chosen where it is connected, else the default ([defaultAiId]).
  CleanupAi? get ai {
    final id = defaultAiId(_connected, choice: choice, chosen: _aiChosen, localOnly: localOnly);
    return _connected.where((a) => a.id == id).firstOrNull;
  }

  /// How many notes a run would read in the folder now: under it too, out of the Trash and the Archive.
  int get noteCount {
    final id = _folderId;
    if (id == null) return 0;
    final spaces = workspaces.value;
    final family = workspaceFamily(spaces.list, id).toSet();
    final held = trash.value;
    return library.value.where((note) => family.contains(spaces.of[note.id]) && !trashedNote(note, held) && (note.archivedAt == null || note.archivedAt == 0)).length;
  }

  void _keep() => _storage?.set(cleanupOptionsKey, {'options': _options.toJson(), 'ai': ?_aiChosen});

  /// Reads which AIs can be asked now: as the page opens, and when Local only or a plugin changes.
  Future<void> readAis() async {
    try {
      _connected = await (_ais ?? () => connectedAis(choice: choice, localOnly: localOnly))();
    } catch (_) {
      _connected = const [];
    }
    _aisRead = true;
    notifyListeners();
  }

  /// Chooses the folder to clean up: a folder's menu, or the page's picker. A plan for another folder is put away.
  void choose(String folderId) {
    if (_stage == CleanupStage.running || _stage == CleanupStage.applying) return;
    if (_folderId != folderId) {
      _plan = null;
      _ticked = const {};
      if (_stage == CleanupStage.review) _stage = CleanupStage.choosing;
    }
    _folderId = folderId;
    _problem = null;
    notifyListeners();
  }

  void chooseAi(String id) {
    _aiChosen = id;
    _keep();
    notifyListeners();
  }

  void setPass(CleanupPass pass, bool on) {
    _options = _options.toggled(pass, on);
    _keep();
    notifyListeners();
  }

  void setDeeper(bool on) {
    _options = _options.copyWith(deeper: on);
    _keep();
    notifyListeners();
  }

  void setRewrite(bool on) {
    _options = _options.copyWith(rewrite: on);
    _keep();
    notifyListeners();
  }

  /// Why Look for changes cannot run now, or null.
  String? get cannotLook {
    if (_folderId == null || folder == null) return 'Choose a folder first.';
    if (_options.passes.isEmpty) return 'Turn on at least one thing to do.';
    if (_aisRead && ai == null) return localOnly ? 'Local only is on, and there is no model on this device yet.' : 'No AI is connected yet.';
    if (noteCount == 0) return '${folder!.name} has no notes in it.';
    return null;
  }

  /// Looks at the folder (docs/CLEANUP.md, "Large folders"): the estimate, asked about where it is a big run, then the
  /// run on the Activity tray with Stop, then the plan for review. Answers whether it ran. [context] is where the
  /// estimate is asked; without one a big run is not started.
  Future<bool> look([BuildContext? context]) async {
    if (_stage == CleanupStage.running || _stage == CleanupStage.applying) return false;
    // Read again as it starts, so a plugin switched off or Local only turned on since the page opened holds.
    await readAis();
    final ai = this.ai;
    final folderId = _folderId;
    if (ai != null && localOnly && !ai.local) {
      _problem = 'Local only is on: only the model on this device may read your notes.';
      notifyListeners();
      return false;
    }
    if (ai == null || folderId == null || cannotLook != null) {
      _problem = cannotLook;
      notifyListeners();
      return false;
    }
    final scope = cleanupScope(folderId: folderId, workspaces: workspaces, library: library, trash: trash);
    if (scope == null) return false;
    final estimate = _estimate = cleanupEstimate(scope, ai, _options);
    if (estimate.job.asks) {
      final yes = context != null && context.mounted && await askJobCost(context, estimate.job, title: 'Clean up ${scope.root.name} with ${ai.name}?');
      if (!yes) {
        notifyListeners();
        return false;
      }
    }
    final stop = _stop = CleanupStop();
    _stage = CleanupStage.running;
    _problem = null;
    _plan = null;
    _last = null;
    _progress = 'Reading with ${ai.name}';
    notifyListeners();
    final job = _record.begin(
      cleanupJobId(folderId),
      kind: JobKind.ai,
      title: 'Cleaning up ${scope.root.name}',
      line: 'Reading with ${ai.name}',
      onStop: this.stop,
      onOpen: onOpen,
      personStarted: true,
      estimate: estimate.job,
      plugin: ai.plugin ?? cleanupManifest.id,
    );
    void told(int done, int total, String line) {
      job.progress(done: done, total: total, unit: 'notes', line: line);
      _progress = '$line: $done of $total ${total == 1 ? 'note' : 'notes'}';
      notifyListeners();
    }

    try {
      final plan = await runCleanup(scope: scope, ai: ai, options: _options, progress: told, stop: stop, now: _clock);
      _plan = plan;
      _ticked = plan.startTicked;
      _stage = CleanupStage.review;
      final count = plan.items.length;
      if (plan.failures.length == plan.asks && plan.asks > 0 && count == 0) {
        job.failed(plan.failures.first);
      } else if (stop.stopped) {
        job.stopped(tally: JobTally('suggestion', 'suggestions', count));
      } else {
        job.done(result: JobResult(count == 0 ? 'Nothing to change' : '$count ${count == 1 ? 'suggestion' : 'suggestions'} to review', action: 'Review', onOpen: onOpen), tally: JobTally('suggestion', 'suggestions', count));
      }
    } catch (failure) {
      _stage = CleanupStage.choosing;
      _problem = '$failure';
      job.failed('$failure');
    } finally {
      _stop = null;
      _progress = null;
      notifyListeners();
    }
    return true;
  }

  /// Stops the run in flight; what the finished asks found is kept for review.
  void stop() => _stop?.stop();

  void tick(String id, bool on) {
    final plan = _plan;
    if (plan == null) return;
    final next = {..._ticked};
    on ? next.add(id) : next.remove(id);
    final item = plan.byId(id);
    // A new folder's moves follow it out; a move into it ticks it back in.
    if (item is NewFolderItem && !on) next.removeAll(plan.movesInto(id).map((m) => m.id));
    if (item is MoveItem && on && item.intoNew) next.add(item.to);
    _ticked = next;
    notifyListeners();
  }

  /// Every item of [pass] ticked or not.
  void tickPass(CleanupPass pass, bool on) {
    final plan = _plan;
    if (plan == null) return;
    final ids = plan.of(pass).map((i) => i.id);
    _ticked = on ? {..._ticked, ...ids} : ({..._ticked}..removeAll(ids));
    notifyListeners();
  }

  /// Applies the ticked items, or with [all] every item: then the record is kept, and Undo is offered.
  Future<CleanupApplied?> apply({bool all = false}) async {
    final plan = _plan;
    if (plan == null || _stage != CleanupStage.review) return null;
    _stage = CleanupStage.applying;
    notifyListeners();
    try {
      final done = await applyCleanup(plan: plan, ticked: all ? {for (final i in plan.items) i.id} : _ticked, library: library, workspaces: workspaces, trash: trash, aiName: ai?.name ?? '', now: _clock());
      if (done.record.changes.isNotEmpty) records.add(done.record);
      _last = done;
      _plan = null;
      _ticked = const {};
      _stage = CleanupStage.applied;
      return done;
    } catch (failure) {
      _problem = '$failure';
      _stage = CleanupStage.review;
      return null;
    } finally {
      notifyListeners();
    }
  }

  /// Takes the run [recordId] back, whole.
  Future<CleanupUndone?> undo(String recordId) async {
    final record = records.byId(recordId);
    if (record == null || record.undone) return null;
    final undone = await undoCleanup(record: record, library: library, workspaces: workspaces, trash: trash);
    records.markUndone(recordId);
    return undone;
  }

  /// Puts the plan away; nothing is changed.
  void discard() {
    _plan = null;
    _ticked = const {};
    _stage = CleanupStage.choosing;
    notifyListeners();
  }

  /// Back to choosing, after a run was applied.
  void again() {
    _last = null;
    _stage = CleanupStage.choosing;
    notifyListeners();
  }

  @override
  void dispose() {
    records.removeListener(notifyListeners);
    _stop?.stop();
    super.dispose();
  }
}

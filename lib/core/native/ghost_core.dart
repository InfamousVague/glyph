/// The app's Rust core (native/, docs/STAGE3.md), as the app holds it: what `@tauri-apps/api`'s `invoke` was to
/// the web app. [GhostCore.invoke] is a [CoreInvoke] (core.dart), so everything written against that typedef
/// takes `core.invoke` and a test takes a fake.
///
/// What differs from the page's `invoke`:
///
/// - **It has to be opened, and told where the files are.** Tauri loaded its Rust with the app and resolved the
///   directories itself; here [GhostCore.open] starts the isolate that owns the library (ghost_worker.dart) and
///   [init] hands Rust the two directories device_paths.dart found. Nothing but `new_id` answers before `init`.
/// - **Commands are answered in the order they were asked**, one at a time, off the isolate that draws.
/// - **An error is a [CoreError]** with the sentence Rust's `Err(String)` carried, where the page's promise
///   rejected with the bare string.
/// - **Events** are one stream, [GhostCore.events] (events.dart), where the page called `listen` per name.
/// - **A long job** is a command that answers `{id}` at once and reports by events: [GhostCore.startJob].
///
/// ```dart
/// final core = await GhostCore.open();
/// final paths = await DevicePaths.find();
/// await core.init(dataDir: paths.dataDir, cacheDir: paths.cacheDir);
/// final notes = await core.invoke('list_notes') as List<Object?>;
/// ```
library;

import 'dart:async';
import 'dart:isolate';

import 'core.dart';
import 'events.dart';
import 'ghost_worker.dart' if (dart.library.js_interop) 'ghost_worker_web.dart';

class GhostCore {
  GhostCore._(this._isolate, this._requests, this._answers);

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _answers;

  /// The requests not yet answered, by the id each was sent with.
  final Map<int, Completer<Object?>> _waiting = {};
  int _nextId = 0;
  bool _closed = false;
  final Completer<void> _ended = Completer<void>();
  final StreamController<CoreEvent> _events = StreamController<CoreEvent>.broadcast(sync: true);

  /// Everything the core says without being asked (native/src/events.rs), in the order it arrived: a broadcast
  /// stream, so each screen filters for the names it wants. An event emitted while nobody listens is gone, as
  /// a Tauri event was. Closed when the worker ends.
  Stream<CoreEvent> get events => _events.stream;

  /// Starts a long job: [command] must be one that answers `{id: ...}` at once (native/src/work.rs). The
  /// [CoreJob] has the job's own events from the first one and a future for its end. Throws [CoreError] when
  /// the command itself refuses.
  Future<CoreJob> startJob(String command, [Map<String, Object?> args = const {}]) async {
    // Listening from before the command is sent: the job's thread may speak before the id has been read here.
    final early = <CoreEvent>[];
    String? id;
    final mine = StreamController<CoreEvent>();
    final done = Completer<Object?>();
    late final StreamSubscription<CoreEvent> heard;
    void take(CoreEvent event) {
      if (event.jobId != id) return;
      if (event.event != jobEnd) {
        mine.add(event);
        return;
      }
      heard.cancel();
      mine.close();
      final said = event.map;
      if (said.containsKey('err')) {
        done.completeError(CoreError('${said['err']}'));
      } else {
        done.complete(said['ok']);
      }
    }

    heard = _events.stream.listen(
      (event) => id == null ? early.add(event) : take(event),
      onDone: () {
        mine.close();
        if (!done.isCompleted) done.completeError(const CoreError('Ghost.md\'s core stopped before the job ended.'));
      },
    );
    // A job nobody awaits the end of must not be an unhandled error.
    done.future.ignore();
    try {
      final answer = await invoke(command, args);
      if (answer case {'id': final String jobId}) {
        id = jobId;
      } else {
        throw CoreError('$command did not answer with a job\'s id.');
      }
    } on Object {
      await heard.cancel();
      // Not awaited: with nobody listening, a controller's close never completes.
      unawaited(mine.close());
      rethrow;
    }
    final jobId = id;
    early.forEach(take);
    early.clear();
    return CoreJob(jobId, mine.stream, done.future, () async => await invoke('job_cancel', {'id': jobId}) as bool);
  }

  /// Starts the worker isolate and has it load the library: `libghost_core.so` from the APK by default, or the
  /// file at [libraryPath] (a test's `native/target/debug/libghost_core.dylib`). Throws [CoreError] when the
  /// library cannot be loaded, with the loader's reason.
  ///
  /// [hears] is whether the core's events come to this one ([events], and so every [startJob]). The app's own
  /// core hears; a second one opened beside it for long calls must be opened with `hears: false`, since the core
  /// has one listener and the last worker to ask for it takes it from the first (ghost_worker.dart's header).
  static Future<GhostCore> open({String? libraryPath, bool hears = true}) async {
    final answers = ReceivePort('ghost core answers');
    final first = Completer<Object?>();
    GhostCore? core;
    answers.listen((message) {
      if (!first.isCompleted) {
        first.complete(message);
      } else {
        core?._answered(message);
      }
    });
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn<GhostWorkerStart>(
        ghostWorkerMain,
        (answers.sendPort, libraryPath, hears),
        debugName: 'ghost core',
        // `null` when the worker ends for any reason, its own close included.
        onExit: answers.sendPort,
        errorsAreFatal: true,
      );
    } on Object {
      answers.close();
      rethrow;
    }
    final said = await first.future;
    if (said is! SendPort) {
      answers.close();
      throw CoreError(said is String ? said : 'Ghost.md\'s core could not be started.');
    }
    return core = GhostCore._(isolate, said, answers);
  }

  /// Asks the core: a [CoreInvoke]. The commands and their arguments are docs/STAGE3.md's, by the names and
  /// camelCase keys the web page used. Completes with the decoded answer, or throws [CoreError].
  Future<Object?> invoke(String command, [Map<String, Object?> args = const {}]) {
    if (_closed) return Future.error(CoreError('Ghost.md\'s core is closed, so it cannot answer $command.'));
    final id = _nextId++;
    final answer = Completer<Object?>();
    _waiting[id] = answer;
    try {
      _requests.send([id, command, args]);
    } on Object catch (e) {
      // Arguments an isolate cannot be sent: not JSON either.
      _waiting.remove(id);
      return Future.error(CoreError('Ghost.md\'s core could not be asked $command: $e'));
    }
    return answer.future;
  }

  /// Opens the library in [dataDir] (`<dataDir>/Library`, or the folder `library-root.json` names), as the Tauri
  /// app's launch did. Safe to ask again with the same directories; a different [dataDir] is refused while the
  /// process lives, since one process has one library.
  Future<void> init({required String dataDir, required String cacheDir}) async {
    await invoke('init', {'dataDir': dataDir, 'cacheDir': cacheDir});
  }

  /// A fresh note id, minted by Rust (`note::new_id`, a UUID v4): the app's ids are file-name safe by
  /// construction (`fsx::plain_id`).
  Future<String> newId() async => await invoke('new_id') as String;

  /// Ends the worker once everything already asked has been answered. Anything asked after this throws. The
  /// library itself stays loaded and open in the process: a [GhostCore] opened later carries on with it.
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _requests.send(null);
    }
    return _ended.future;
  }

  void _answered(Object? message) {
    if (message == null) {
      // The worker has ended. After a close nothing is waiting; after a crash everything is.
      _closed = true;
      _answers.close();
      _events.close();
      final lost = _waiting.values.toList();
      _waiting.clear();
      for (final answer in lost) {
        answer.completeError(const CoreError('Ghost.md\'s core stopped before it answered.'));
      }
      if (!_ended.isCompleted) _ended.complete();
      return;
    }
    if (message case [final String event, final payload]) {
      if (!_events.isClosed) _events.add(CoreEvent(event, payload));
      return;
    }
    final [id as int, ok as bool, value] = message as List<Object?>;
    final answer = _waiting.remove(id);
    if (answer == null) return;
    if (ok) {
      answer.complete(value);
    } else {
      answer.completeError(CoreError(value as String));
    }
  }

  /// The worker, for a debugger's list of isolates.
  String? get debugName => _isolate.debugName;
}

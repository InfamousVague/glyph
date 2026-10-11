import 'dart:async';

import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;

/// The native capture as a test speaks for it: the stand-in the web's tests make of Tauri's `invoke` and of
/// `listenTo` (core/events.ts). Each command is answered by what the test put in [answers] under the web's command
/// name, and recorded in [invoked] with the web's arguments; a command with no answer rejects, as the web's stand-in
/// does. [say] speaks as Rust.
class FakeCaptureBackend implements CaptureBackend {
  /// What Rust would answer, by the web's command name. An answer may throw, and may be a future.
  final Map<String, FutureOr<Object?> Function(Map<String, Object?>? args)> answers = {};

  /// Every command asked, in order: `{'command': …, 'args': …}`, the args null where the web passes none.
  final List<Map<String, Object?>> invoked = [];

  final List<MultiStreamController<CaptureEvent>> _listeners = [];

  /// How many listeners have stopped listening, ever: the web's `unlistened`, counted.
  int unlistened = 0;

  /// How many are listening now.
  int get listening => _listeners.length;

  @override
  Stream<CaptureEvent> get events => Stream<CaptureEvent>.multi((controller) {
        _listeners.add(controller);
        controller.onCancel = () {
          if (_listeners.remove(controller)) unlistened += 1;
        };
      }, isBroadcast: true);

  /// Speaks as Rust: every listener hears [event] before this returns.
  void say(CaptureEvent event) {
    for (final listener in _listeners.toList()) {
      listener.addSync(event);
    }
  }

  /// A new test: nothing asked yet, nothing answered, and nobody a test before left listening.
  void reset() {
    answers.clear();
    invoked.clear();
    _listeners.clear();
    unlistened = 0;
  }

  /// Every call of [command], in order.
  List<Map<String, Object?>> calls(String command) => [
        for (final call in invoked)
          if (call['command'] == command) call,
      ];

  Future<Object?> _invoke(String command, [Map<String, Object?>? args]) async {
    invoked.add({'command': command, 'args': args});
    final answer = answers[command];
    if (answer == null) throw Exception('no answer for $command');
    return await answer(args);
  }

  @override
  Future<void> start() => _invoke('capture_start');

  @override
  Future<void> push(String pcm) => _invoke('capture_push', {'pcm': pcm});

  @override
  Future<void> rewind(int toMs) => _invoke('capture_rewind', {'toMs': toMs});

  @override
  Future<CaptureStopped?> stop([StopOptions? options]) async =>
      await _invoke('capture_stop', options == null ? null : {'recordAs': options.recordAs, 'append': options.append}) as CaptureStopped?;

  @override
  Future<void> cancel() => _invoke('capture_cancel');

  @override
  Future<ModelStatus> modelStatus() async => await _invoke('capture_model_status') as ModelStatus;

  @override
  Future<ModelStatus> fetchModel() async => await _invoke('capture_fetch_model') as ModelStatus;

  @override
  Future<int?> reassignRecording({required String fromId, required String toId, required bool append}) async =>
      await _invoke('capture_reassign_recording', {'fromId': fromId, 'toId': toId, 'append': append}) as int?;

  @override
  Future<void> discardRecording({required String id}) => _invoke('capture_discard_recording', {'id': id});

  @override
  Future<({bool present, int bytes})> refineModelStatus() async => await _invoke('capture_refine_model_status') as ({bool present, int bytes});

  @override
  Future<({bool present, int bytes})> fetchRefineModel() async => await _invoke('capture_fetch_refine_model') as ({bool present, int bytes});

  @override
  Future<List<Segment>> refine({required String id, required int fromMs, required String promptTail}) async =>
      await _invoke('capture_refine', {'id': id, 'fromMs': fromMs, 'promptTail': promptTail}) as List<Segment>;
}

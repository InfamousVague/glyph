/// The language model on the device: [AiBackend] (backend.dart) over the Rust core, which is llama.cpp in
/// native/src/ai.rs and the write-up's files in native/src/recording.rs. What `invoke('ai_generate', …)` and
/// `listenTo('ai://progress', …)` were to the web app's `core/ai.ts`.
///
/// One method a command, with the web's arguments; [listen] for its events, by the web's names. A command that is
/// a long job in the core (a download, a run, a spoken command) is awaited to its end here, so each method resolves
/// when the Tauri command did and with what it did. A refusal is thrown as the core's own sentence ([CoreError]),
/// "cancelled" for a run that was stopped.
///
/// Everything runs on this device: no cloud model, no cloud speech. The one thing that crosses a network is a
/// model's download, from [mirrors].
///
/// ```dart
/// useAiBackend(NativeAiBackend(core));   // at launch, once the core is open
/// ```
library;

import 'dart:async';

import '../core/native/ghost_core.dart';
import 'backend.dart';

class NativeAiBackend implements AiBackend {
  NativeAiBackend(this.core, {this.mirrors});

  final GhostCore core;

  /// The base URLs a model is fetched from, each tried as `<mirror>/<file>`: null for the web app's own (attack.fm,
  /// then Hugging Face at the pinned revision), or a list that is then the WHOLE list.
  final List<String>? mirrors;

  Future<Object?> _job(String command, [Map<String, Object?> args = const {}]) async => (await core.startJob(command, args)).done;

  Map<String, Object?> _map(Object? json) => (json as Map).cast<String, Object?>();

  @override
  bool get available => true;

  /// `native_status`: what the core's voice and AI commands promise, as the Tauri app's generation that had them
  /// all (native/src/ai.rs `NATIVE_GENERATION`).
  @override
  Future<int> nativeGeneration() async => (_map(await core.invoke('native_status'))['nativeGeneration'] as num?)?.toInt() ?? 0;

  @override
  Future<String> binaryVersion() async => _map(await core.invoke('native_status'))['nativeVersion'] as String? ?? '';

  @override
  Future<AiDevice> device() async => AiDevice.fromJson(_map(await core.invoke('ai_device')));

  @override
  Future<List<ModelInfo>> models() async => [for (final model in await core.invoke('ai_models') as List) ModelInfo.fromJson(_map(model))];

  @override
  Future<ModelInfo> fetchModel(String id) async => ModelInfo.fromJson(_map(await _job('ai_fetch_model', {'id': id, if (mirrors != null) 'mirrors': mirrors})));

  @override
  Future<ModelInfo> deleteModel(String id) async => ModelInfo.fromJson(_map(await core.invoke('ai_delete_model', {'id': id})));

  @override
  Future<Output> generate(GenerateRequest request) async => Output.fromJson(_map(await _job('ai_generate', {'request': request.toJson()})));

  @override
  Future<Object?> inferCommand(InferCommandRequest request) => _job('ai_infer_command', {'request': request.toJson()});

  @override
  Future<bool> cancel(String id) async => await core.invoke('ai_cancel', {'id': id}) == true;

  @override
  Future<void> unload() => core.invoke('ai_unload');

  @override
  Future<void> keepJobConfig(JobConfig config) => core.invoke('ai_keep_job_config', {'config': config.toJson()});

  @override
  void Function() listen(String event, void Function(Object? payload) handler) {
    final heard = core.events.where((said) => said.event == event).listen((said) => handler(said.payload));
    return () => unawaited(heard.cancel());
  }

  // ---- a meeting's write-up and its tapes (native/src/recording.rs): not part of [AiBackend], whose web twin
  // kept them in `core/recordings.ts`; here until that file's port asks for them. ------------------------------------

  /// `recording_job_state`: every write-up, as `{id, title, phase, waitingFor, percent, error, updatedAt}`.
  Future<List<Map<String, Object?>>> recordingJobState() async => [for (final job in await core.invoke('recording_job_state') as List) _map(job)];

  /// `recording_result_take { id }`: `{summary, model, transcriptChars, finishedAt}` once, or null.
  Future<Map<String, Object?>?> recordingResultTake(String id) async {
    final result = await core.invoke('recording_result_take', {'id': id});
    return result == null ? null : _map(result);
  }

  /// `recording_digest { id }`: `{sha256, bytes}` of the note's tape, or null when it has none here.
  Future<({String sha256, int bytes})?> recordingDigest(String id) async {
    final digest = await _job('recording_digest', {'id': id});
    if (digest == null) return null;
    final said = _map(digest);
    return (sha256: said['sha256'] as String, bytes: (said['bytes'] as num).toInt());
  }

  /// `recording_delete { ids }`: the tapes and their write-up files go; `{removed, freedBytes}`.
  Future<({List<String> removed, int freedBytes})> recordingDelete(List<String> ids) async {
    final said = _map(await core.invoke('recording_delete', {'ids': ids}));
    return (removed: List<String>.from(said['removed'] as List), freedBytes: (said['freedBytes'] as num).toInt());
  }
}

// A scripted engine for the AI's tests: the web tests' `vi.mock('../core/tauri.ts')` and `vi.mock('../core/events.ts')`
// in one object.
//
// A web test set `answers.set('ai_generate', …)` to a value or a function of the arguments, read `invoked` for what
// was asked, and called `listeners.get('ai://progress')?.(…)` to say what Rust reported. This is the same, by the
// same command and event names, so a case ports line for line:
//
//     final engine = FakeAiBackend();
//     useAiBackend(engine);
//     engine.answers['ai_generate'] = (Object? args) {
//       final id = ((args as Map)['request'] as Map)['id'];
//       engine.emit('ai://progress', {'id': id, 'phase': 'generating', 'partial': 'T'});
//       return {'text': 'Tidied.'};
//     };
//
// An answer is a value, or a function of the arguments (`{'id': …}`, `{'request': {…}}`, `{'config': {…}}`: what the
// page passed `invoke`), which may throw and may answer a Future. Values are JSON as Rust serialises it (maps and
// lists), or the typed thing itself (an `Output`, a `ModelInfo`). [script] is the short way to a run that streams.

import 'dart:async';

import 'package:ghost_md/ai/backend.dart';

/// One command as it was asked: the web tests' `{ command, args }`.
typedef Invoked = ({String command, Object? args});

class FakeAiBackend implements AiBackend {
  FakeAiBackend({this.native = true, this.generation = 0, this.version = ''});

  /// `isTauri()`: false is a browser.
  bool native;

  /// What `ota_status` says the binary's native generation is.
  int generation;

  /// What `ota_status` says the binary's version is.
  String version;

  /// Every command asked, in order.
  final List<Invoked> invoked = [];

  /// Each command's answer by name: a value, or a function of the arguments that may throw.
  final Map<String, Object?> answers = {};

  /// Every listener attached, by event.
  final Map<String, List<void Function(Object? payload)>> listeners = {};

  /// What had been invoked at the moment each listener was attached.
  final List<List<String>> invokedWhenListening = [];

  /// How many listeners have been detached.
  int unlistened = 0;

  /// The commands asked, by name alone.
  List<String> get commands => [for (final call in invoked) call.command];

  /// The calls of one command.
  List<Invoked> calls(String command) => [for (final call in invoked) if (call.command == command) call];

  /// The `request` of every `ai_generate`, in order.
  List<Map<String, Object?>> get requests => [
        for (final call in calls('ai_generate')) ((call.args as Map)['request'] as Map).cast<String, Object?>(),
      ];

  /// Says what Rust reported: every listener of [event] is given [payload].
  void emit(String event, Object? payload) {
    for (final handler in [...?listeners[event]]) {
      handler(payload);
    }
  }

  /// Whether anything is listening to [event] now.
  bool listening(String event) => listeners[event]?.isNotEmpty ?? false;

  /// Makes `ai_generate` a run that reports each of [partials] as a `generating` progress under its own id and then
  /// answers [output] (a JSON map, an [Output], or just its text); [thinking] marks the reports and the output so.
  void script(Object output, {List<String> partials = const [], bool? thinking}) {
    answers['ai_generate'] = (Object? args) {
      final id = ((args as Map)['request'] as Map)['id'];
      var n = 0;
      for (final partial in partials) {
        n += 1;
        emit(progressEvent, {
          'id': id,
          'phase': 'generating',
          'promptTokens': 3,
          'promptTokensDone': 3,
          'outputTokens': n,
          'tokensPerSecond': 9,
          'elapsedMs': 5 * n,
          'partial': partial,
          'thinking': ?thinking,
        });
      }
      if (output is String) return {'text': output, 'thinking': ?thinking};
      return output;
    };
  }

  Future<Object?> _invoke(String command, [Object? args]) async {
    invoked.add((command: command, args: args));
    final answer = answers[command];
    if (answer is Function) {
      return await (args == null && answer is Object? Function() ? answer() : (answer as dynamic)(args));
    }
    return answer;
  }

  static Map<String, Object?> _json(Object? value) => (value as Map).cast<String, Object?>();

  @override
  bool get available => native;

  @override
  Future<int> nativeGeneration() async {
    final status = await _invoke('ota_status');
    return status is Map ? (status['nativeGeneration'] as num?)?.toInt() ?? 0 : generation;
  }

  @override
  Future<String> binaryVersion() async {
    final status = await _invoke('ota_status');
    return status is Map ? status['nativeVersion'] as String? ?? '' : version;
  }

  @override
  Future<AiDevice> device() async {
    final answer = await _invoke('ai_device');
    return answer is AiDevice ? answer : AiDevice.fromJson(answer == null ? const {} : _json(answer));
  }

  @override
  Future<List<ModelInfo>> models() async {
    final answer = await _invoke('ai_models');
    return [
      for (final one in (answer as List? ?? const [])) one is ModelInfo ? one : ModelInfo.fromJson(_json(one)),
    ];
  }

  ModelInfo _model(Object? answer, String id) => answer is ModelInfo ? answer : ModelInfo.fromJson(answer == null ? {'id': id} : _json(answer));

  @override
  Future<ModelInfo> fetchModel(String id) async => _model(await _invoke('ai_fetch_model', {'id': id}), id);

  @override
  Future<ModelInfo> deleteModel(String id) async => _model(await _invoke('ai_delete_model', {'id': id}), id);

  @override
  Future<Output> generate(GenerateRequest request) async {
    final answer = await _invoke('ai_generate', {'request': request.toJson()});
    if (answer is Output) return answer;
    if (answer is String) return Output(text: answer);
    return Output.fromJson(answer == null ? const {} : _json(answer));
  }

  @override
  Future<Object?> inferCommand(InferCommandRequest request) => _invoke('ai_infer_command', {'request': request.toJson()});

  @override
  Future<bool> cancel(String id) async => await _invoke('ai_cancel', {'id': id}) == true;

  @override
  Future<void> unload() async => _invoke('ai_unload');

  @override
  Future<void> keepJobConfig(JobConfig config) async => _invoke('ai_keep_job_config', {'config': config.toJson()});

  @override
  void Function() listen(String event, void Function(Object? payload) handler) {
    (listeners[event] ??= []).add(handler);
    invokedWhenListening.add(commands);
    return () {
      if (listeners[event]?.remove(handler) ?? false) unlistened += 1;
    };
  }
}

/// The formatting model on the phone: which ones there are, which are here, getting one, and running it. A port of
/// `src/app/core/ai.ts`, with `core/nativeGeneration.ts`'s two questions beside it.
///
/// Everything runs on the device (Matt: "the idea is that everything on here will be on device"). The catalogue's
/// bytes and hashes live in Rust (`src-tauri/src/llm/model.rs`); the names and the words a person reads live here,
/// keyed by the same ids. The events (`ai://model-progress`, `ai://progress`) carry the caller's own ids, so two runs
/// or two downloads in flight cannot be confused.
///
/// What differs: the page reached Rust through `invoke` and `listenTo`; here that pair is [AiBackend], one method a
/// command (`ai_device`, `ai_models`, `ai_fetch_model`, `ai_delete_model`, `ai_generate`, `ai_infer_command`,
/// `ai_cancel`, `ai_unload`, `ai_keep_job_config`) and [AiBackend.listen] for its events, whose payloads are the JSON
/// Rust serialises. The app's is [aiBackend], which whoever wires the engine replaces ([useAiBackend]); until then it
/// is [NoAiBackend], a browser: an empty catalogue and "Formatting runs on the phone". `useModels` is a
/// [ModelsController]; coming back to the front is its [ModelsController.refresh], called by whoever watches the
/// app's lifecycle. `test/ai/fake_backend.dart` holds the scripted backend the tests use.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/background_jobs.dart';
import '../core/preferences.dart';
import 'support/failure.dart';
import 'support/runnable.dart';

/// The generation that brought the write-up with the app closed (`MEETING_GENERATION`, capture/meeting.ts).
const int meetingGeneration = 20;

/// A model's download as it comes, `{id, receivedBytes, totalBytes}`.
const String modelProgressEvent = 'ai://model-progress';

/// A run's [Progress].
const String progressEvent = 'ai://progress';

/// One model the app offers (`ModelChoice`).
@immutable
class ModelChoice {
  const ModelChoice({required this.id, required this.name, required this.about, required this.bytes, required this.learntUntil});

  final String id;
  final String name;

  /// One line under the name in Settings.
  final String about;

  /// The download, in bytes, from the catalogue.
  final int bytes;

  /// The last whole year the model is taken to know, a fixed year and never the clock (docs/DESIGN.md §145): a blank
  /// asking about an event after it is refused before the model is asked (core/fill_live.dart), in 2026 and in 2028
  /// alike. 2024 for every model until each is read from its own card.
  final int learntUntil;
}

/// In the order Settings shows them (`MODELS`). Ids match `llm::model::CATALOGUE`.
const List<ModelChoice> models = [
  ModelChoice(id: 'qwen3.5-2b', name: 'Qwen3.5 2B', about: 'Quick. Good for short notes, and it can shorten long ones.', bytes: 1280835840, learntUntil: 2024),
  ModelChoice(id: 'qwen3.5-4b', name: 'Qwen3.5 4B', about: 'The balance. Fits most phones; check a fact it answers from memory.', bytes: 2740937888, learntUntil: 2024),
  ModelChoice(id: 'qwen3.5-9b', name: 'Qwen3.5 9B', about: 'The most careful, and the slowest. Wants 12 GB of memory.', bytes: 5680522464, learntUntil: 2024),
  ModelChoice(id: 'gemma-4-e4b', name: 'Gemma 4 E4B', about: 'A different voice. Runs like a 4B, with a bigger file.', bytes: 4977171584, learntUntil: 2024),
];

/// `DEFAULT_MODEL`.
const String defaultModel = 'qwen3.5-4b';

/// A model in the catalogue by its id, or null for one this build does not offer (`modelSpec`).
ModelChoice? modelSpec(String id) {
  for (final model in models) {
    if (model.id == id) return model;
  }
  return null;
}

/// `modelName`.
String modelName(String id) => modelSpec(id)?.name ?? id;

/// The year a model is taken to know up to: its own, or the catalogue's earliest for one this build does not know
/// (`learntUntil`).
int learntUntil(String id) => modelSpec(id)?.learntUntil ?? models.map((m) => m.learntUntil).reduce((a, b) => a < b ? a : b);

/// What every model is, said one way everywhere (`MODEL_LIMITS`).
const String modelLimits = 'The model has no internet. It knows what it learnt in training, nothing newer, and it can be wrong.';

/// Bytes as a person reads them: "2.7 GB" (`gb`).
String gb(int bytes) => '${(bytes / 1e9).toStringAsFixed(1)} GB';

/// A download's size as its line says it: whole megabytes (`megabytes`). JavaScript's `Math.round`.
int megabytes(int bytes) => (bytes / 1e6 + 0.5).floor();

// ---- what is on the phone ---------------------------------------------------------------

/// One catalogue entry with whether this phone has it (`ModelInfo`). Mirrors Rust's ModelInfo.
@immutable
class ModelInfo {
  const ModelInfo({required this.id, required this.file, required this.bytes, required this.present, required this.path});

  factory ModelInfo.fromJson(Map<String, Object?> json) => ModelInfo(
        id: json['id'] as String? ?? '',
        file: json['file'] as String? ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        present: json['present'] == true,
        path: json['path'] as String? ?? '',
      );

  final String id;
  final String file;
  final int bytes;
  final bool present;
  final String path;

  ModelInfo copyWith({bool? present}) => ModelInfo(id: id, file: file, bytes: bytes, present: present ?? this.present, path: path);

  Map<String, Object?> toJson() => {'id': id, 'file': file, 'bytes': bytes, 'present': present, 'path': path};

  @override
  bool operator ==(Object other) => other is ModelInfo && other.id == id && other.file == file && other.bytes == bytes && other.present == present && other.path == path;

  @override
  int get hashCode => Object.hash(id, file, bytes, present, path);

  @override
  String toString() => 'ModelInfo(${toJson()})';
}

/// A download in flight (`Download`).
@immutable
class Download {
  const Download({required this.id, required this.received, required this.total});

  final String id;
  final int received;
  final int total;

  @override
  bool operator ==(Object other) => other is Download && other.id == id && other.received == received && other.total == total;

  @override
  int get hashCode => Object.hash(id, received, total);

  @override
  String toString() => 'Download($id, $received of $total)';
}

/// The phone, as `ai_device` reads it (Rust's `llm::device::Device`). Every field that could not be read is null
/// rather than a guess.
@immutable
class AiDevice {
  const AiDevice({this.totalRamBytes, this.availableRamBytes, this.cores = 0, this.fastCores, this.chip, this.chipMaker, this.phone, this.phoneName, this.freeDiskBytes});

  factory AiDevice.fromJson(Map<String, Object?> json) => AiDevice(
        totalRamBytes: (json['totalRamBytes'] as num?)?.toInt(),
        availableRamBytes: (json['availableRamBytes'] as num?)?.toInt(),
        cores: (json['cores'] as num?)?.toInt() ?? 0,
        fastCores: (json['fastCores'] as num?)?.toInt(),
        chip: json['chip'] as String?,
        chipMaker: json['chipMaker'] as String?,
        phone: json['phone'] as String?,
        phoneName: json['phoneName'] as String?,
        freeDiskBytes: (json['freeDiskBytes'] as num?)?.toInt(),
      );

  /// All the memory the kernel manages, a little under the number on the box.
  final int? totalRamBytes;

  /// What the kernel says could be handed out now without swapping.
  final int? availableRamBytes;
  final int cores;

  /// Cores above the slowest tier: the ones generation should run on.
  final int? fastCores;

  /// `ro.soc.model`, such as "SM8850".
  final String? chip;

  /// `ro.soc.manufacturer`, such as "QTI".
  final String? chipMaker;

  /// `ro.product.model`, such as "SM-F976U".
  final String? phone;

  /// The maker's name for it where it sets one ("Galaxy Z Fold8").
  final String? phoneName;

  /// Free space where models are kept.
  final int? freeDiskBytes;

  Map<String, Object?> toJson() => {
        'totalRamBytes': totalRamBytes,
        'availableRamBytes': availableRamBytes,
        'cores': cores,
        'fastCores': fastCores,
        'chip': chip,
        'chipMaker': chipMaker,
        'phone': phone,
        'phoneName': phoneName,
        'freeDiskBytes': freeDiskBytes,
      };
}

// ---- a run ---------------------------------------------------------------------------------

/// Where a run is (`Phase`); [name] is the word Rust says.
enum Phase {
  loading,
  prefill,
  generating,
  done,
  error,
  cancelled;

  /// The phase Rust named; `generating` for a word this build does not know, which shows a run as working.
  static Phase of(Object? word) => values.firstWhere((p) => p.name == word, orElse: () => Phase.generating);
}

/// What the phone is doing for the model, sampled with each progress report by the engine (native generation 14)
/// (`Hardware`).
@immutable
class Hardware {
  const Hardware({required this.rssBytes, required this.freeBytes, required this.totalBytes, required this.cpuPercent, required this.threads, required this.cores, this.tempC});

  factory Hardware.fromJson(Map<String, Object?> json) => Hardware(
        rssBytes: (json['rssBytes'] as num?)?.toInt() ?? 0,
        freeBytes: (json['freeBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
        cpuPercent: (json['cpuPercent'] as num?)?.toDouble() ?? 0,
        threads: (json['threads'] as num?)?.toInt() ?? 0,
        cores: (json['cores'] as num?)?.toInt() ?? 0,
        tempC: (json['tempC'] as num?)?.toDouble(),
      );

  final int rssBytes;
  final int freeBytes;
  final int totalBytes;

  /// 0 to 100 per core: 640 is six and a half cores busy.
  final double cpuPercent;
  final int threads;
  final int cores;
  final double? tempC;

  Map<String, Object?> toJson() => {'rssBytes': rssBytes, 'freeBytes': freeBytes, 'totalBytes': totalBytes, 'cpuPercent': cpuPercent, 'threads': threads, 'cores': cores, 'tempC': tempC};

  @override
  bool operator ==(Object other) =>
      other is Hardware && other.rssBytes == rssBytes && other.freeBytes == freeBytes && other.totalBytes == totalBytes && other.cpuPercent == cpuPercent && other.threads == threads && other.cores == cores && other.tempC == tempC;

  @override
  int get hashCode => Object.hash(rssBytes, freeBytes, totalBytes, cpuPercent, threads, cores, tempC);
}

double _share(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);

/// The heat as a share of a bar: 20 °C is its foot and 60 °C its top (`heatShare`).
double heatShare(double tempC) => _share((tempC - 20) / 40);

/// The busy figure as a share of every core: 640% of eight is four fifths (`cpuShare`).
double cpuShare(double cpuPercent, int cores) => cores > 0 ? _share(cpuPercent / (100 * cores)) : 0;

/// One report of a run (`Progress`). Mirrors Rust's Progress.
@immutable
class Progress {
  const Progress({
    required this.id,
    required this.phase,
    this.promptTokens = 0,
    this.promptTokensDone = 0,
    this.outputTokens = 0,
    this.tokensPerSecond = 0,
    this.elapsedMs = 0,
    this.partial = '',
    this.thinking,
    this.message,
    this.hardware,
  });

  factory Progress.fromJson(Map<String, Object?> json) => Progress(
        id: json['id'] as String? ?? '',
        phase: Phase.of(json['phase']),
        promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
        promptTokensDone: (json['promptTokensDone'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        tokensPerSecond: (json['tokensPerSecond'] as num?)?.toDouble() ?? 0,
        elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
        partial: json['partial'] as String? ?? '',
        thinking: json['thinking'] as bool?,
        message: json['message'] as String?,
        hardware: json['hardware'] is Map ? Hardware.fromJson((json['hardware'] as Map).cast<String, Object?>()) : null,
      );

  final String id;
  final Phase phase;
  final int promptTokens;
  final int promptTokensDone;
  final int outputTokens;
  final double tokensPerSecond;
  final int elapsedMs;
  final String partial;

  /// [partial] starts with the model's reasoning, up to `</think>` (native generation 13, `think` asked for).
  final bool? thinking;
  final String? message;

  /// From native generation 14; absent before.
  final Hardware? hardware;

  Progress copyWith({String? id, Phase? phase, int? outputTokens, int? elapsedMs, String? partial, bool? thinking, String? message, Hardware? hardware}) => Progress(
        id: id ?? this.id,
        phase: phase ?? this.phase,
        promptTokens: promptTokens,
        promptTokensDone: promptTokensDone,
        outputTokens: outputTokens ?? this.outputTokens,
        tokensPerSecond: tokensPerSecond,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        partial: partial ?? this.partial,
        thinking: thinking ?? this.thinking,
        message: message ?? this.message,
        hardware: hardware ?? this.hardware,
      );

  /// As Rust serialises it; the keys the web's interface marks optional are left out when null.
  Map<String, Object?> toJson() => {
        'id': id,
        'phase': phase.name,
        'promptTokens': promptTokens,
        'promptTokensDone': promptTokensDone,
        'outputTokens': outputTokens,
        'tokensPerSecond': tokensPerSecond,
        'elapsedMs': elapsedMs,
        'partial': partial,
        if (thinking != null) 'thinking': thinking,
        if (message != null) 'message': message,
        if (hardware != null) 'hardware': hardware!.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is Progress &&
      other.id == id &&
      other.phase == phase &&
      other.promptTokens == promptTokens &&
      other.promptTokensDone == promptTokensDone &&
      other.outputTokens == outputTokens &&
      other.tokensPerSecond == tokensPerSecond &&
      other.elapsedMs == elapsedMs &&
      other.partial == partial &&
      other.thinking == thinking &&
      other.message == message &&
      other.hardware == hardware;

  @override
  int get hashCode => Object.hash(id, phase, promptTokens, promptTokensDone, outputTokens, tokensPerSecond, elapsedMs, partial, thinking, message, hardware);

  @override
  String toString() => 'Progress(${toJson()})';
}

/// What a run answered (`Output`). Mirrors Rust's Output.
@immutable
class Output {
  const Output({
    required this.text,
    this.promptTokens = 0,
    this.outputTokens = 0,
    this.ms = 0,
    this.cachedTokens = 0,
    this.prefillMs = 0,
    this.loadMs = 0,
    this.tokensPerSecond = 0,
    this.truncated = false,
    this.thinking,
  });

  factory Output.fromJson(Map<String, Object?> json) => Output(
        text: json['text'] as String? ?? '',
        promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        ms: (json['ms'] as num?)?.toInt() ?? 0,
        cachedTokens: (json['cachedTokens'] as num?)?.toInt() ?? 0,
        prefillMs: (json['prefillMs'] as num?)?.toInt() ?? 0,
        loadMs: (json['loadMs'] as num?)?.toInt() ?? 0,
        tokensPerSecond: (json['tokensPerSecond'] as num?)?.toDouble() ?? 0,
        truncated: json['truncated'] == true,
        thinking: json['thinking'] as bool?,
      );

  final String text;
  final int promptTokens;
  final int outputTokens;
  final int ms;
  final int cachedTokens;
  final int prefillMs;
  final int loadMs;
  final double tokensPerSecond;
  final bool truncated;

  /// The text starts with reasoning, up to `</think>` (ai/runs.dart `splitThinking` parts the two).
  final bool? thinking;

  Output copyWith({String? text, bool? truncated, bool? thinking}) => Output(
        text: text ?? this.text,
        promptTokens: promptTokens,
        outputTokens: outputTokens,
        ms: ms,
        cachedTokens: cachedTokens,
        prefillMs: prefillMs,
        loadMs: loadMs,
        tokensPerSecond: tokensPerSecond,
        truncated: truncated ?? this.truncated,
        thinking: thinking ?? this.thinking,
      );

  Map<String, Object?> toJson() => {
        'text': text,
        'promptTokens': promptTokens,
        'outputTokens': outputTokens,
        'ms': ms,
        'cachedTokens': cachedTokens,
        'prefillMs': prefillMs,
        'loadMs': loadMs,
        'tokensPerSecond': tokensPerSecond,
        'truncated': truncated,
        if (thinking != null) 'thinking': thinking,
      };

  @override
  bool operator ==(Object other) =>
      other is Output &&
      other.text == text &&
      other.promptTokens == promptTokens &&
      other.outputTokens == outputTokens &&
      other.ms == ms &&
      other.cachedTokens == cachedTokens &&
      other.prefillMs == prefillMs &&
      other.loadMs == loadMs &&
      other.tokensPerSecond == tokensPerSecond &&
      other.truncated == truncated &&
      other.thinking == thinking;

  @override
  int get hashCode => Object.hash(text, promptTokens, outputTokens, ms, cachedTokens, prefillMs, loadMs, tokensPerSecond, truncated, thinking);

  @override
  String toString() => 'Output(${toJson()})';
}

/// What `ai_generate` is sent: the `request` of the web's `invoke('ai_generate', { request })`.
@immutable
class GenerateRequest {
  const GenerateRequest({
    required this.id,
    required this.model,
    required this.system,
    this.context,
    required this.prompt,
    required this.maxTokens,
    required this.temperature,
    this.think = false,
    this.thinkBudget = 0,
  });

  final String id;
  final String model;
  final String system;
  final String? context;
  final String prompt;
  final int maxTokens;
  final double temperature;
  final bool think;
  final int thinkBudget;

  /// The request as the page sent it, key for key.
  Map<String, Object?> toJson() => {
        'id': id,
        'model': model,
        'system': system,
        'context': context,
        'prompt': prompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'think': think,
        'thinkBudget': thinkBudget,
      };
}

/// What `ai_infer_command` is sent (capture/instructionIntent.ts `inferInstruction`): a spoken command for the
/// engine's own fixed prompt and grammar, with the model a person chose. Its answer is the JSON Rust returns
/// (`CommandInferenceResult`), which the voice commands' reader validates.
@immutable
class InferCommandRequest {
  const InferCommandRequest({required this.id, required this.utterance, required this.preferredModel});

  final String id;
  final String utterance;
  final String preferredModel;

  Map<String, Object?> toJson() => {'id': id, 'utterance': utterance, 'preferredModel': preferredModel};
}

/// The prompts the write-up runs by (`JobConfig['prompts']`).
@immutable
class JobPrompts {
  const JobPrompts({required this.summary, required this.notes, required this.piece, required this.parts});

  final String summary;
  final String notes;
  final String piece;
  final String parts;

  Map<String, Object?> toJson() => {'summary': summary, 'notes': notes, 'piece': piece, 'parts': parts};
}

/// What the phone's own write-up reads when the app is not there to ask (src-tauri/src/jobs.rs `JobConfig`): which
/// model, the prompts as the app has them, the piece rule, and the two preferences it obeys (`JobConfig`).
@immutable
class JobConfig {
  const JobConfig({
    required this.model,
    required this.prompts,
    required this.onePassChars,
    required this.pieceChars,
    required this.temperature,
    required this.writeUp,
    required this.summaries,
  });

  final String model;
  final JobPrompts prompts;
  final int onePassChars;
  final int pieceChars;
  final double temperature;

  /// `charging` or `now`.
  final String writeUp;

  /// `meetings`, `long` or `off`.
  final String summaries;

  Map<String, Object?> toJson() => {
        'model': model,
        'prompts': prompts.toJson(),
        'onePassChars': onePassChars,
        'pieceChars': pieceChars,
        'temperature': temperature,
        'writeUp': writeUp,
        'summaries': summaries,
      };
}

/// The engine, as the page reached it: one method a Tauri command, and [listen] for its events.
///
/// Every method may throw; what is thrown is the engine's sentence, as an [Exception], an [Error] or a bare string
/// ([failureText] reads all three). An implementation over the native library decodes Rust's JSON with the
/// `fromJson` constructors here.
abstract class AiBackend {
  /// Whether there is an engine at all: the web's `isTauri()`. Without one nothing below is called.
  bool get available;

  /// This binary's native generation (`nativeGeneration()`): 0 when it will not say.
  Future<int> nativeGeneration();

  /// This binary's own version, `0.12.0` (`binaryVersion()`): empty when it will not say.
  Future<String> binaryVersion();

  /// `ai_device`: the phone, as it describes itself.
  Future<AiDevice> device();

  /// `ai_models`: the catalogue with what is on this phone.
  Future<List<ModelInfo>> models();

  /// `ai_fetch_model`: downloads a model, saying how far on [modelProgressEvent]; answers it as it now is.
  Future<ModelInfo> fetchModel(String id);

  /// `ai_delete_model`: removes a model's file; answers it as it now is.
  Future<ModelInfo> deleteModel(String id);

  /// `ai_generate`: runs the model, streaming [Progress] on [progressEvent] under the request's id; answers the
  /// whole output, or throws the engine's sentence, "cancelled" included.
  Future<Output> generate(GenerateRequest request);

  /// `ai_infer_command`: one spoken command read by an installed model with the engine's own prompt and grammar.
  /// Answers Rust's JSON as decoded.
  Future<Object?> inferCommand(InferCommandRequest request);

  /// `ai_cancel`: stops the run or the inference with this id; whether there was one.
  Future<bool> cancel(String id);

  /// `ai_unload`: lets the engine drop its model and context.
  Future<void> unload();

  /// `ai_keep_job_config`: hands the write-up its configuration.
  Future<void> keepJobConfig(JobConfig config);

  /// Hears [event] (`listenTo`): [handler] is given each payload as decoded JSON. Answers the way to stop.
  void Function() listen(String event, void Function(Object? payload) handler);
}

/// No engine: a browser, and this app until the native one is wired. Nothing is asked of it; anything that is
/// answers as the page did with nothing behind it.
class NoAiBackend implements AiBackend {
  const NoAiBackend();

  static const String _none = 'Formatting runs on the phone. Install Ghost.md to use it.';

  @override
  bool get available => false;

  @override
  Future<int> nativeGeneration() async => 0;

  @override
  Future<String> binaryVersion() async => '';

  @override
  Future<AiDevice> device() async => const AiDevice();

  @override
  Future<List<ModelInfo>> models() async => const [];

  @override
  Future<ModelInfo> fetchModel(String id) => Future.error(StateError(_none));

  @override
  Future<ModelInfo> deleteModel(String id) => Future.error(StateError(_none));

  @override
  Future<Output> generate(GenerateRequest request) => Future.error(StateError(_none));

  @override
  Future<Object?> inferCommand(InferCommandRequest request) => Future.error(StateError(_none));

  @override
  Future<bool> cancel(String id) async => false;

  @override
  Future<void> unload() async {}

  @override
  Future<void> keepJobConfig(JobConfig config) async {}

  @override
  void Function() listen(String event, void Function(Object? payload) handler) => () {};
}

AiBackend _backend = const NoAiBackend();
Future<int>? _generation;
Future<String>? _version;

/// The app's engine.
AiBackend get aiBackend => _backend;

/// Makes [next] the app's engine: the native one at launch, a scripted one in a test. What was asked of the one
/// before (its generation, its version) is forgotten with it.
void useAiBackend(AiBackend next) {
  _backend = next;
  _generation = null;
  _version = null;
}

/// This binary's native generation, asked once per engine: 0 with no engine or when it will not say
/// (`nativeGeneration`, core/nativeGeneration.ts).
Future<int> nativeGeneration() {
  if (!_backend.available) return Future.value(0);
  return _generation ??= _backend.nativeGeneration().then((n) => n, onError: (Object _) => 0);
}

/// This binary's own version, asked once per engine: '' with no engine or when it will not say (`binaryVersion`).
Future<String> binaryVersion() {
  if (!_backend.available) return Future.value('');
  return _version ??= _backend.binaryVersion().then((v) => v, onError: (Object _) => '');
}

/// Whether this binary is generation [wanted] or newer (`hasNativeGeneration`).
Future<bool> hasNativeGeneration(int wanted) async => (await nativeGeneration()) >= wanted;

final Set<VoidCallback> _modelsChanged = {};

/// [listener] after a model has been downloaded or removed here; answers the way to stop (`onModelsChanged`).
VoidCallback onModelsChanged(VoidCallback listener) {
  _modelsChanged.add(listener);
  return () => _modelsChanged.remove(listener);
}

/// Tells the listeners the models on the phone changed (`announceModelsChanged`).
void announceModelsChanged() {
  for (final listener in [..._modelsChanged]) {
    listener();
  }
}

/// The catalogue with what is on this phone; an empty list with no engine (`listModels`).
Future<List<ModelInfo>> listModels() async {
  if (!_backend.available) return const [];
  return _backend.models();
}

/// The phone as it describes itself, or null with no engine or when it will not say (`ai_device`; the web asked it
/// from the model page's fit lines).
Future<AiDevice?> readDevice() async {
  if (!_backend.available) return null;
  try {
    return await _backend.device();
  } catch (_) {
    return null;
  }
}

/// The catalogue with its state on this phone, refreshed after every change and whenever the app comes back to the
/// front (`useModels`). A download killed by the phone locking is retried by a person tapping Get again, not by
/// itself: gigabytes are not fetched behind anyone's back.
///
/// What differs: a hook's state is this notifier's fields; the first read is [refresh], which whoever makes one
/// calls, and calls again when the app comes back to the front.
class ModelsController extends ChangeNotifier {
  List<ModelInfo> _models = const [];
  Download? _download;
  String? _problem;
  bool _busy = false;
  bool _disposed = false;

  /// What is on the phone, as last read.
  List<ModelInfo> get models => _models;

  /// The download in flight, if one is.
  Download? get download => _download;

  /// Why the last download or removal failed, in the engine's words.
  String? get problem => _problem;

  void _set(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }

  /// Reads the phone again. A failure is left as the list was.
  Future<void> refresh() async {
    try {
      final read = await listModels();
      _set(() => _models = read);
    } catch (failure) {
      debugPrint('[glyph] models: ${failureText(failure)}');
    }
  }

  /// Downloads model [id]. A second call while one is coming is not a second download.
  Future<void> fetch(String id) async {
    final backend = aiBackend;
    if (_busy || !backend.available) return;
    if (preferences.value.localOnly) {
      _set(() => _problem = 'Local only is on, so nothing is downloaded. Turn it off in Settings to get a model.');
      return;
    }
    _busy = true;
    _set(() => _problem = null);
    // On the app's record of running work (lib/core/background_jobs.dart; docs/ACTIVITY.md): a ring filling, green,
    // as far as the download is; asked for by the person, so a long one chimes as it lands.
    final job = activity.begin('model:$id', kind: JobKind.downloads, title: 'Downloading ${modelSpec(id)?.name ?? 'the model'}', line: 'Downloading', personStarted: true, fraction: 0);
    final unlisten = backend.listen(modelProgressEvent, (payload) {
      if (payload is! Map || payload['id'] != id) return;
      _set(() => _download = Download(id: id, received: (payload['receivedBytes'] as num?)?.toInt() ?? 0, total: (payload['totalBytes'] as num?)?.toInt() ?? 0));
      final d = _download!;
      if (d.total > 0) job.progress(fraction: d.received / d.total, steps: downloadSteps(d.received, d.total));
    });
    _set(() => _download = Download(id: id, received: 0, total: modelSpec(id)?.bytes ?? 0));
    try {
      await backend.fetchModel(id);
      job.done(result: JobResult('${modelSpec(id)?.name ?? 'The model'} is ready'), tally: const JobTally('model downloaded', 'models downloaded'));
    } catch (failure) {
      _set(() => _problem = failureText(failure));
      job.failed(failureText(failure), fix: JobFix(JobFixKind.retry, () => unawaited(fetch(id))));
    } finally {
      unlisten();
      _set(() => _download = null);
      _busy = false;
      await refresh();
      announceModelsChanged();
    }
  }

  /// Removes model [id] from the phone.
  Future<void> remove(String id) async {
    final backend = aiBackend;
    if (!backend.available) return;
    _set(() => _problem = null);
    try {
      await backend.deleteModel(id);
    } catch (failure) {
      _set(() => _problem = failureText(failure));
    }
    await refresh();
    announceModelsChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// What a run is asked (`RunOptions`).
class RunOptions {
  const RunOptions({
    required this.model,
    required this.system,
    this.context,
    required this.prompt,
    required this.maxTokens,
    required this.temperature,
    this.think,
    this.thinkBudget,
    required this.onProgress,
  });

  final String model;
  final String system;
  final String? context;
  final String prompt;
  final int maxTokens;
  final double temperature;

  /// Let a reasoning model think before it answers, the thinking streamed ahead of the answer, up to `</think>`
  /// (ai/runs.dart `splitThinking` parts the two). Needs native generation 13. Off for every formatting pass.
  final bool? think;

  /// With [think]: tokens of thinking before it is closed for the model and the answer starts (native 13).
  final int? thinkBudget;
  final void Function(Progress progress) onProgress;
}

/// A generation in flight (`Run`).
class Run {
  const Run({required this.done, required this.cancel});

  /// Completes with the whole output; fails with the engine's sentence, "cancelled" included.
  final Future<Output> done;
  final void Function() cancel;
}

/// A failure said in the app's own words, with what the engine said kept as its [cause] (JavaScript's
/// `new Error(message, { cause })`).
class AiFailure implements Exception {
  const AiFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

int _runs = 0;

/// Starts a generation and streams its progress (`generate`). The listener is attached before the command is sent,
/// so no report is missed, and detached when the run ends however it ends.
///
/// The page's first step was a promise tick (`await listenTo`); here it is a microtask, so a caller has the [Run]
/// in hand before anything is asked, as there.
Run generate(RunOptions options) {
  final backend = aiBackend;
  final id = 'run-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${_runs += 1}';
  Future<Output> run() async {
    await null;
    if (!backend.available) throw const AiFailure('Formatting runs on the phone. Install Ghost.md to use it.');
    final unlisten = backend.listen(progressEvent, (payload) {
      if (payload is! Map) return;
      final progress = Progress.fromJson(payload.cast<String, Object?>());
      if (progress.id == id) options.onProgress(progress);
    });
    try {
      return await backend.generate(GenerateRequest(
        id: id,
        model: options.model,
        system: options.system,
        context: options.context,
        prompt: options.prompt,
        maxTokens: options.maxTokens,
        temperature: options.temperature,
        think: options.think ?? false,
        thinkBudget: options.thinkBudget ?? 0,
      ));
    } catch (failure) {
      // A model whose chat template this binary cannot apply cannot run at all here: it is remembered, so the next
      // run goes to another model on the phone, and said in words a person can act on (support/runnable.dart).
      if (isTemplateFailure(failureText(failure))) {
        unawaited(markCannotRun(options.model));
        throw AiFailure(
          '${modelSpec(options.model)?.name ?? 'This model'} can’t run in this version of Ghost.md. Choose another model in Settings › AI, or install the newest Ghost.md.',
          cause: failure,
        );
      }
      rethrow;
    } finally {
      unlisten();
    }
  }

  return Run(
    done: run(),
    cancel: () {
      if (backend.available) unawaited(backend.cancel(id).then((_) {}, onError: (Object _) {}));
    },
  );
}

// ---- the write-up with the app closed (native generation 20) ---------------------------------

/// Hand the write-up its configuration; nothing on a binary without a write-up (`keepJobConfig`).
Future<void> keepJobConfig(JobConfig config) async {
  if (!aiBackend.available || !(await hasNativeGeneration(meetingGeneration))) return;
  await aiBackend.keepJobConfig(config);
}

/// Let the engine drop its model and context: after a long summary, whose context is the largest the app asks for
/// (`unloadModel`). The engine idles it out after five minutes anyway; this is sooner. Nothing on an older binary.
Future<void> unloadModel() async {
  if (!aiBackend.available || !(await hasNativeGeneration(meetingGeneration))) return;
  await aiBackend.unload().then((_) {}, onError: (Object _) {});
}

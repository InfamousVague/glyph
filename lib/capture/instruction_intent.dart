/// What the on-device model says a command asks for, checked at the boundary it arrives over, and the one pass that
/// asks it. A port of `src/app/capture/instructionIntent.ts`.
///
/// What differs: the shapes, and what the web reaches for that this takes. `InstructionIntent` is a sealed class
/// ([InstructionIntentAppend], [InstructionIntentCreate], [InstructionIntentNone], its reason an
/// [InstructionNoneReason]); `InferenceResult` is [InferenceResultIntent] or [InferenceResultUnavailable];
/// `InterpretedCommand` is [InterpretedCommandDeterministic], [InterpretedCommandInferred] (its `note` null for a
/// create, which on the web has none) or [InterpretedCommandRejected]. `interpretWakeCommand` takes `notes` as a
/// named parameter and its inference as an optional positional one, and answers an [InterpretedRun].
///
/// The web's `inferInstruction` calls Tauri's `invoke`, asks `isTauri()`, reads `preferences().formatModel` and the
/// clock. Here each is a parameter: [inferInstruction] takes the native call as an [InstructionInvoke] (none where
/// there is no native side, the web's `isTauri()` false), the preferred model as a string, and the clock as a
/// function. A failure is said as `core/failure.ts` `failureText` says one: an error's own message, or the thing
/// thrown as a string.
library;

import 'command.dart' show Plan, planCommand;
import 'list_append.dart' show InstructionArea;
import 'route.dart' show Candidate, TargetResolutionAmbiguous, TargetResolutionNotFound, TargetResolutionResolved, resolveTarget;

/// Why the model answered that nothing should change.
enum InstructionNoneReason { unsupported, destructive, compound, unclear }

/// What a command asks for, as the model read it (`InstructionIntent`).
sealed class InstructionIntent {
  const InstructionIntent();

  /// The web's `action`: `append`, `create` or `none`.
  String get action;
}

/// `action: 'append'`: words for a note named.
final class InstructionIntentAppend extends InstructionIntent {
  const InstructionIntentAppend({required this.target, required this.content, required this.placement});

  final String target;
  final String content;
  final InstructionArea? placement;

  @override
  String get action => 'append';

  @override
  bool operator ==(Object other) =>
      other is InstructionIntentAppend && other.target == target && other.content == content && other.placement == placement;

  @override
  int get hashCode => Object.hash(action, target, content, placement);

  @override
  String toString() => '{action: append, target: $target, content: $content, placement: ${placement?.name}}';
}

/// `action: 'create'`: a new note by name, with what it says or nothing.
final class InstructionIntentCreate extends InstructionIntent {
  const InstructionIntentCreate({required this.target, required this.content});

  final String target;
  final String? content;

  @override
  String get action => 'create';

  @override
  bool operator ==(Object other) => other is InstructionIntentCreate && other.target == target && other.content == content;

  @override
  int get hashCode => Object.hash(action, target, content);

  @override
  String toString() => '{action: create, target: $target, content: $content}';
}

/// `action: 'none'`: nothing changes, and why.
final class InstructionIntentNone extends InstructionIntent {
  const InstructionIntentNone({required this.reason});

  final InstructionNoneReason reason;

  @override
  String get action => 'none';

  @override
  bool operator ==(Object other) => other is InstructionIntentNone && other.reason == reason;

  @override
  int get hashCode => Object.hash(action, reason);

  @override
  String toString() => '{action: none, reason: ${reason.name}}';
}

/// What an inference came to (`InferenceResult`).
sealed class InferenceResult {
  const InferenceResult();

  /// The web's `status`: `intent` or `unavailable`.
  String get status;
}

/// `status: 'intent'`.
final class InferenceResultIntent extends InferenceResult {
  const InferenceResultIntent({required this.intent, required this.model});

  final InstructionIntent intent;
  final String model;

  @override
  String get status => 'intent';

  @override
  bool operator ==(Object other) => other is InferenceResultIntent && other.intent == intent && other.model == model;

  @override
  int get hashCode => Object.hash(status, intent, model);

  @override
  String toString() => '{status: intent, intent: $intent, model: $model}';
}

/// `status: 'unavailable'`.
final class InferenceResultUnavailable extends InferenceResult {
  const InferenceResultUnavailable({required this.reason});

  final String reason;

  @override
  String get status => 'unavailable';

  @override
  bool operator ==(Object other) => other is InferenceResultUnavailable && other.reason == reason;

  @override
  int get hashCode => Object.hash(status, reason);

  @override
  String toString() => '{status: unavailable, reason: $reason}';
}

bool _keysAre(Map<Object?, Object?> value, List<String> keys) {
  final actual = [for (final key in value.keys) '$key']..sort();
  final wanted = [...keys]..sort();
  if (actual.length != wanted.length) return false;
  for (var index = 0; index < actual.length; index += 1) {
    if (actual[index] != wanted[index]) return false;
  }
  return true;
}

bool _safeText(Object? value, int max) {
  if (value is! String || value.trim().isEmpty) return false;
  final characters = value.runes;
  return characters.length <= max && characters.every((code) => code >= 32 && code != 127);
}

/// Strict runtime validation at the IPC boundary, independent of the static types.
InferenceResult? validateInference(Object? value) {
  if (value is! Map) return null;
  final result = value;
  if (result['status'] == 'unavailable') {
    final reason = result['reason'];
    return _keysAre(result, ['reason', 'status']) && _safeText(reason, 500) ? InferenceResultUnavailable(reason: reason as String) : null;
  }
  final model = result['model'];
  if (result['status'] != 'intent' || !_keysAre(result, ['intent', 'model', 'status']) || model is! String) return null;
  final intent = result['intent'];
  if (intent is! Map) return null;
  final target = intent['target'];
  final content = intent['content'];
  if (intent['action'] == 'append') {
    final placement = intent['placement'];
    InstructionArea? area;
    var placed = placement == null;
    for (final each in InstructionArea.values) {
      if (each.name == placement) {
        area = each;
        placed = true;
      }
    }
    if (_keysAre(intent, ['action', 'content', 'placement', 'target']) && _safeText(target, 120) && _safeText(content, 4000) && placed) {
      return InferenceResultIntent(
        model: model,
        intent: InstructionIntentAppend(target: (target as String).trim(), content: (content as String).trim(), placement: area),
      );
    }
  }
  if (intent['action'] == 'create') {
    if (_keysAre(intent, ['action', 'content', 'target']) && _safeText(target, 120) && (content == null || _safeText(content, 4000))) {
      return InferenceResultIntent(
        model: model,
        intent: InstructionIntentCreate(target: (target as String).trim(), content: content is String ? content.trim() : null),
      );
    }
  }
  if (intent['action'] == 'none') {
    final reason = intent['reason'];
    if (_keysAre(intent, ['action', 'reason'])) {
      for (final each in InstructionNoneReason.values) {
        if (each.name == reason) return InferenceResultIntent(model: model, intent: InstructionIntentNone(reason: each));
      }
    }
  }
  return null;
}

int _sequence = 0;

/// One inference under way: its answer, and how to stop it (`InferenceRun`).
class InferenceRun {
  const InferenceRun({required this.done, required this.cancel});

  final Future<InferenceResult> done;
  final void Function() cancel;
}

/// What a command's words came to (`InterpretedCommand`).
sealed class InterpretedCommand<N extends Candidate> {
  const InterpretedCommand();

  /// The web's `source`: `deterministic`, `inferred` or `rejected`.
  String get source;
}

/// The rules read it.
final class InterpretedCommandDeterministic<N extends Candidate> extends InterpretedCommand<N> {
  const InterpretedCommandDeterministic({required this.plan});

  final Plan<N> plan;

  @override
  String get source => 'deterministic';

  @override
  bool operator ==(Object other) => other is InterpretedCommandDeterministic && other.plan == plan;

  @override
  int get hashCode => Object.hash(source, plan);

  @override
  String toString() => '{source: deterministic, plan: $plan}';
}

/// The model read it: an append with the note its title found, or a create, which has no note.
final class InterpretedCommandInferred<N extends Candidate> extends InterpretedCommand<N> {
  const InterpretedCommandInferred({required this.intent, this.note});

  final InstructionIntent intent;
  final N? note;

  @override
  String get source => 'inferred';

  @override
  bool operator ==(Object other) => other is InterpretedCommandInferred && other.intent == intent && other.note == note;

  @override
  int get hashCode => Object.hash(source, intent, note);

  @override
  String toString() => '{source: inferred, intent: $intent${note == null ? '' : ', note: $note'}}';
}

/// Nothing is done, and why.
final class InterpretedCommandRejected<N extends Candidate> extends InterpretedCommand<N> {
  const InterpretedCommandRejected({required this.reason});

  final String reason;

  @override
  String get source => 'rejected';

  @override
  bool operator ==(Object other) => other is InterpretedCommandRejected && other.reason == reason;

  @override
  int get hashCode => Object.hash(source, reason);

  @override
  String toString() => '{source: rejected, reason: $reason}';
}

/// The native side's call, as Tauri's `invoke`: a command's name and its arguments, answered with whatever JSON the
/// command gives back. `ai_infer_command` and `ai_cancel` are the two asked for here.
typedef InstructionInvoke = Future<Object?> Function(String command, Map<String, Object?> args);

/// `core/failure.ts` `failureText`: an error's own message where it has one, or the thing thrown as a string.
String _failureText(Object failure) {
  final text = '$failure';
  for (final lead in const ['Exception: ', 'Error: ']) {
    if (text.startsWith(lead)) return text.substring(lead.length);
  }
  return text;
}

/// Native-only inference. It never downloads a model or calls a remote service.
///
/// [invoke] is the native call, null where there is no native side; [preferredModel] is the preferences'
/// `formatModel`; [now] is the clock, in milliseconds.
InferenceRun inferInstruction(String utterance, {InstructionInvoke? invoke, String? preferredModel, int Function()? now}) {
  final at = now != null ? now() : DateTime.now().millisecondsSinceEpoch;
  final id = 'command-${at.toRadixString(36)}-${_sequence += 1}';
  if (invoke == null) {
    return InferenceRun(
      done: Future.value(const InferenceResultUnavailable(reason: 'Instruction inference is available in the installed Android app.')),
      cancel: () {},
    );
  }
  Future<InferenceResult> ask() async {
    try {
      final value = await invoke('ai_infer_command', {
        'request': {'id': id, 'utterance': utterance, 'preferredModel': preferredModel},
      });
      return validateInference(value) ?? const InferenceResultUnavailable(reason: 'The on-device model returned an invalid command.');
    } catch (failure) {
      return InferenceResultUnavailable(reason: _failureText(failure));
    }
  }

  return InferenceRun(
    done: ask(),
    cancel: () {
      invoke('ai_cancel', {'id': id}).then<void>((_) {}, onError: (Object _) {});
    },
  );
}

/// An interpretation under way: its answer, and how to stop it.
class InterpretedRun<N extends Candidate> {
  const InterpretedRun({required this.done, required this.cancel});

  final Future<InterpretedCommand<N>> done;
  final void Function() cancel;
}

/// Deterministic parser has absolute precedence; inference is fallback only. Only the evaluation corpus
/// (instruction_corpus_test.dart) runs this now: the reader at Done reads through `classifyFinalTranscript`
/// (final_instruction.dart), and the pass that asked it while the microphone was live has gone (docs/DESIGN.md
/// §127).
InterpretedRun<N> interpretWakeCommand<N extends Candidate>(String utterance, {required List<N> notes, InferenceRun Function(String words)? startInference}) {
  final deterministic = planCommand<N>(utterance, notes: notes);
  if (deterministic != null) {
    return InterpretedRun<N>(done: Future.value(InterpretedCommandDeterministic<N>(plan: deterministic)), cancel: () {});
  }
  final run = (startInference ?? inferInstruction)(utterance);
  return InterpretedRun<N>(
    cancel: run.cancel,
    done: run.done.then<InterpretedCommand<N>>((result) {
      if (result is! InferenceResultIntent) return InterpretedCommandRejected<N>(reason: (result as InferenceResultUnavailable).reason);
      final intent = result.intent;
      switch (intent) {
        case InstructionIntentNone():
          return InterpretedCommandRejected<N>(reason: 'That ${intent.reason.name} request was not changed.');
        case InstructionIntentCreate():
          return InterpretedCommandInferred<N>(intent: intent);
        case InstructionIntentAppend():
          final target = resolveTarget<N>(intent.target, notes);
          return switch (target) {
            TargetResolutionNotFound() => InterpretedCommandRejected<N>(reason: 'No note called “${intent.target}”.'),
            TargetResolutionAmbiguous() => InterpretedCommandRejected<N>(reason: '“${intent.target}” matches more than one note.'),
            TargetResolutionResolved(:final note) => InterpretedCommandInferred<N>(intent: intent, note: note),
          };
      }
    }),
  );
}

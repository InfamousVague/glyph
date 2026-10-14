/// One reader for a spoken instruction, with "hey Ghost" before it or without: what the person wants done, and to
/// which note, which the recorder asks once, at Done, when the live reader carried out nothing (capture_screen.dart
/// `finish`).
///
/// The reader and its rules are `lib/ai/instruction.dart`'s (a port of `src/app/ai/instruction.ts`): [bareWords] is
/// that file's own, and [readInstruction] asks that file's and says what came back in this file's classes, which
/// differ in one thing: a run's kind is the web's word for it as a `String` (`RunKind.id`), as in `run_of.dart`,
/// which is how the recorder's screen carries it. When the screen carries the enum, this file goes and the screen
/// imports that one.
library;

import '../../ai/instruction.dart' as ai;
import '../route.dart' show Candidate;
import '../voice_log.dart' show VoiceTrace;
import '../voice_plan.dart' show VoiceAction, VoiceStep;

export '../../ai/instruction.dart' show bareWords;

/// What a spoken instruction was read as (`Read`).
sealed class Read<N extends Candidate> {
  const Read();

  /// The web's `kind`: `run`, `command`, `reject`, `ask` or `words`.
  String get kind;
}

/// One of the runs, on the note on screen.
final class ReadRun<N extends Candidate> extends Read<N> {
  const ReadRun({required this.run});

  final String run;

  @override
  String get kind => 'run';
}

/// The changes a recording asks for, to be confirmed first (lib/ai/instruction.dart `ReadCommand`).
final class ReadCommand<N extends Candidate> extends Read<N> {
  const ReadCommand({required this.actions, this.note, this.conversational = false, this.trace});

  final List<VoiceAction<N>> actions;
  final String? note;
  final bool conversational;
  final int? trace;

  @override
  String get kind => 'command';
}

/// A command that could not be carried out, and why.
final class ReadReject<N extends Candidate> extends Read<N> {
  const ReadReject({required this.reason});

  final String reason;

  @override
  String get kind => 'reject';
}

/// Free words about the note on screen.
final class ReadAsk<N extends Candidate> extends Read<N> {
  const ReadAsk({required this.instruction});

  final String instruction;

  @override
  String get kind => 'ask';
}

/// Not an instruction at all: spoken words with no keyword. [notice] says when the model could not be asked, or why
/// a command said without the keyword was not carried out.
final class ReadWords<N extends Candidate> extends Read<N> {
  const ReadWords({this.notice});

  final String? notice;

  @override
  String get kind => 'words';
}

/// Reads a spoken instruction (lib/ai/instruction.dart `readInstruction`). [notes] are the person's notes, for a
/// command that names one.
Future<Read<N>> readInstruction<N extends Candidate>(
  String text,
  List<N> notes, [
  VoiceStep? step,
  VoiceTrace? trace,
  Future<List<String>> Function()? diagnose,
]) async =>
    switch (await ai.readInstruction<N>(text, notes, step, trace, diagnose)) {
      ai.ReadRun<N>(:final run) => ReadRun<N>(run: run.id),
      ai.ReadCommand<N>(:final actions, :final note, :final conversational, :final trace) =>
        ReadCommand<N>(actions: actions, note: note, conversational: conversational, trace: trace),
      ai.ReadReject<N>(:final reason) => ReadReject<N>(reason: reason),
      ai.ReadAsk<N>(:final instruction) => ReadAsk<N>(instruction: instruction),
      ai.ReadWords<N>(:final notice) => ReadWords<N>(notice: notice),
    };

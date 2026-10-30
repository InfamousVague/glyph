/// The reader at Done: one stopped recording, read once from its complete transcript, for the changes it may be
/// asking for. A port of `src/app/capture/finalInstruction.ts`, as the Tauri app's voice work after 1.6 left it.
///
/// 1. The rules (command.dart), on a request found anywhere in the recording (command_scan.dart): instant and exact
///    for the phrasings they know, each request of a recording read on its own (compound.dart). What they read is
///    polished by the model (voice_polish.dart): items split or joined, titles and text tidied; the rules' draft
///    stands if it cannot.
/// 2. Otherwise, when anything in it could be a request, the on-device model in two steps (voice_plan.dart): sort,
///    then plan with real item lists.
///
/// Every step is written to the voice log (voice_log.dart). Whisper's echo at the end of a recording is dropped
/// first (trailing_echo.dart).
///
/// What differs from the web:
/// - The shapes. `FinalInstruction` is a sealed class ([FinalInstructionOrdinary], [FinalInstructionOffer],
///   [FinalInstructionRejected]); an offer is a list of [VoiceAction]s, not one plan. A note's body is read through
///   its candidate's `noteBody` (the web's `note?.body`), and whether it is a book with `lib/core/book.dart`.
/// - The model is the optional third argument, a [VoiceStep] (voice_plan.dart); the recorder passes its own, bound to
///   the native call, and the default has no native side, which answers that it is unavailable.
/// - What the rules read keeps what the Flutter app's port of the page added after the 1.6 branch: the note's own
///   title taken out of a request for a list ([_askedForList]: "House TODOs" is a name), a book never written into,
///   a table, board or book turned down without asking the model, and a name found as the live reader finds it
///   (note_find.dart).
library;

import '../core/item_syntax.dart' show markerPattern;
import 'command.dart'
    show
        FinalPlan,
        PlacementHow,
        Plan,
        PlanCreateList,
        PlanCreateNote,
        PlanNoNote,
        PlanPlace,
        planFinalCommand;
import 'command_scan.dart' show scanForCommand;
import 'compound.dart' show splitCommands;
import 'note_find.dart' show nameWords;
import 'route.dart' show Candidate;
import 'spoken_list.dart' show spokenListItems;
import 'trailing_echo.dart' show withoutTrailingEcho;
import 'voice_log.dart' show VoiceTrace, traceRecording;
import 'voice_plan.dart';
import 'voice_polish.dart' show polishActions;

export 'voice_plan.dart' show VoiceAction, VoiceAppend, VoiceCreate;

/// What a finished recording is (`FinalInstruction`).
sealed class FinalInstruction<N extends Candidate> {
  const FinalInstruction({this.trace});

  /// The web's `kind`: `ordinary`, `offer` or `rejected`.
  String get kind;

  /// This recording's entry in the voice log (voice_log.dart), for what the person chooses on the card.
  final int? trace;

  FinalInstruction<N> withTrace(int at);
}

/// Words: a note of its own, with something to say about it or nothing.
final class FinalInstructionOrdinary<N extends Candidate> extends FinalInstruction<N> {
  const FinalInstructionOrdinary({required this.notice, super.trace});

  final String? notice;

  @override
  String get kind => 'ordinary';

  @override
  FinalInstruction<N> withTrace(int at) => FinalInstructionOrdinary<N>(notice: notice, trace: at);

  @override
  bool operator ==(Object other) => other is FinalInstructionOrdinary && other.notice == notice && other.trace == trace;

  @override
  int get hashCode => Object.hash(kind, notice, trace);

  @override
  String toString() => '{kind: ordinary, notice: $notice}';
}

/// The changes the recording asks for, and the rest of what was said as its own note. [conversational]: found inside
/// the recording, not at its start; declined, the recording is kept as a note.
final class FinalInstructionOffer<N extends Candidate> extends FinalInstruction<N> {
  const FinalInstructionOffer({required this.actions, required this.note, required this.conversational, super.trace});

  final List<VoiceAction<N>> actions;
  final String? note;
  final bool conversational;

  @override
  String get kind => 'offer';

  @override
  FinalInstruction<N> withTrace(int at) => FinalInstructionOffer<N>(actions: actions, note: note, conversational: conversational, trace: at);

  @override
  bool operator ==(Object other) =>
      other is FinalInstructionOffer && _sameActions(other.actions, actions) && other.note == note && other.conversational == conversational && other.trace == trace;

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(actions), note, conversational, trace);

  @override
  String toString() => '{kind: offer, actions: $actions, note: $note, conversational: $conversational}';
}

bool _sameActions(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A command turned down, and why.
final class FinalInstructionRejected<N extends Candidate> extends FinalInstruction<N> {
  const FinalInstructionRejected({required this.reason, super.trace});

  final String reason;

  @override
  String get kind => 'rejected';

  @override
  FinalInstruction<N> withTrace(int at) => FinalInstructionRejected<N>(reason: reason, trace: at);

  @override
  bool operator ==(Object other) => other is FinalInstructionRejected && other.reason == reason && other.trace == trace;

  @override
  int get hashCode => Object.hash(kind, reason, trace);

  @override
  String toString() => '{kind: rejected, reason: $reason}';
}

/// A spoken command that asks for several things: a list, or a plural kind ("items", "tasks", "to-dos", "bullet
/// points"). Read with the note's own title taken out ([_askedForList]): "House TODOs" is a name, not a request for
/// items.
final RegExp _listWords = RegExp(r'\b(?:lists?|items|bullets|bullet\s+points|tasks|todos|check\s?lists?)\b', caseSensitive: false);

/// A Markdown list line, its marker (core/item_syntax.dart) and then words or a to-do's box: the note already keeps
/// a list.
final RegExp _listLine = RegExp('^\\s*$markerPattern\\s+\\S', multiLine: true);

/// The most words an item has when nobody said "list": longer pieces are a sentence with commas in it.
const int _shortItemWords = 4;

/// "We should…", "it was…": a piece that starts like a sentence is not an item.
final RegExp _sentenceStart = RegExp(
  r"^(?:i|i'm|we|we're|you|he|she|it|it's|they|this|that|there|so|if|when|because|after|before|with)\b",
  caseSensitive: false,
);

final RegExp _separated = RegExp(r'[,;]|\band\b', caseSensitive: false);
final RegExp _spaces = RegExp(r'\s+');

/// Items, when what is added is a list: the command asked for one, or the note already is one and the words are
/// several short things. The app decides this from the person's words and the note, not from the model's answer, so
/// a small model that leaves its placement empty cannot turn a list into a block of text.
List<String>? _listItems(String words, String content, {required String title, String? body, required bool asked}) {
  final wanted = asked || _askedForList(words, title);
  if (!wanted && !_listLine.hasMatch(body ?? '')) return null;
  // Told apart by commas, semicolons or "and", never word by word: "call an electrician to fix the light sockets" is
  // one thing to do, and it was eight.
  final items = _separated.hasMatch(content) ? spokenListItems(content) : const <String>[];
  if (items.length < 2) return null;
  if (!wanted && items.any((item) => item.split(_spaces).length > _shortItemWords || _sentenceStart.hasMatch(item))) return null;
  return items;
}

final RegExp _apostrophes = RegExp("[’']");
final RegExp _todos = RegExp(r'\b(?:to|two|2)[\s-]*do(?:s|es)\b');
final RegExp _todo = RegExp(r'\b(?:to|2)[\s-]*do\b');
final RegExp _notLetters = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Whether the command asked for several things, with the note's title taken out of it first: "add to house to-dos,
/// fix the gutter" is one to-do, where the title's "to-dos" once split it into "Fix", "The" and "Gutter".
bool _askedForList(String words, String title) {
  final titled = nameWords(title).words.toSet();
  final said = words.toLowerCase().replaceAll(_apostrophes, '').replaceAll(_todos, 'todos').replaceAll(_todo, 'todo').split(_notLetters).where((word) {
    if (word.isEmpty) return false;
    final named = nameWords(word).words;
    return !titled.contains(named.isNotEmpty ? named.first : word);
  }).join(' ');
  return _listWords.hasMatch(said);
}

/// Why a command the reader read, but a recording does not carry out, was turned down.
const String _unsupportedBare = 'That command is not supported from a voice capture.';
const String _unsupported = '$_unsupportedBare Nothing changed.';

/// Words that could be a request, anywhere: worth asking the model to sort. Loose on purpose - the sort step decides -
/// but a recording with none of them is plainly dictation and costs no model time.
final RegExp _hint = RegExp(
  r"\b(?:add|put|append|make|create|start|throw|stick|toss|include|insert|jot|write|save|list|lists|checklist|to-?\s?dos?|keep\s+track|track\s+of|remember|remind|note\s+down|could\s+use|(?:need|want)\s+(?:a|an|some)\s+(?:new\s+)?(?:list|note|place|spot|way))\b",
  caseSensitive: false,
);

final RegExp _regexMarks = RegExp(r'[.*+?^${}()|[\]\\]');
final RegExp _titleSpaces = RegExp(r'\s+');

bool _namesATitle(String said, List<String> titles) {
  return titles.any((title) {
    if (title.trim().length <= 1) return false;
    final escaped = title.trim().replaceAllMapped(_regexMarks, (m) => '\\${m[0]}').replaceAll(_titleSpaces, r'[\s\p{P}]+');
    return RegExp('(?:^|[^\\p{L}\\p{N}])$escaped(?=\$|[^\\p{L}\\p{N}])', caseSensitive: false, unicode: true).hasMatch(said);
  });
}

/// The rules' plan as actions: what the card shows and confirming carries out (`actionsOf`).
List<VoiceAction<N>> _actionsOf<N extends Candidate>(FinalPlan<N> plan) => switch (plan) {
      PlanPlace<N>() => [VoiceAppend<N>(note: plan.note, text: plan.text, placement: plan.placement)],
      PlanCreateList<N>() => [VoiceCreate<N>(title: plan.title, items: plan.items ?? const [], tasks: false)],
      PlanCreateNote<N>() => [VoiceCreate<N>(title: plan.title, items: const [], tasks: false, body: plan.body, template: plan.template, place: plan.place)],
    };

String _describe<N extends Candidate>(List<VoiceAction<N>> actions, String? note) {
  final parts = [
    for (final action in actions)
      switch (action) {
        VoiceCreate<N>() => action.body != null ? 'create the note “${action.title}”' : 'create “${action.title}” (${action.items.length} items)',
        VoiceAppend<N>() =>
          'add to ${action.note.title}: ${action.placement.items?.length ?? 1} ${action.placement.how == PlacementHow.item ? 'item(s)' : 'paragraph'}',
      },
    if (note != null && note.isNotEmpty) 'keep the rest as a note',
  ];
  return 'offer: ${parts.join('; ')}';
}

bool _isFinal(Plan<Candidate>? plan) => plan is PlanPlace || plan is PlanCreateList || plan is PlanCreateNote;

String _cut(String text, int max) => text.length > max ? text.substring(0, max) : text;

String _sentenceCase(String text) => text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

Future<List<String>> _noDiagnostics() async => const [];

/// Read one stopped recording. Live phrase commits never call this: an action is possible only after Whisper has
/// supplied the complete transcript (`classifyFinalTranscript`). [diagnose] says what the engine was doing, for the
/// voice log when a step fails (voice_plan.dart `diagnosticsOver`).
Future<FinalInstruction<N>> classifyFinalTranscript<N extends Candidate>(
  String heard,
  List<N> notes, [
  VoiceStep? step,
  VoiceTrace? trace,
  Future<List<String>> Function()? diagnose,
]) async {
  final ask = step ?? runVoiceStep;
  final log = trace ?? traceRecording(heard);
  final diagnostics = diagnose ?? _noDiagnostics;
  final transcript = withoutTrailingEcho(heard);
  if (transcript.trim() != heard.trim()) log.step('dropped Whisper’s echo at the end: “${heard.substring(transcript.length).trim()}”');
  final titles = [
    for (final note in notes)
      if (note.title.trim().isNotEmpty) note.title,
  ];
  final scan = scanForCommand(transcript, titles);
  final conversational = !(scan?.anchored ?? false);

  FinalInstruction<N> finish(FinalInstruction<N> result) {
    log.decide(switch (result) {
      FinalInstructionOffer<N>() => _describe(result.actions, result.note),
      FinalInstructionRejected<N>() => 'rejected: ${result.reason}',
      FinalInstructionOrdinary<N>() => 'note${result.notice != null && result.notice!.isNotEmpty ? ' (${result.notice})' : ''}',
    });
    return result.withTrace(log.at);
  }

  /// A request that cannot be carried out. One the recording began with is rejected: its words are a command, not a
  /// note. One found inside talk leaves the recording as a note, with why.
  FinalInstruction<N> fail(String reason) =>
      finish(conversational ? FinalInstructionOrdinary<N>(notice: '$reason Saved this recording as a note.') : FinalInstructionRejected<N>(reason: '$reason Nothing changed.'));

  // 1. The rules.
  String? unmatched;
  if (scan != null) {
    log.step('request found (${scan.anchored ? 'at the start' : 'inside the talk'}): “${_cut(scan.words, 200)}”');
    // "Add to elements gold, and then add to posters genes": each request is read on its own.
    final parts = splitCommands(scan.words);
    if (parts.length > 1) log.step('${parts.length} requests: ${parts.map((part) => '“${_cut(part, 60)}”').join(' / ')}');
    final plans = [for (final part in parts) planFinalCommand<N>(part, notes: notes)];
    final plan = plans.isEmpty ? null : plans.first;
    final missing = plans.whereType<PlanNoNote<N>>().firstOrNull;
    if (missing != null) unmatched = 'No unambiguous note matches “${missing.name}”.';
    if (plans.every(_isFinal)) {
      final actions = <VoiceAction<N>>[];
      for (var at = 0; at < plans.length; at += 1) {
        final read = plans[at];
        if (read is! FinalPlan<N>) continue;
        var ruled = read;
        if (read is PlanPlace<N> && read.how == PlacementHow.leave) {
          // "Add to Movies Jaws, Alien and Heat": a list note takes several things as several items.
          final items = _listItems(at < parts.length ? parts[at] : scan.words, read.text, title: read.note.title, body: read.note.noteBody, asked: false);
          if (items != null) {
            ruled = PlanPlace<N>(note: read.note, text: read.text, how: PlacementHow.item, task: read.task, many: true, near: read.near, items: items);
          }
        }
        log.step(
          'rules: ${ruled is PlanPlace<N> ? 'add to ${ruled.note.title}' : '${ruled is PlanCreateNote<N> ? 'make the note' : 'create'} ${ruled is PlanCreateList<N> ? ruled.title : (ruled as PlanCreateNote<N>).title}'}',
        );
        actions.addAll(_actionsOf<N>(ruled));
      }
      final polished = await polishActions<N>(actions, transcript, notes, ask, log);
      return finish(FinalInstructionOffer<N>(actions: polished, note: null, conversational: conversational));
    }
    // A table, a board, a book, a chapter, a move: read, but not carried out from a recording, and not worth the
    // model's time (a book is never written into by voice, docs/BOOKS.md).
    if (unmatched == null && plans.any((read) => read != null && read is! PlanNoNote<N> && !_isFinal(read))) {
      return finish(
        conversational
            ? const FinalInstructionOrdinary(notice: '$_unsupportedBare Saved this recording as a note.')
            : const FinalInstructionRejected(reason: _unsupported),
      );
    }
    log.step(plan != null ? 'rules: ${plans.length > 1 ? 'not every request could be read' : plan.kind}${unmatched != null ? ' ($unmatched)' : ''}' : 'rules: no known phrasing');
  } else if (!_hint.hasMatch(transcript) && !_namesATitle(transcript, titles)) {
    log.step('no request words: dictation');
    return finish(const FinalInstructionOrdinary(notice: null));
  } else {
    log.step('request words, no request shape: asking the model');
  }

  // 2. The model: sort.
  for (final line in await diagnostics()) {
    log.step(line);
  }
  final sorted = await ask('sort', null, transcript, titles);
  if (sorted is! StepAnswer) {
    final reason = sorted is StepRefused ? sorted.reason : (sorted as StepUnavailable).reason;
    log.step('sort ${sorted.status}: $reason');
    for (final line in await diagnostics()) {
      log.step(line);
    }
    if (sorted is StepRefused) return fail(reason);
    if (unmatched != null) return fail(unmatched);
    // Said aloud even for plain talk: a recording quietly saved as a note because the model could not be reached looks
    // like the app ignoring a request.
    return finish(FinalInstructionOrdinary<N>(notice: 'The on-device model was unavailable (${_cut(reason, 120)}); saved this recording as a note.'));
  }
  log.step('sort (${sorted.model}): ${sorted.raw}');
  final kind = readSort(sorted.answer);
  if (kind == null) {
    return unmatched != null
        ? fail(unmatched)
        : finish(FinalInstructionOrdinary<N>(notice: scan != null ? 'The model’s answer could not be read; saved this recording as a note.' : null));
  }
  if (kind == 'note') return (scan?.anchored ?? false) && unmatched != null ? fail(unmatched) : finish(FinalInstructionOrdinary<N>(notice: null));

  // 3. The model: plan.
  final planned = await ask('plan', kind, transcript, titles);
  if (planned is! StepAnswer) {
    final reason = planned is StepRefused ? planned.reason : (planned as StepUnavailable).reason;
    log.step('plan ${planned.status}: $reason');
    for (final line in await diagnostics()) {
      log.step(line);
    }
    return fail(planned is StepRefused ? reason : unmatched ?? 'Command understanding was unavailable.');
  }
  log.step('plan (${planned.model}): ${planned.raw}');
  final read = readPlan<N>(planned.answer, transcript, notes);
  if (read == null) return fail(unmatched ?? 'The model’s plan could not be read.');
  for (final problem in read.problems) {
    log.step('check: $problem');
  }
  if (read.actions.isEmpty) {
    final why = read.problems.isNotEmpty ? '${_sentenceCase(read.problems.first)}.' : null;
    return why != null || unmatched != null ? fail(why ?? unmatched ?? '') : finish(FinalInstructionOrdinary<N>(notice: null));
  }
  return finish(FinalInstructionOffer<N>(actions: read.actions, note: read.note, conversational: conversational));
}

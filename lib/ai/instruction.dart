/// One reader for a spoken instruction, with "hey Ghost" before it or without (docs/DESIGN.md §136): what the person
/// wants done, and to which note. A port of `src/app/ai/instruction.ts`. (The note's AI bar took typed ones too
/// until it was removed, docs/DESIGN.md §122.)
///
/// The rules are here, once, in the order they bite:
///
/// 1. The runs, said in words - "fix the spelling", "make this a list", "summarise it", "carry on" - are those runs
///    on the note on screen. Specific phrasings, read before anything else, so a model is never asked what a run's
///    own words already say. Without the keyword a run is the whole phrase and nothing more but its object: "fix the
///    spelling of Kowalski on the sign" is a sentence, which the keyword makes the run.
/// 2. A command that names another note - "add eggs to Groceries", "make a new list called Comic books" - is read by
///    the voice commands' reader (capture/final_instruction.dart): its rules first and the on-device model once when
///    the rules heard a name they could not match (a misheard title is what the model is for). What comes back is
///    offered on the confirm card before anything is written, as it always was for a recording. A command that named
///    a note there is no note for is refused, with its reason, after the keyword, since the person said it was a
///    command; without it, the words are the note's, and the reason is the chip's.
/// 3. Anything else is an ask about the note on screen, but only after the keyword; without it, speech is the note's
///    words.
///
/// What differs:
/// - `Read` is a sealed class ([ReadRun], [ReadCommand], [ReadReject], [ReadAsk], [ReadWords]), each with the web's
///   `kind` as a word.
/// - A candidate's body is `Candidate.noteBody` (capture/route.dart), the web's optional `note?.body`.
/// - The inference is the optional third argument, handed on to `classifyFinalTranscript`, which the web binds to the
///   native call inside `instructionIntent.ts`.
/// - The recorder's files keep a run's kind as the web's word (lib/capture/run_of.dart and
///   lib/capture/ui/read_instruction.dart, which call this file and say [RunKind.id]); here it is the [RunKind].
library;

import '../capture/command.dart' show FinalPlan, PlanPlace, findKeyword, findMisheard, isStandaloneCommandLike, leadIns, onlyFiller;
import '../capture/final_instruction.dart';
import '../capture/instruction_intent.dart' show InferenceRun;
import '../capture/live_command.dart' show Reading, bareCommand, bareShape, misheardShape, readRoute;
import '../capture/note_find.dart' show FoundResolved, findNote;
import '../capture/route.dart' show Candidate;
import '../core/book.dart' show isBookBody;
import 'kinds.dart';

/// What a spoken instruction was read as (`Read`).
sealed class Read<N extends Candidate> {
  const Read();

  /// The web's `kind`: `run`, `command`, `reject`, `ask` or `words`.
  String get kind;
}

/// One of the runs, on the note on screen.
final class ReadRun<N extends Candidate> extends Read<N> {
  const ReadRun({required this.run, this.instruction});

  final RunKind run;

  /// Words said with the run, when a caller has some to carry (the web's optional `instruction`); the reader itself
  /// gives none.
  final String? instruction;

  @override
  String get kind => 'run';
}

/// A command on a note by name, to be confirmed first.
final class ReadCommand<N extends Candidate> extends Read<N> {
  const ReadCommand({required this.plan});

  final FinalPlan<N> plan;

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

/// The lead-ins a person says before the thing itself (`LEAD`).
final RegExp _lead = RegExp(
  r'^\s*(?:(?:hey|hi|ok(?:ay)?|alright|all right|please|can you|could you|would you|will you|just|now|um+|uh+)[,.\s]+)+',
  caseSensitive: false,
);
final RegExp _leadingMarks = RegExp(r'^[\s.,;:!?…"“]+');
final RegExp _finalStops = RegExp(r'[.!?]+$');

/// The words themselves: a keyword at the start and the lead-ins gone. Null when the keyword is inside, not first;
/// filler before it ("Um, hey Ghost") leaves it first. A mishearing of it ("Hey, like, add…", "Hey goes, add…") is
/// taken off when a command follows (capture/command.dart `findMisheard`), but it is `misheard`, not `keyed`: it may start
/// a command for a note, which a card asks about, and never makes the words an ask or a run.
({String words, bool keyed, bool misheard})? bareWords(String text) {
  var words = text.trim().replaceFirst(_leadingMarks, '');
  var keyed = false;
  var misheard = false;
  for (var pass = 0; pass < 3; pass += 1) {
    final before = words;
    final keyword = findKeyword(words);
    final heard = keyword ?? (keyed || misheard ? null : findMisheard(words, (after) => isStandaloneCommandLike(after.replaceFirst(leadIns, ''))));
    if (heard != null) {
      if (!onlyFiller(heard.before)) return null;
      words = heard.after;
      if (keyword != null) {
        keyed = true;
      } else {
        misheard = true;
      }
    }
    words = words.replaceFirst(_lead, '').trim();
    // After the keyword, what a person says before the command goes too ("like, add…", "I want to add…"); without
    // it, those are the words ("And carry on tomorrow" is no run).
    if (keyed || misheard) words = words.replaceFirst(leadIns, '').trim();
    if (words == before) break;
  }
  return (words: words.replaceFirst(_finalStops, '').trim(), keyed: keyed, misheard: misheard);
}

/// The runs, said in words: each rule is the phrasings that mean one kind and nothing else.
final List<(RunKind, RegExp)> _runRules = [
  (RunKind.fix, RegExp(r'^(?:(?:fix|correct|check|clean up)(?:\s+(?:the|my|its|any))?\s+(?:spelling|grammar|typos?|punctuation|mistakes)|spell\s?check|proof\s?read)', caseSensitive: false)),
  (RunKind.summarize, RegExp(r'^(?:summari[sz]e|sum (?:it |this )?up|give me (?:a |the )?summary|tl;?dr)\b', caseSensitive: false)),
  (RunKind.format, RegExp(r'^(?:format|reformat|tidy(?: (?:it|this|up))?(?: up)?|clean (?:it |this )?up|organi[sz]e(?: it| this)?)\b(?!.*\b(?:spelling|grammar)\b)', caseSensitive: false)),
  (RunKind.enhance, RegExp(r'^(?:enhance|expand(?: on)?(?: it| this)?|flesh (?:it |this )?out|elaborate|make (?:it|this) (?:fuller|longer|richer|better))\b', caseSensitive: false)),
  (RunKind.continueWriting, RegExp(r"^(?:continue|carry on|keep (?:going|writing)|write more|go on|what(?:'s| is) next)\b", caseSensitive: false)),
  // "Make this a list", never "make a list called…", which is a new list by name (capture/command.dart `createList`).
  (
    RunKind.shape,
    RegExp(
      r'^(?:make|turn)\s+(?:this|it|the note|these|this note|everything)\s+(?:into\s+)?(?:a\s+|an\s+)?(?:list|to-?\s?do(?: list)?|task list|tasks|check\s?list|table|numbered list|bullet(?:ed)? list|bullets)\b',
      caseSensitive: false,
    ),
  ),
];

/// What may follow a run's words and leave it the run alone: its object ("summarise it for me", "tidy this up").
final RegExp _runRest = RegExp(r'^(?:\s+(?:it|this|that|the note|this note|everything|up|please|for me|now))*\s*$', caseSensitive: false);

/// The run a phrasing means, or null. With [whole], the run and nothing more: without the keyword, "fix the spelling
/// of Kowalski on the sign" is a sentence, not a run on the note, since the rules are anchored at the front and would
/// take any sentence that opens with one of them.
RunKind? runOf(String words, {bool whole = false}) {
  for (final (kind, rule) in _runRules) {
    final found = rule.firstMatch(words);
    if (found == null) continue;
    if (!whole || _runRest.hasMatch(words.substring(found.group(0)!.length))) return kind;
  }
  return null;
}

/// Whether the live reader's gate turned [words] down as a command for [note] (capture/live_command.dart `bareCommand`):
/// they have a bare command's shape for that note, and not one such reading passes the rest of the gate. Then a
/// transcript with no keyword is the note's words at Done too, and no card offers to send it there: "Add the flour
/// to the bowl", "Put this in the car, then drive" and "Add call the plumber to work" were cards here after the live
/// reader had kept them as words, and the card's Cancel lets the recording go.
bool _turnedDown<N extends Candidate>(String words, N note, List<N> notes) {
  final body = note.noteBody ?? '';
  final judged = <({Reading reading, double score})>[];
  for (final reading in readRoute(words)) {
    if (!bareShape(reading)) continue;
    final found = findNote<N>(reading.name, notes);
    if (found is FoundResolved<N> && found.note.id == note.id) judged.add((reading: reading, score: found.score));
  }
  return judged.isNotEmpty && !judged.any((j) => bareCommand(j.reading, (title: note.title, body: body), j.score, atStart: true));
}

final RegExp _unmatched = RegExp(r'^No unambiguous note matches “(.+?)”\.');
final RegExp _nameEnd = RegExp(r'\s*[,;:]\s*');
final RegExp _nothingChanged = RegExp(r'\.\s*Nothing changed\.$');

/// The reason a command said without the keyword was not carried out, for the words saved in its place: the name as
/// said, up to its first comma ("No note called “shopping”"), where the rules' reason carries the words after it too.
String _savedAsWords(String reason) {
  final name = _unmatched.firstMatch(reason)?.group(1)?.split(_nameEnd).first.trim();
  if (name != null && name.isNotEmpty) return 'No note called “$name”, so the words are saved as a note.';
  return reason.replaceFirst(_nothingChanged, ', so the words are saved as a note.');
}

final RegExp _noteWord = RegExp(r'\bnote\b', caseSensitive: false);
final RegExp _namedWords = RegExp('called|matches|No unambiguous', caseSensitive: false);

/// Reads a spoken instruction. [notes] are the person's notes, for a command that names one.
Future<Read<N>> readInstruction<N extends Candidate>(String text, List<N> notes, [InferenceRun Function(String words)? startInference]) async {
  final bare = bareWords(text);
  if (bare == null || bare.words.isEmpty) return ReadWords<N>();
  if (bare.misheard && !bare.keyed) {
    // "Hey, like, make sure the door is locked" is how people talk: after a mishearing of the keyword only a command
    // that passes the gate every bare phrase passes counts, as it does for the live reader, which its card asks
    // about; anything else is the note's words, never a run, an ask or a refusal.
    final clear = misheardShape(bare.words, (reading) {
      final found = findNote<N>(reading.name, notes);
      if (found is! FoundResolved<N>) return false;
      final body = found.note.noteBody ?? '';
      return !isBookBody(body) && bareCommand(reading, (title: found.note.title, body: body), found.score, atStart: true);
    });
    if (!clear) return ReadWords<N>();
    final decision = await classifyFinalTranscript<N>(bare.words, notes, startInference);
    return decision is FinalInstructionOffer<N> ? ReadCommand<N>(plan: decision.plan) : ReadWords<N>();
  }
  final run = runOf(bare.words, whole: !bare.keyed);
  if (run != null) return ReadRun<N>(run: run);
  final decision = await classifyFinalTranscript<N>(bare.words, notes, startInference);
  if (decision is FinalInstructionOffer<N>) {
    // Without the keyword, what the live reader's gate kept as words is words here too, not a card.
    final plan = decision.plan;
    if (!bare.keyed && plan is PlanPlace<N> && _turnedDown<N>(bare.words, plan.note, notes)) return ReadWords<N>();
    return ReadCommand<N>(plan: plan);
  }
  // A command that named a note fails closed after the keyword, with its reason; without it the words are the
  // note's, and the reason is the chip's. One the reader could make nothing of is an ask.
  final reason = decision is FinalInstructionRejected<N> ? decision.reason : null;
  final named = reason != null && _noteWord.hasMatch(reason) && _namedWords.hasMatch(reason);
  if (named) return bare.keyed ? ReadReject<N>(reason: reason) : ReadWords<N>(notice: _savedAsWords(reason));
  if (!bare.keyed) return ReadWords<N>(notice: decision is FinalInstructionOrdinary<N> ? decision.notice : null);
  return ReadAsk<N>(instruction: bare.words);
}

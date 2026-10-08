/// One reader for a spoken instruction, with "hey Ghost" before it or without: what the person wants done, and to
/// which note. A port of `bareWords`, `readInstruction`, `turnedDown` and `savedAsWords` from
/// `src/app/ai/instruction.ts`, which the recorder asks once, at Done, when the live reader carried out nothing
/// (capture_screen.dart `finish`).
///
/// The rules, in the order they bite:
///
/// 1. The runs, said in words - "fix the spelling", "make this a list", "summarise it", "carry on" - are those runs
///    on the note on screen (`run_of.dart`). Without the keyword a run is the whole phrase and nothing more but its
///    object: "fix the spelling of Kowalski on the sign" is a sentence, which the keyword makes the run.
/// 2. A command that names another note - "add eggs to Groceries", "make a new list called Comic books" - is read by
///    the voice commands' reader (`final_instruction.dart`): its rules first and the on-device model once when the
///    rules heard a name they could not match. What comes back is offered on the confirm card before anything is
///    written. A command that named a note there is no note for is refused, with its reason, after the keyword; without
///    it the words are the note's, and the reason is the chip's.
/// 3. Anything else is an ask about the note on screen, but only after the keyword; without it, speech is the note's
///    words.
///
/// What differs:
/// - It lives beside the recorder's screen, not in `lib/ai`: that folder is being written elsewhere and has no
///   `instruction.dart` yet. `runOf` is `lib/capture/run_of.dart`'s, the same private port the live reader uses. When
///   `lib/ai/instruction.dart` exists, this file goes and the screen imports that one.
/// - `Read` is a sealed class ([ReadRun], [ReadCommand], [ReadReject], [ReadAsk], [ReadWords]); a run's kind is the
///   web's word for it as a `String`, as in `run_of.dart`.
/// - The inference is the optional third argument, handed on to `classifyFinalTranscript`, which the web binds to the
///   native call inside `instructionIntent.ts`.
library;

import '../../core/book.dart' show isBookBody;
import '../command.dart' show FinalPlan, PlanPlace, findKeyword, findMisheard, isStandaloneCommandLike, leadIns, onlyFiller;
import '../final_instruction.dart';
import '../instruction_intent.dart' show InferenceRun;
import '../live_command.dart' show Reading, bareCommand, bareShape, misheardShape, readRoute;
import '../note_find.dart' show FoundResolved, findNote;
import '../route.dart' show Candidate;
import '../run_of.dart';

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
/// taken off when a command follows (`command.dart` `findMisheard`), but it is `misheard`, not `keyed`: it may start
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

/// Whether the live reader's gate turned [words] down as a command for [note] (`live_command.dart` `bareCommand`):
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

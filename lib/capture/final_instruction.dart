/// The reader at Done: one stopped recording, read once from its complete transcript, for the command it may be. A
/// port of `src/app/capture/finalInstruction.ts`.
///
/// What differs: the shapes. `FinalInstruction` is a sealed class ([FinalInstructionOrdinary],
/// [FinalInstructionOffer], [FinalInstructionRejected]). A note's body is read through its candidate's `noteBody`
/// (the web's `note?.body`), and whether it is a book with `lib/core/book.dart`. The inference is the optional
/// third argument, as on the web, and defaults to instruction_intent.dart's `inferInstruction` with no native side,
/// which answers that it is unavailable: the recorder passes its own, bound to the native call.
library;

import '../core/book.dart' show isBookBody;
import '../core/item_syntax.dart' show markerPattern;
import 'command.dart'
    show FinalPlan, PlacementHow, Plan, PlanNoNote, PlanPlace, finalCommandWords, planCommand, withoutPayloadLead;
import 'instruction_intent.dart'
    show
        InferenceResultIntent,
        InferenceResultUnavailable,
        InferenceRun,
        InstructionIntentAppend,
        InstructionIntentCreate,
        InstructionIntentNone,
        inferInstruction;
import 'instruction_mutation.dart' show literalMarkdown;
import 'list_append.dart' show InstructionArea;
import 'note_find.dart' show FoundResolved, FoundUnsure, findNote, nameWords;
import 'route.dart' show Candidate;
import 'spoken_list.dart' show spokenListItems;

/// What a finished recording is (`FinalInstruction`).
sealed class FinalInstruction<N extends Candidate> {
  const FinalInstruction();

  /// The web's `kind`: `ordinary`, `offer` or `rejected`.
  String get kind;
}

/// Words: a note of its own, with something to say about it or nothing.
final class FinalInstructionOrdinary<N extends Candidate> extends FinalInstruction<N> {
  const FinalInstructionOrdinary({required this.notice});

  final String? notice;

  @override
  String get kind => 'ordinary';

  @override
  bool operator ==(Object other) => other is FinalInstructionOrdinary && other.notice == notice;

  @override
  int get hashCode => Object.hash(kind, notice);

  @override
  String toString() => '{kind: ordinary, notice: $notice}';
}

/// A command the recorder can carry out, once its card is tapped.
final class FinalInstructionOffer<N extends Candidate> extends FinalInstruction<N> {
  const FinalInstructionOffer({required this.plan});

  final FinalPlan<N> plan;

  @override
  String get kind => 'offer';

  @override
  bool operator ==(Object other) => other is FinalInstructionOffer && other.plan == plan;

  @override
  int get hashCode => Object.hash(kind, plan);

  @override
  String toString() => '{kind: offer, plan: $plan}';
}

/// A command turned down, and why.
final class FinalInstructionRejected<N extends Candidate> extends FinalInstruction<N> {
  const FinalInstructionRejected({required this.reason});

  final String reason;

  @override
  String get kind => 'rejected';

  @override
  bool operator ==(Object other) => other is FinalInstructionRejected && other.reason == reason;

  @override
  int get hashCode => Object.hash(kind, reason);

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
const String _unsupported = 'That command is not supported from a voice capture. Nothing changed.';

/// Read one stopped recording, once, from its complete transcript: the reader at Done, which the recorder asks only
/// when the live reader (live_route.dart) carried out nothing as the words were said. The note named is found as the
/// live reader finds it (note_find.dart), for the rules' names and the model's alike.
Future<FinalInstruction<N>> classifyFinalTranscript<N extends Candidate>(
  String transcript,
  List<N> notes, [
  InferenceRun Function(String words)? startInference,
]) async {
  // "Hey Ghost, add…", "Okay, um, add…": the lead-in is not the command, but it must not turn the command back into
  // a note of its own words.
  final words = finalCommandWords(transcript);
  if (words == null) return FinalInstructionOrdinary<N>(notice: null);

  final Plan<N>? deterministic = planCommand<N>(words, notes: notes);
  // The rules heard a note name they could not match. The on-device model reads the same words once more before
  // that is the answer: it knows "my note labeled Go" means Go when the rules' phrasing list does not.
  final unmatched = deterministic is PlanNoNote<N> ? 'No unambiguous note matches “${deterministic.name}”. Nothing changed.' : null;
  if (deterministic != null && unmatched == null) {
    if (deterministic is PlanPlace<N> && deterministic.how == PlacementHow.leave) {
      // "Add to Movies Jaws, Alien and Heat": a list note takes several things as several items.
      final items = _listItems(words, deterministic.text, title: deterministic.note.title, body: deterministic.note.noteBody, asked: false);
      if (items != null) {
        return FinalInstructionOffer<N>(
          plan: PlanPlace<N>(
            note: deterministic.note,
            text: deterministic.text,
            how: PlacementHow.item,
            task: deterministic.task,
            many: true,
            near: deterministic.near,
            items: items,
          ),
        );
      }
    }
    // What a finished recording may do once confirmed: add to a note, or make a new list (with its items).
    return deterministic is FinalPlan<N> ? FinalInstructionOffer<N>(plan: deterministic) : FinalInstructionRejected<N>(reason: _unsupported);
  }

  // One constrained on-device pass, with this capture's complete transcript and no phrase history or prior session
  // context.
  final result = await (startInference ?? inferInstruction)(words).done;
  if (result is! InferenceResultIntent) {
    result as InferenceResultUnavailable;
    return unmatched != null
        ? FinalInstructionRejected<N>(reason: unmatched)
        : FinalInstructionOrdinary<N>(notice: 'Command understanding was unavailable; saved this recording as a note.');
  }
  final intent = result.intent;
  switch (intent) {
    case InstructionIntentNone():
      return FinalInstructionRejected<N>(reason: unmatched ?? 'That ${intent.reason.name} request was not changed.');
    case InstructionIntentCreate():
      return FinalInstructionRejected<N>(reason: unmatched ?? 'Creating a named note is not supported from a voice capture. Nothing changed.');
    case InstructionIntentAppend():
      break;
  }
  // The model's title as spoken, found as the rules find a name (note_find.dart): "house chores" is House TODOs.
  final target = findNote<N>(intent.target, notes);
  if (target is! FoundResolved<N>) {
    return FinalInstructionRejected<N>(
      reason:
          unmatched ??
          (target is FoundUnsure<N> ? '“${intent.target}” matches more than one note. Nothing changed.' : 'No note called “${intent.target}”. Nothing changed.'),
    );
  }
  // A book is never written into by voice (docs/BOOKS.md): the model's note is held to that as the rules' is
  // (command.dart `forBook`), and turned down the same way.
  final body = target.note.noteBody;
  if (body != null && isBookBody(body)) return FinalInstructionRejected<N>(reason: _unsupported);
  final area = intent.placement;
  // A list is told apart by the app, not the model: its items are literal text, one bullet each, whether or not the
  // model said "list".
  final content = withoutPayloadLead(intent.content);
  final namesList = area == InstructionArea.list || area == InstructionArea.tasks || area == InstructionArea.bugs;
  final said = area != InstructionArea.notes ? _listItems(words, content, title: target.note.title, body: body, asked: namesList) : null;
  final listed = namesList || said != null;
  final items = (said ?? const <String>[]).map(literalMarkdown).toList();
  return FinalInstructionOffer<N>(
    plan: PlanPlace<N>(
      note: target.note,
      text: literalMarkdown(content),
      how: area == InstructionArea.notes
          ? PlacementHow.paragraph
          : listed
          ? PlacementHow.item
          : PlacementHow.leave,
      task: area == InstructionArea.tasks,
      many: items.length > 1,
      near: area == InstructionArea.bugs ? 'bugs' : null,
      items: items.length > 1 ? items : null,
    ),
  );
}

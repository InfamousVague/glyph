/// The live reader: a committed phrase read as it is said, for one family of command, "words for a note you name".
///
/// Matt: "It should first step try to find a note that the person is talking about … then when it's found that note,
/// it should look through the note and see what different things I could be talking about adding to … then it should
/// modify that note, open the note, and start live writing to that note instead of doing the second pass over at the
/// end." A phrase is read at each commit, for these commands only:
///
/// - "Hey Ghost, add a note to House TODOs. Call an electrician." At the start of a fresh recording the recorder
///   switches to that note, for good (`route`): its page shows the note, and what is said is written into its list.
/// - Mid-take, or on a note's own Speak, "add call Sam to House TODOs" puts those words there (`insert`) and the take
///   carries on where it was. "Move this to …" is the one command that moves the take. "Add call the plumber to House
///   TODOs", with no keyword at all, does the same (`bare`).
/// - "Remind me to…", "add a to-do: …": a to-do in the note being written to (`self`). "New note": a fresh one.
/// - "Scratch that", "actually, …", "no wait, four" and "scratch that, add it to X instead" take back the last thing
///   said in this take: gone, replaced, one word changed, or sent to a note named (`takeBack`, docs/DESIGN.md §130).
///   "Hey Ghost, actually, add a note to X" is that command, said as people say it.
///
/// Nothing it does is stored: the recorder draws the words where they will go, and Done writes each note once,
/// fresh. So a wrong switch is seen, and put right with Not this note ([LiveRoute.decline]), Discard or Undo; nothing
/// has to be taken back from the store. It never deletes or replaces text it did not write in this take. A take-back
/// takes back the last thing this take said, shows what went with Undo, never engages the reader, and stores
/// nothing, since nothing is stored before Done; it never runs a table, a board, a book, a plugin or an AI run; a run
/// or an ask said mid-take is queued for after Done.
///
/// A phrase is read whether or not it opens with the keyword (docs/DESIGN.md §136). Without it, only a command
/// plainly about a note it names clearly, with its words in the same breath, is one, through one gate
/// (`live_command.dart` `bareCommand`, asked by `_clear`); anything short of that is words, untouched. The keyword
/// adds what a bare phrase never gets: a card for an unsure or missing name, a hold for an opener waiting for its
/// name, an ask or a run, the name-first shapes ("For Groceries, …"), a heading or lane of the note being written
/// to, a command said in pieces, and the take-back waiver of §130. An unsure name, or one that matches nothing but
/// comes near a title, gets a card after the keyword; no card blocks anything, since each takes Keep here after a
/// while, and at once when the recording ends ([LiveRoute.close]).
///
/// A state machine with its own clock handed in, and no screen: the recorder applies its steps. Pure, so every rule
/// is a test.
///
/// A port of `src/app/capture/liveRoute.ts`.
///
/// What differs:
/// - The web's notes are structural (`N extends LiveNote`, anything with an id and a body). Here `N` is any object
///   the reader can read an id and a body from ([liveNoteId], [liveNoteBody]): a [LiveNote], a take's `TakeNote`, or
///   the library's own `Note`.
/// - `LIVE_TIMING` is [liveTiming], a record. `LiveRoute.final` is [LiveRoute.final_], `final` being a word of Dart's. `LiveCard.form` is the enum [LiveCardForm], and a step's `haptic` is
///   `take_host.dart`'s `Haptic`.
/// - An ask's `run` is the web's word for the kind of run ('fix', 'summarize', …) as a `String`, read by
///   `run_of.dart`, a private port of `runOf` (`src/app/ai/instruction.ts`), since `lib/ai` is not here yet.
/// - The web sorts with `Array.prototype.sort`; where the order among equals can show (the readings of a command,
///   whose comparison is not a total order), the same insertion sort V8 runs for a short array is run here.
library;

import '../core/book.dart';
import '../core/note.dart' show Note;
import '../core/text.dart';
import 'command.dart';
import 'list_append.dart' show Run, runsOf, semanticListKind;
import 'live_command.dart';
import 'markdown.dart';
import 'note_find.dart';
import 'place.dart' hide Placed;
import 'route.dart' show Candidate;
import 'run_of.dart';
import 'take_back.dart';
import 'take_host.dart';
import 'take_types.dart';

/// The live reader's timings, in ms (`LIVE_TIMING`).
///
/// - `holdMs`: a command held for its name: this long after its last phrase, and it gives up.
/// - `holdPhrases`: the most phrases a held command waits for its name.
/// - `growMs`: a name that may still be growing: the next phrase, said this soon after it on the recording, is read
///   with it.
/// - `itemsQuietMs`: a one-shot with nothing said for it: its phrases until a pause this long.
/// - `itemsPhrases`: and at most this many of them.
/// - `cardMs`: a card up this long takes its default, Keep here.
/// - `takeBackMs`: a take-back's Undo: this long on the reader's clock, then it settles and its stretches are marked
///   for the better words. Longer than the chip's four seconds (chip.dart), so a button drawn is a button that works.
/// - `bareScore`: a resolved name must score this well to route with no keyword said, or after a mishearing of it:
///   the alias of `find.clear`.
/// - `nameWords`: a name that ran to the end of what was said, and is longer than this many words, is more than a
///   title: Keep here gives back all of it ("add a note to moon base pack sunscreen and the tent").
final ({int holdMs, int holdPhrases, int growMs, int itemsQuietMs, int itemsPhrases, int cardMs, int takeBackMs, double bareScore, int nameWords}) liveTiming = (
  holdMs: 4500,
  holdPhrases: 3,
  growMs: 2500,
  itemsQuietMs: 2500,
  itemsPhrases: 3,
  cardMs: 8000,
  takeBackMs: 5000,
  bareScore: find.clear,
  nameWords: 4,
);

/// A note as the live reader sees it: its id and its body.
abstract interface class LiveNote {
  String get id;
  String get body;
}

/// The id of a note the reader was given: a [LiveNote]'s, a `TakeNote`'s, or the library's `Note`'s.
String liveNoteId(Object note) => switch (note) {
  final LiveNote note => note.id,
  final TakeNote note => note.id,
  final Note note => note.id,
  _ => throw ArgumentError.value(note, 'note', 'not a note the live reader can read'),
};

/// The body of a note the reader was given.
String liveNoteBody(Object note) => switch (note) {
  final LiveNote note => note.body,
  final TakeNote note => note.body,
  final Note note => note.body,
  _ => throw ArgumentError.value(note, 'note', 'not a note the live reader can read'),
};

/// A note a command can name, as the recorder's candidates carry it (capture/candidates.dart).
class LiveCandidate<N extends Object> extends Candidate {
  const LiveCandidate({required super.id, required super.title, required this.note});

  final N note;

  @override
  String? get noteBody => liveNoteBody(note);

  @override
  bool operator ==(Object other) => other is LiveCandidate && other.id == id && other.title == title && other.note == note;

  @override
  int get hashCode => Object.hash(id, title, note);

  @override
  String toString() => '{id: $id, title: $title, note: $note}';
}

class LiveContext<N extends Object> {
  const LiveContext({required this.notes, required this.aim, required this.own, required this.locked, this.published});

  final List<LiveCandidate<N>> notes;

  /// The note being written to now, or null for the take's own new note.
  final N? aim;

  /// The take is a note's own Speak, and [aim] is that note.
  final bool own;

  /// Over the lock screen: no card, no title said, and no shared note is written to.
  final bool locked;

  /// Whether a note is shared, or is a chapter of a shared book (share/share.ts).
  final bool Function(String id)? published;
}

/// What a card is for: a name that was unsure, one that matched none, or the choice after Not this note.
enum LiveCardForm { unsure, missing, declined }

/// A card: which note, when the name was unsure or matched none.
class LiveCard<N extends Object> {
  const LiveCard({required this.id, required this.form, required this.heading, required this.candidates, required this.newTitle, required this.payload});

  final int id;
  final LiveCardForm form;

  /// "Add to which note?", "No note called “the moon base”", "Not added to House TODOs".
  final String heading;

  /// The notes to choose between.
  final List<LiveCandidate<N>> candidates;

  /// The title "New note “…”" would make.
  final String newTitle;

  /// What would land, for the card to show.
  final String payload;

  @override
  String toString() => '{id: $id, form: ${form.name}, heading: $heading, candidates: $candidates, newTitle: $newTitle, payload: $payload}';
}

/// A card's answer: a note, a new note, or Keep here.
sealed class CardChoice {
  const CardChoice();
}

final class CardChoiceNote extends CardChoice {
  const CardChoiceNote({required this.id});

  final String id;

  @override
  bool operator ==(Object other) => other is CardChoiceNote && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class CardChoiceNew extends CardChoice {
  const CardChoiceNew();
}

final class CardChoiceKeep extends CardChoice {
  const CardChoiceKeep();
}

/// What the recorder does with a phrase, in order.
sealed class LiveStep<N extends Object> {
  const LiveStep();

  /// The web's `kind`.
  String get kind;
}

/// Words of the take, drawn and saved with it. [payload] marks what a command sent.
final class LiveStepWords<N extends Object> extends LiveStep<N> {
  const LiveStepWords({required this.segment, this.payload});

  final Segment segment;
  final bool? payload;

  @override
  String get kind => 'words';
}

/// Words of the take given back out of it, to go elsewhere (a card answered for a one-shot).
final class LiveStepUnword<N extends Object> extends LiveStep<N> {
  const LiveStepUnword({required this.segments});

  final List<Segment> segments;

  @override
  String get kind => 'unword';
}

/// A stretch that was a command, for the better words to leave out.
final class LiveStepCommand<N extends Object> extends LiveStep<N> {
  const LiveStepCommand({required this.span});

  final Span span;

  @override
  String get kind => 'command';
}

/// A phrase that was words and then the keyword: the better words keep what came before it.
final class LiveStepKeyword<N extends Object> extends LiveStep<N> {
  const LiveStepKeyword({required this.span});

  final Span span;

  @override
  String get kind => 'keyword';
}

/// The take goes to [note] from here, words so far and all: sticky, until "move this", "new note" or Not this note.
final class LiveStepRoute<N extends Object> extends LiveStep<N> {
  const LiveStepRoute({required this.note, required this.title, required this.placing, required this.move, required this.spot});

  final N note;
  final String title;
  final Placing placing;
  final bool move;
  final String? spot;

  @override
  String get kind => 'route';
}

/// The take goes to a note that does not exist yet, made at Done with this title ("New note “House chores”").
final class LiveStepRouteNew<N extends Object> extends LiveStep<N> {
  const LiveStepRouteNew({required this.title, required this.task});

  final String title;
  final bool task;

  @override
  String get kind => 'route-new';
}

/// The take's own note again (Not this note).
final class LiveStepHome<N extends Object> extends LiveStep<N> {
  const LiveStepHome();

  @override
  String get kind => 'home';
}

/// How the words go into the note being written to changed: a heading said for it, or a to-do.
final class LiveStepPlacing<N extends Object> extends LiveStep<N> {
  const LiveStepPlacing({required this.placing});

  final Placing placing;

  @override
  String get kind => 'placing';
}

/// A one-shot opened for [note]: [segments] go there, not into the take. More may follow ([LiveStepInsertWords]).
final class LiveStepInsert<N extends Object> extends LiveStep<N> {
  const LiveStepInsert({required this.id, required this.note, required this.title, required this.placing, required this.segments});

  final int id;
  final N note;
  final String title;
  final Placing placing;
  final List<Segment> segments;

  @override
  String get kind => 'insert';
}

final class LiveStepInsertWords<N extends Object> extends LiveStep<N> {
  const LiveStepInsertWords({required this.id, required this.segments});

  final int id;
  final List<Segment> segments;

  @override
  String get kind => 'insert-words';
}

/// Words given to a one-shot, taken out of it again (a take-back or its Undo); a one-shot with nothing left is not
/// written.
final class LiveStepInsertUnword<N extends Object> extends LiveStep<N> {
  const LiveStepInsertUnword({required this.id, required this.segments});

  final int id;
  final List<Segment> segments;

  @override
  String get kind => 'insert-unword';
}

/// A one-shot closed: the take carries on where it was.
final class LiveStepInsertEnd<N extends Object> extends LiveStep<N> {
  const LiveStepInsertEnd({required this.id});

  final int id;

  @override
  String get kind => 'insert-end';
}

/// A one-shot taken out again (its Not this note): its words back into the take, at their time.
final class LiveStepInsertDrop<N extends Object> extends LiveStep<N> {
  const LiveStepInsertDrop({required this.id});

  final int id;

  @override
  String get kind => 'insert-drop';
}

/// "New note": the words so far stay with the note they were said for, and a fresh note starts.
final class LiveStepNewNote<N extends Object> extends LiveStep<N> {
  const LiveStepNewNote();

  @override
  String get kind => 'new-note';
}

final class LiveStepCard<N extends Object> extends LiveStep<N> {
  const LiveStepCard({required this.card});

  final LiveCard<N>? card;

  @override
  String get kind => 'card';
}

/// A run or an ask, for the note that opens after Done. [run] is the web's `RunKind` word, or null for an ask.
final class LiveStepAsk<N extends Object> extends LiveStep<N> {
  const LiveStepAsk({required this.run, required this.instruction});

  final String? run;
  final String instruction;

  @override
  String get kind => 'ask';
}

/// What the chip at the foot says.
final class LiveStepChip<N extends Object> extends LiveStep<N> {
  const LiveStepChip({required this.view});

  final RouteView? view;

  @override
  String get kind => 'chip';
}

final class LiveStepHaptic<N extends Object> extends LiveStep<N> {
  const LiveStepHaptic({required this.haptic});

  final Haptic haptic;

  @override
  String get kind => 'haptic';
}

/// A line for the review's check of commands, and the take's log.
final class LiveStepLog<N extends Object> extends LiveStep<N> {
  const LiveStepLog({required this.line});

  final String line;

  @override
  String get kind => 'log';
}

/// Why a command is held: the keyword was said in the first of its phrases, or they are only its lead ("Hey."), or
/// only filler ("Okay."), or its name was unsure.
enum _Why { keyword, lead, filler, unsure }

class _Held {
  _Held({required this.segments, required this.why, required this.lastAt, this.name});

  final List<Segment> segments;
  final _Why why;
  final int lastAt;

  /// The name heard so far, for the chip: "Looking for “house”".
  final String? name;
}

/// Where the reader put words: on the page (the take) or into a one-shot.
class _Where {
  const _Where.take() : id = null;
  const _Where.insert(int this.id);

  /// The one-shot's id, or null for the take.
  final int? id;

  bool get isTake => id == null;
}

const _Where _take = _Where.take();

class _Stays {
  _Stays({required this.text, required this.after, required this.from});

  final String text;
  final List<Segment> after;
  final _Where from;
}

class _Pending<N extends Object> {
  _Pending({required this.card, required this.since, required this.command, required this.payload, required this.reading, required this.atStart, required this.after, this.declined, this.stays});

  final LiveCard<N> card;
  final int since;

  /// The command phrase the card holds.
  final Segment command;
  final String payload;
  final Reading reading;

  /// The take was at its start: a choice is sticky.
  final bool atStart;

  /// Phrases said since, which went to the page as words.
  List<Segment> after;

  /// A card after Not this note: the note declined, and the name it was declined for.
  final ({String id, String name})? declined;

  /// A take-back's send that was not sure of its note: the words are on the page while it asks ([after] holds
  /// them), and Keep here puts them back where they were, a one-shot's into it (`from`), and says so.
  final _Stays? stays;
}

class _Opened<N extends Object> {
  _Opened({required this.id, required this.note, required this.title, required this.count, required this.lastAt, required this.words});

  final int id;
  final N note;
  final String title;
  int count;
  int lastAt;

  /// The command's words as heard, the stop off, for the chip that cancels it.
  final String words;
}

/// Words the reader put somewhere in this take: on the page (the take) or into a one-shot.
class _Placed {
  _Placed({required this.where, required this.segment, required this.from});

  final _Where where;
  final Segment segment;

  /// The source phrase: where it went and its stretch, so an enumeration's items are one thing.
  final String from;
}

enum _Outcome { gone, sent, placed, changed, replaced }

class _DoneEntry {
  _DoneEntry({required this.segments, required this.words});

  final List<Segment> segments;
  final String words;
}

/// The last take-back, undoable until it settles.
class _TookBack {
  _TookBack({
    required this.id,
    required this.phrase,
    required this.keyed,
    required this.headBeforeKeyword,
    required this.removed,
    required this.taken,
    required this.placed,
    required this.outcome,
    required this.dropOnly,
    required this.fragment,
    required this.sent,
    required this.doneReader,
    required this.quote,
    required this.since,
  });

  final int id;

  /// The opener and its rest as said, keyword and head off: what Undo writes as words, on the phrase's stretch.
  final Segment phrase;

  /// "Hey Ghost" was said before the opener: Undo marks the stretch `keyword`, as `_read` marks one.
  final bool keyed;

  /// The head came before the keyword: the phrase is marked `keyword` at settle, else `command`.
  final bool headBeforeKeyword;

  /// What came off the page or out of a one-shot, in order: one source phrase's group.
  List<_Placed> removed;

  /// What went, as it would move on a send: the last sentence alone when the phrase held several.
  final List<Segment> taken;

  /// What it put in their place.
  List<_Placed> placed;
  _Outcome outcome;

  /// A bare drop, nothing said after the opener, or only a send's opener: a send in the next breath is its second half.
  bool dropOnly;

  /// A send's opener Whisper cut from its name: never written, the name read with it.
  final String? fragment;

  /// A send: the one-shot it made.
  ({int id, String title})? sent;

  /// A phrase the reader at Done was to read, taken out of `_doneReader`: back there on Undo.
  final _DoneEntry? doneReader;

  /// What went, as the chip said it, for the landing when Done settles it unseen.
  final String quote;

  /// A send said in a breath of its own: its phrase, marked with the take-back's when it settles.
  List<Segment>? sends;
  int since;
}

class _Growing<N extends Object> {
  _Growing({required this.reading, required this.score, required this.command, required this.words, required this.into, required this.note});

  final Reading reading;
  final double score;
  final Segment command;

  /// The command's words as heard, the stop gone, to be read again with the next phrase.
  final String words;

  /// Where the name went: the route (null), or the one-shot (its id).
  final int? into;
  final N note;
}

class _Routed {
  _Routed({required this.id, required this.title, required this.awaiting, required this.name, required this.words});

  final String id;
  final String title;
  bool awaiting;
  final String name;
  final String words;
}

class _Scored<N extends Object> {
  _Scored(this.reading, this.found);

  final Reading reading;
  final Found<LiveCandidate<N>> found;
}

Segment _withText(Segment segment, String text) => Segment(startMs: segment.startMs, endMs: segment.endMs, text: text);

/// A stretch of a segment.
Span _spanOf(Segment segment) => Span(startMs: segment.startMs, endMs: segment.endMs);

/// Whether two phrases are the one phrase: the same stretch and the same words ([withoutWords] knows them so).
bool _same(Segment a, Segment b) => a.startMs == b.startMs && a.endMs == b.endMs && a.text == b.text;

/// The source phrase a placed segment came from: where it went, and the stretch it was said over.
String _fromOf(_Where where, Segment segment) => '${where.isTake ? 'take' : 'insert ${where.id}'}|${segment.startMs}-${segment.endMs}';

/// What a chip can hold of a sentence.
String _cut(String text) => text.length > 40 ? '${text.substring(0, 40)}…' : text;

/// `Array.prototype.sort` as V8 runs it for a short array (under 32, a binary insertion sort after its first run),
/// in place: stable, and the same answer as the web's for a comparison that is not a total order.
void _sort<T>(List<T> list, num Function(T a, T b) compare) {
  final n = list.length;
  if (n < 2) return;
  var run = 2;
  if (compare(list[1], list[0]) < 0) {
    while (run < n && compare(list[run], list[run - 1]) < 0) {
      run += 1;
    }
    for (var low = 0, high = run - 1; low < high; low += 1, high -= 1) {
      final swap = list[low];
      list[low] = list[high];
      list[high] = swap;
    }
  } else {
    while (run < n && compare(list[run], list[run - 1]) >= 0) {
      run += 1;
    }
  }
  for (var start = run; start < n; start += 1) {
    final pivot = list[start];
    var left = 0;
    var right = start;
    while (left < right) {
      final mid = left + ((right - left) >> 1);
      if (compare(pivot, list[mid]) < 0) {
        right = mid;
      } else {
        left = mid + 1;
      }
    }
    for (var p = start; p > left; p -= 1) {
      list[p] = list[p - 1];
    }
    list[left] = pivot;
  }
}

/// A take's words in the order they were said. A card's words land when it settles, after what was said while it was
/// up, so they can arrive out of order; the sort is stable, so the pieces of one phrase keep theirs. The same list
/// when nothing moved.
List<Segment> inOrder(List<Segment> segments) {
  var ordered = true;
  for (var i = 1; i < segments.length; i += 1) {
    if (segments[i - 1].startMs > segments[i].startMs) {
      ordered = false;
      break;
    }
  }
  if (ordered) return segments;
  // Stable, as the web's is: each put after those that start no later.
  final out = <Segment>[];
  for (final segment in segments) {
    var at = out.length;
    while (at > 0 && out[at - 1].startMs > segment.startMs) {
      at -= 1;
    }
    out.insert(at, segment);
  }
  return out;
}

/// A take's words without [gone] (an `unword` step), each known by its stretch and its words.
List<Segment> withoutWords(List<Segment> segments, List<Segment> gone) => segments.where((segment) => !gone.any((g) => _same(g, segment))).toList();

final RegExp _sentenceEnd = RegExp(r'[.!?…:]$');

/// Words as a sentence: first letter up, a stop at the end.
String _sentence(String text) {
  final said = capitalise(text.trim());
  return said.isEmpty || _sentenceEnd.hasMatch(said) ? said : '$said.';
}

final RegExp _payloadTail = RegExp(r'[\s.!?…]+$');
final RegExp _listSplit = RegExp(r'\s*(?:,|\band\b)\s*', caseSensitive: false);
final RegExp _spaces = RegExp(r'\s+');

/// A payload as the take's words: one sentence; or, said as a short enumeration ("milk, eggs and bread") or as an
/// item of a list, the cue-marked items the renderer lays out as a list ("Check box: call Sam.", capture/markdown.dart),
/// each on the command phrase's stretch of the recording.
List<Segment> payloadWords(Segment whole, String payload, {bool item = false, bool task = false}) {
  final words = payloadOf(payload).trim();
  final said = words.replaceFirst(_payloadTail, '');
  if (said.isEmpty) return [];
  final pieces = said.contains(',') ? said.split(_listSplit).map((piece) => piece.trim()).where((piece) => piece.isNotEmpty).toList() : const <String>[];
  final listed = pieces.length >= 2 && pieces.every((piece) => piece.split(_spaces).length <= 4) ? pieces : null;
  // As it was said: a phrase Whisper cut before its stop runs on into the next ("…fix the light" | "sockets.").
  if (listed == null && !item) return [_withText(whole, capitalise(words))];
  final cue = task ? 'Check box' : 'Bullet point';
  return [for (final piece in listed ?? [said]) _withText(whole, '$cue: $piece.')];
}

/// What a command said of the words it sent, for where they go (place.dart `placingFor`): a to-do, or a paragraph.
Said _saidOf(Reading reading) => Said(task: reading.placing == ReadingPlacing.task, paragraph: reading.placing == ReadingPlacing.paragraph);

final RegExp _afterStop = RegExp(r'(?<=[.!?])\s+');

/// The first two lines of what would land, lead-ins gone, for a card to show.
String _shown(String payload) => payloadOf(payload).split(_afterStop).take(2).join(' ');

final RegExp _articles = RegExp(r'^(?:(?:the|my|our|a)\s+)+', caseSensitive: false);
final RegExp _stops = RegExp(r'[.!?]+$');

/// "the moon base" as the title a new note for it would take: "Moon base".
String _titleFor(String name) => capitalise(name.trim().replaceFirst(_articles, '').replaceFirst(_stops, ''));

/// What stays here when a name finds no note: the payload; or, when the name ran to the end of what was said and is
/// longer than a title, everything said after the verb, since the grammar cannot tell where such a name ends ("add a
/// note to moon base pack sunscreen and the tent" keeps "Moon base pack sunscreen and the tent.").
String _keptWords(Reading reading, String payload) {
  if (reading.stopped || reading.nameFirst || reading.split || reading.tail.isEmpty) return payload;
  // Ended as a sentence, as the phrase it was the end of was.
  return reading.name.split(_spaces).length > liveTiming.nameWords ? _sentence(payloadOf(reading.tail)) : payload;
}

final RegExp _leadingMarks = RegExp(r'^[\s.,;:!?…]+');
final RegExp _endsWithStop = RegExp(r'[.!?…]$');
final RegExp _check = RegExp('check', caseSensitive: false);
final RegExp _answerLead = RegExp(r'^(?:um+|uh+|er+|ok(?:ay)?|so)[,\s]+');
final RegExp _keepHere = RegExp(r'^keep(?:\s+it)?\s+here$');
final RegExp _aNewNote = RegExp(r'^(?:a\s+)?new\s+note$');
final RegExp _nth = RegExp(r'^the\s+(first|second|third)(?:\s+one)?$');
final RegExp _newNote = RegExp(r'^new\s+note$', caseSensitive: false);

class LiveRoute<N extends Object> {
  bool _engagedYet = false;
  bool _closed = false;
  _Held? _held;
  _Pending<N>? _pending;
  _Opened<N>? _opened;
  _Growing<N>? _growing;

  /// The note the take was routed to, sticky: `awaiting` while nothing has been said for it yet; `words` for the chip
  /// that cancels it.
  _Routed? _routed;
  final Set<String> _declined = {};

  /// Keyworded phrases at the take's start, left as words for the reader at Done (`_late`).
  final List<_DoneEntry> _doneReader = [];
  int _nextId = 1;

  /// Every phrase the reader put somewhere in this take, in the order they were said (by start, then as emitted), as
  /// the page shows them.
  List<_Placed> _said = [];

  /// The last take-back, until it settles.
  _TookBack? _undoable;

  /// A take-back ran, spans pushed or to come: the take's words are not the transcript's ([changedWords]).
  bool _tookBackYet = false;

  /// Take-backs settled by [close], quoted, for the landing to name.
  final List<String> _closedWith = [];

  /// "New note" was said or tapped: the take is past its start, whatever the page holds now.
  bool _sealedYet = false;

  /// What `_command` answers when it holds the phrase for its name, or leaves it to the reader at Done: known by
  /// which list it is, never by what is in it (the web's `HELD` and `DONE_READER` symbols).
  final List<LiveStep<N>> _heldMark = List.unmodifiable(const []);
  final List<LiveStep<N>> _doneReaderMark = List.unmodifiable(const []);

  /// The reader has done something: routed, inserted, placed, raised a card, kept a payload, queued an ask.
  bool get engaged => _engagedYet;

  /// The take's words are not the transcript's: a command was carried out, or something was taken back. The recorder
  /// reads the take's phrases, not the transcript, at Done, and hands them to the better words.
  bool get changedWords => _engagedYet || _tookBackYet;

  /// What Done settled unseen, for the note's toast: each take-back still open when the recording ended, quoted.
  List<String> get tookBackAtDone => _closedWith;

  /// Words of the take are on the page: something that lays out as anything.
  bool get _kept => _said.any((placed) => placed.where.isTake && _renderable(placed.segment.text));

  /// The take is at its start: nothing on the page, nothing done, and no note sealed by "New note". A route said here
  /// is sticky.
  bool get _atStart => !_kept && !_engagedYet && !_sealedYet;

  /// A bare drop is waiting for a send in the next breath ("Scratch that." | "Add it to Groceries."): the partial
  /// starting one belongs in the chip.
  bool get sendOpen => _undoable?.dropOnly == true;

  /// A command is being held, a one-shot is open, a card is up, or a take-back can still be undone: the recording
  /// stays open.
  bool get holding => _held != null || _opened != null || _pending != null || _undoable != null;

  /// A note was routed to and nothing has been said for it yet: the phrase still being heard belongs in the chip.
  bool get awaitingPayload => _routed?.awaiting == true;

  /// A command is being said, waiting for its name, or a one-shot is taking its words: the phrase still being heard
  /// is the command's, for the chip, not the page's. A card up is not: what is said meanwhile goes to the page.
  bool get hearingCommand => _held != null || _opened != null || _routed?.awaiting == true;

  /// The card up now, if one is.
  LiveCard<N>? get card => _pending?.card;

  // ---- a phrase ---------------------------------------------------------------------------------

  /// A committed phrase: what the recorder does with it.
  List<LiveStep<N>> phrase(Segment said, LiveContext<N> ctx, int now) => _late(_heard(said, ctx, now), ctx);

  /// A phrase read. [took] is set when the phrase is the take-back half of one cut in two by `_takeBack`: whether the
  /// keyword came before it, and whether the head did.
  List<LiveStep<N>> _heard(Segment said, LiveContext<N> ctx, int now, [({bool keyed, bool headBeforeKeyword})? took]) {
    final text = said.text.replaceFirst(_leadingMarks, '');
    if (text.isEmpty) return [];
    final segment = _withText(said, text);
    if (_closed) return [_words(segment)];
    final steps = <LiveStep<N>>[];

    // A card up: this phrase may be its answer. Not this note's card goes at the next phrase.
    if (_pending != null) {
      final answer = _spokenAnswer(text);
      if (answer != null) return [LiveStepCommand(span: _spanOf(segment)), ..._settle(answer, ctx)];
      if (_pending!.declined != null) steps.addAll(_settle(const CardChoiceKeep(), ctx));
    }

    // A name that may still be growing: this phrase, read with it.
    final growing = _growing;
    _growing = null;
    // The last thing said, taken back: before a name could grow into "scratch that", and before a held command, an
    // open one-shot or a note waiting for its words could take it as theirs.
    final taken = _takeBack(segment, ctx, now, took);
    if (taken != null) return [...steps, ...taken];
    // Measured on the recording, from the end of the command to the start of this phrase: a long phrase is committed
    // well after it began.
    if (growing != null && segment.startMs - growing.command.endMs <= liveTiming.growMs) {
      final grown = _grow(growing, segment, ctx, now);
      if (grown != null) return [...steps, ...grown];
    }

    final keyed = hearKeyword(text, (words) => _readsAsRoute(words, ctx)) != null;
    // A command held for its name: read again, joined. Unless the keyword is said again: then the held command got no
    // name, and this phrase is a command of its own ("Hey Ghost, add to signing." | "Hey Ghost, add milk to groceries.").
    if (_held != null) {
      if (!keyed || _held!.why == _Why.lead || _held!.why == _Why.filler) return [...steps, ..._readHeld(segment, ctx, now)];
      steps.addAll(_letGoHeld(ctx, now));
    }

    // A one-shot with nothing said for it yet: its phrases, until a pause. Each is marked, so the better words leave
    // it out of the take's own note (refine_text.dart).
    final opened = _opened;
    if (opened != null && !keyed) {
      opened.count += 1;
      opened.lastAt = now;
      final theirs = opened.count == 1 ? payloadWords(segment, text) : [segment];
      steps.add(LiveStepCommand(span: _spanOf(segment)));
      for (final piece in theirs) {
        steps.add(_place(_Where.insert(opened.id), piece));
      }
      if (opened.count >= liveTiming.itemsPhrases) steps.addAll(_closeInsert());
      return steps;
    }
    if (opened != null) steps.addAll(_closeInsert());
    // A note routed to, and nothing said for it yet: this is what it is for.
    if (_routed?.awaiting == true && !keyed) {
      _routed!.awaiting = false;
      return [...steps, ..._payload(segment, text), const LiveStepChip(view: null)];
    }
    final pending = _pending;
    final read = _read(segment, ctx, now);
    // What is said with a card up goes to the page as words, and is what a one-shot chosen on the card takes.
    final first = read.length == 1 ? read[0] : null;
    final word = first is LiveStepWords<N> && identical(first.segment, segment);
    if (pending != null && identical(_pending, pending) && word) pending.after.add(segment);
    return [...steps, ...read];
  }

  /// The clock: holds give up, cards take their default, a one-shot closes after a pause, a take-back settles.
  List<LiveStep<N>> tick(int now, LiveContext<N> ctx) {
    final steps = <LiveStep<N>>[];
    if (_held != null && now - _held!.lastAt > liveTiming.holdMs) steps.addAll(_letGoHeld(ctx, now));
    if (_pending != null && now - _pending!.since > liveTiming.cardMs) steps.addAll(_settle(const CardChoiceKeep(), ctx));
    if (_opened != null && now - _opened!.lastAt > liveTiming.itemsQuietMs) steps.addAll(_closeInsert());
    if (_undoable != null && now - _undoable!.since > liveTiming.takeBackMs) steps.addAll(_settleTakeBack());
    return _late(steps, ctx);
  }

  /// A take-back's Undo, tapped: what went comes back, and what was said is written as words.
  List<LiveStep<N>> undoTakeBack(int id) {
    final took = _undoable;
    // Settled already (Done settles it too): the chip is drawn a moment after the reader's clock starts, so a tap is
    // never silent.
    if (took == null || took.id != id) return [const LiveStepChip(view: RouteViewSaid(text: 'Too late to put that back.'))];
    _undoable = null;
    // What it put in their place, out (a send's one-shot emptied with it, so Done skips it); what went, back where it
    // was (the recorder re-listens and re-sorts, and a card up takes it as said since); then the take-back itself, and
    // a send said after it, as the words they would have been: the opener and its rest, keyword off and the head's own
    // steps standing. A correction goes back beside the item it corrected, in its one-shot; anything else to the page.
    // A keyword's stretch is marked as `_read` marks one, so the better words leave "hey Ghost" out.
    final steps = _putBack(took);
    final beside = (took.outcome == _Outcome.replaced || took.outcome == _Outcome.changed) && took.removed.isNotEmpty ? took.removed[0].where : _take;
    steps.add(_place(beside, took.phrase));
    if (took.keyed) steps.add(LiveStepKeyword(span: _spanOf(took.phrase)));
    for (final send in took.sends ?? const <Segment>[]) {
      final heard = findKeyword(send.text);
      steps.add(_place(_take, _withText(send, _sentence(heard != null ? heard.after : send.text))));
      if (heard != null) steps.add(LiveStepKeyword(span: _spanOf(send)));
    }
    steps.addAll([const LiveStepChip(view: RouteViewDone(text: 'Put back')), const LiveStepHaptic(haptic: Haptic.light), LiveStepLog(line: 'Put back “${took.quote}”')]);
    return steps;
  }

  /// "New note", tapped: the words so far are sealed with the note they were said for, out of a take-back's reach, an
  /// open take-back settles, and the take is past its start, as after the spoken cue.
  List<LiveStep<N>> forked() {
    if (_closed) return [];
    final steps = _settleTakeBack();
    _said = [];
    _sealedYet = true;
    return steps;
  }

  /// A card's button: a note, a new note, or Keep here.
  List<LiveStep<N>> answer(int cardId, CardChoice choice, LiveContext<N> ctx) {
    if (_closed || _pending?.card.id != cardId) return [];
    return _settle(choice, ctx);
  }

  /// Not this note: the take goes home, and that name is not sent to that note again in this take. A card offers the
  /// find's other candidates and a new note, for 8 s or until the next phrase.
  List<LiveStep<N>> decline(LiveContext<N> ctx, int now) {
    final routed = _routed;
    if (routed == null || _closed) return [];
    _routed = null;
    _growing = null;
    _declined.add('${routed.id}|${routed.name.toLowerCase()}');
    final steps = <LiveStep<N>>[..._settleTakeBack(), const LiveStepHome(), LiveStepLog(line: 'Not added to ${routed.title}: the take went back to its own note')];
    if (ctx.locked) return [...steps, LiveStepChip(view: RouteViewSaid(text: 'Not added to ${routed.title}.'))];
    final found = findNote(routed.name, ctx.notes.where((c) => c.id != routed.id).toList());
    final others = switch (found) {
      FoundResolved<LiveCandidate<N>>(:final note) => [note],
      FoundUnsure<LiveCandidate<N>>(:final candidates) => candidates,
      FoundMissing<LiveCandidate<N>>(:final near) => near,
      FoundCurrent<LiveCandidate<N>>() => <LiveCandidate<N>>[],
    }.where((c) => _refusal(c, ctx) == null).toList();
    final card = LiveCard<N>(id: _nextId++, form: LiveCardForm.declined, heading: 'Not added to ${routed.title}', candidates: others.take(2).toList(), newTitle: _titleFor(routed.name), payload: '');
    // Nothing is held for this card to give back: what was said since the command is the take's already.
    const command = Segment(text: '', startMs: 0, endMs: 0);
    _pending = _Pending(card: card, since: now, command: command, payload: '', reading: namedAs(routed.name), atStart: false, after: [], declined: (id: routed.id, name: routed.name));
    return [...steps, LiveStepCard(card: card)];
  }

  /// A one-shot's own Not this note: its words back into the take. Nothing once the recording has ended: Done is
  /// writing it.
  List<LiveStep<N>> dropInsert(int id) {
    if (_closed) return [];
    if (_opened?.id == id) _opened = null;
    _rehome(id);
    return [LiveStepInsertDrop(id: id)];
  }

  /// A one-shot's words back in the take (`insert-drop`): the record says so too, their order as it was.
  void _rehome(int id) {
    _Placed home(_Placed placed) => placed.where.id == id ? _Placed(where: _take, segment: placed.segment, from: _fromOf(_take, placed.segment)) : placed;
    _said = _said.map(home).toList();
    final undoable = _undoable;
    if (undoable != null) {
      undoable.removed = undoable.removed.map(home).toList();
      undoable.placed = undoable.placed.map(home).toList();
    }
  }

  /// Done, Discard, the side key, the screen off, back: every hold, card and take-back settled, before anything is
  /// composed.
  List<LiveStep<N>> close(LiveContext<N> ctx, int now) {
    final steps = <LiveStep<N>>[];
    if (_held != null) steps.addAll(_letGoHeld(ctx, now));
    if (_pending != null) steps.addAll(_settle(const CardChoiceKeep(), ctx));
    if (_opened != null) steps.addAll(_closeInsert());
    steps.addAll(_settleTakeBack(true));
    _growing = null;
    _closed = true;
    return _late(steps, ctx);
  }

  /// The recording's last words, which only the stop's transcript had: read like any phrase, then closed again.
  List<LiveStep<N>> final_(Segment said, LiveContext<N> ctx, int now) {
    _closed = false;
    final steps = phrase(said, ctx, now);
    return [...steps, ...close(ctx, now)];
  }

  // ---- taking it back ---------------------------------------------------------------------------

  /// A held command's words as heard, joined, the keyword and the lead-ins gone, the stop off: '' for the keyword
  /// alone.
  String _heldWords(_Held held) {
    final joined = [for (var i = 0; i < held.segments.length; i += 1) i < held.segments.length - 1 ? withoutFinalStop(held.segments[i].text) : held.segments[i].text].join(' ');
    return withoutFinalStop(_commandWordsOf(joined));
  }

  /// A command with nothing said for it yet: what a safe take-back cancels, and what a risky one is the words of.
  bool _commandWaiting() {
    final held = _held;
    final holding = held != null && (held.why == _Why.unsure || (held.why == _Why.keyword && _heldWords(held) != ''));
    return holding || (_opened != null && _opened!.count == 0) || _routed?.awaiting == true || (_pending != null && _pending!.after.isEmpty);
  }

  /// A hold that is only filler, a lead or the keyword alone, dropped before a take-back goes ahead: filler either
  /// way, its stretch marked. `keyed` when it was the keyword, which made the take-back its command.
  ({List<LiveStep<N>> steps, bool keyed}) _dropHold() {
    final held = _held;
    final keyed = held != null && held.why == _Why.keyword && _heldWords(held) == '';
    if (held == null || (!keyed && held.why != _Why.lead && held.why != _Why.filler)) return (steps: <LiveStep<N>>[], keyed: false);
    _held = null;
    return (steps: [for (final s in held.segments) _spanStep(s)], keyed: keyed);
  }

  /// A phrase's stretch, marked as a command's for the better words.
  LiveStep<N> _spanStep(Segment segment) => LiveStepCommand(span: _spanOf(segment));

  LiveStep<N> _takeOut(_Where where, List<Segment> segments) => where.isTake ? _unword(segments) : _unwordInsert(where.id!, segments);

  /// The last thing said, taken back, when [segment] says so (take_back.dart): gone, replaced by the rest of the
  /// phrase, one word changed, or sent to a note named; a command with nothing said for it yet, cancelled. Null when
  /// the phrase is not one, or its opener is how people talk and no correction follows, so the phrase carries on as
  /// words. A phrase with words before the opener is read as two: the head first, a phrase of its own (it may itself
  /// be what is taken back), then the take-back, with [took] saying what the head took with it. Nothing here engages
  /// the reader.
  List<LiveStep<N>>? _takeBack(Segment segment, LiveContext<N> ctx, int now, [({bool keyed, bool headBeforeKeyword})? took]) {
    // A send said in a breath of its own, after a bare drop still open: "Scratch that." | "Add it to Groceries."; or
    // the name Whisper cut from its send: "Scratch that, add it to" | "Groceries instead."
    final open = _undoable;
    if (open != null && open.dropOnly && open.sent == null) {
      final name = readSend(segment.text) ?? (open.fragment != null ? readSend('${open.fragment} ${segment.text}') : null);
      final sent = name == null ? null : _sendAfter(open, name, segment, ctx, now);
      if (sent != null) return sent;
    }
    final read = readTakeBack(segment.text);
    if (read == null) return null;
    final held = _held;
    final keyedByHold = held != null && held.why == _Why.keyword && _heldWords(held) == '';
    // "Hey Ghost, actually, add a note to House TODOs": the command, said as people say it, and read as that command
    // by `_command`, the words before the keyword the take's own as ever.
    if (read.risky && (read.keyed || keyedByHold) && read.send == null && commandAfterOpener(read.said) != read.said) return null;
    // "Actually, add call the plumber to House TODOs" with no keyword: the command, when its words pass the bare gate.
    // A phrase with words before it ("Buy milk. Actually, add …") is read as two first, and its rest meets this alone.
    if (read.risky && read.head.isEmpty && !read.keyed && !keyedByHold && read.send == null && _bareReading(commandAfterOpener(commandWords(read.said)), ctx) != null) return null;
    if (read.head.isNotEmpty) {
      final head = _heard(_withText(segment, _sentence(read.head)), ctx, now);
      final rest = _heard(_withText(segment, read.said), ctx, now, (keyed: read.keyed, headBeforeKeyword: read.headBeforeKeyword));
      return [...head, ...rest];
    }
    final keyed = read.keyed || took?.keyed == true || keyedByHold;
    final headBeforeKeyword = took?.headBeforeKeyword ?? false;
    // A risky opener at a command with nothing said for it is the command's words: "add a note to House TODOs." |
    // "Actually, …"; and with a send's card up, words said since it.
    final waiting = _commandWaiting();
    if (read.risky && (waiting || _pending?.stays != null)) return null;

    // The last thing said, with the rest of its source phrase: an enumeration's items go as one. Several plain phrases
    // on one stretch (a phrase read as its head and its rest) are each their own, so the last is the unit. Of a phrase
    // that holds several sentences, the last, the others kept.
    final last = _said.isEmpty ? null : _said.last;
    var group = last != null ? _said.where((placed) => placed.from == last.from).toList() : <_Placed>[];
    if (group.length > 1 && group.every((placed) => placed.where.isTake && cuePrefixOf(placed.segment.text).isEmpty)) group = [last!];
    final sentences = group.length == 1 ? splitSentences(last!.segment.text) : const <String>[];
    final String? unitRaw = sentences.length >= 2 ? sentences.last : (group.length == 1 ? last!.segment.text : null);
    final Segment? kept = sentences.length >= 2 ? _withText(last!.segment, sentences.sublist(0, sentences.length - 1).join(' ')) : null;
    final unitText = unitRaw != null ? quoted(unitRaw) : group.map((placed) => quoted(placed.segment.text)).join(', ');
    final taken = kept != null ? [_withText(last!.segment, unitRaw!)] : group.map((placed) => placed.segment).toList();
    final swap = read.rest.isNotEmpty && unitRaw != null ? swapWord(unitRaw, read.rest) : null;
    // How people talk counts only before a correction of what went: the sentence again with a change, one word of a
    // kind, a send, or, after the keyword, a sentence of its own. With nothing said before, it is words, keyword and
    // all, read as any phrase is.
    if (last != null && !waiting && read.risky && read.send == null && swap == null && !corrects(unitText, read.rest) && !(keyed && contentWords(read.rest).length >= 2)) return null;
    if (last == null && read.risky) return null;

    final steps = _dropHold().steps;
    if (waiting || _pending?.stays != null) return [...steps, ..._cancel(read, segment, ctx, now)];
    if (last == null) {
      _tookBackYet = true;
      steps.addAll([_spanStep(segment), const LiveStepChip(view: RouteViewSaid(text: 'Nothing to take back.')), const LiveStepHaptic(haptic: Haptic.warning), const LiveStepLog(line: 'Nothing to take back')]);
      if (read.rest.isNotEmpty && read.send == null) steps.addAll(_heard(_withText(segment, _sentence(read.rest)), ctx, now));
      return steps;
    }

    // Decided before anything moves, so a send that finds no note moves nothing.
    final found = read.send != null ? _findNamed(read.send!, ctx) : null;
    final refused = found != null ? _sendRefused(found, read.send!, ctx) : null;
    if (refused != null) {
      _tookBackYet = true;
      return [...steps, _spanStep(segment), LiveStepChip(view: RouteViewSaid(text: refused)), const LiveStepHaptic(haptic: Haptic.warning), LiveStepLog(line: refused)];
    }
    final where = last.where;
    final segments = group.map((placed) => placed.segment).toList();

    // A send that is not sure of its note asks, the words on the page: a note chosen takes them, as a card mid-take
    // takes what was said since it (`_settle`); Keep here puts them back where they were. The phrase's own stretch is
    // marked now, since the card is the moment: there is no Undo.
    if (found is FoundUnsure<LiveCandidate<N>> || found is FoundMissing<LiveCandidate<N>>) {
      steps.addAll(_settleTakeBack());
      // The sentence alone on the page, split from the rest of its phrase, or brought home from its one-shot, so it
      // can go by itself.
      if (kept != null || !where.isTake) {
        steps.add(_takeOut(where, segments));
        if (kept != null) steps.add(_place(where, kept));
        for (final piece in taken) {
          steps.add(_place(_take, piece));
        }
      }
      return [...steps, ..._askSend(found!, read.send!, taken, unitText, where, segment, ctx, now)];
    }

    // Take it back: off the page or out of its one-shot, the rest of a phrase of several sentences kept.
    steps.addAll(_settleTakeBack());
    steps.add(_takeOut(where, segments));
    final doneAt = _doneReader.indexWhere((entry) => entry.segments.any((s) => group.any((placed) => _same(placed.segment, s))));
    final doneReader = doneAt >= 0 ? _doneReader.removeAt(doneAt) : null;
    // The corrected item said next still goes to the named note, and is read as the first said for it.
    final opened = _opened;
    if (opened != null && !where.isTake && where.id == opened.id) {
      opened.lastAt = now;
      opened.count = opened.count - 1 < 0 ? 0 : opened.count - 1;
    }
    final before = Set<_Placed>.identity()..addAll(_said);
    if (kept != null) steps.add(_place(where, kept));

    final undo = _nextId++;
    var outcome = _Outcome.gone;
    ({int id, String title})? sent;
    RouteView view = RouteViewTookBack(said: _cut(unitText), outcome: const TookBackGone(), undo: undo);
    var line = 'Took back “$unitText”';
    String? fragment;
    if (found is FoundCurrent<LiveCandidate<N>> || found is FoundResolved<LiveCandidate<N>>) {
      final went = _sendTaken(found!, taken, unitText, ctx, undo);
      steps.addAll(went.steps);
      outcome = went.outcome;
      sent = went.sent;
      view = went.view;
      line = went.line;
    } else if (swap != null) {
      steps.add(_place(where, _withText(taken[0], swap.text)));
      outcome = _Outcome.changed;
      view = RouteViewTookBack(said: _cut(swap.from), outcome: TookBackChanged(changed: swap.to), undo: undo);
      line = 'Changed “${swap.from}” to “${swap.to}” in “$unitText”';
    } else if (read.rest.isNotEmpty && read.risky) {
      // The sentence again, in the unit's place, the cue it was written with inherited so the list shape holds.
      final prefix = cuePrefixOf(unitRaw ?? group[0].segment.text);
      final pieces = prefix.isNotEmpty ? payloadWords(segment, read.rest, item: true, task: _check.hasMatch(prefix)) : [_withText(segment, _sentence(read.rest))];
      for (final piece in pieces) {
        steps.add(_place(where, piece));
      }
      final said = pieces.map((piece) => quoted(piece.text)).join(', ');
      outcome = _Outcome.replaced;
      view = RouteViewTookBack(said: _cut(unitText), outcome: TookBackReplaced(replaced: _cut(said)), undo: undo);
      line = 'Replaced “$unitText” with “$said”';
    } else if (read.rest.isNotEmpty && opensSend(read.rest) && isOpener(commandWords(read.rest))) {
      // "Scratch that, add it to" | "Groceries instead.": Whisper cut the name from its send. The opener waits for
      // it, never written.
      fragment = read.rest;
    }

    _tookBackYet = true;
    final placed = _said.where((entry) => !before.contains(entry)).toList();
    final mine = _TookBack(
      id: undo,
      phrase: _withText(segment, _sentence(read.said)),
      keyed: keyed,
      headBeforeKeyword: headBeforeKeyword,
      removed: group,
      taken: taken,
      placed: placed,
      outcome: outcome,
      sent: sent,
      dropOnly: outcome == _Outcome.gone && (read.rest.isEmpty || fragment != null),
      fragment: fragment,
      doneReader: doneReader,
      quote: unitText,
      since: now,
    );
    _undoable = mine;
    if (_pending != null) {
      for (final entry in placed) {
        if (entry.where.isTake) _pending!.after.add(entry.segment);
      }
    }
    steps.addAll([LiveStepChip(view: view), const LiveStepHaptic(haptic: Haptic.selection), LiveStepLog(line: line)]);
    // A safe opener's rest is a phrase of its own: words, a cue, a command, or another take-back.
    if (read.rest.isNotEmpty && !read.risky && read.send == null && swap == null && fragment == null) {
      steps.addAll(_heard(_withText(segment, _sentence(read.rest)), ctx, now));
      if (identical(_undoable, mine)) mine.placed = _said.where((entry) => !before.contains(entry)).toList();
    }
    return steps;
  }

  /// Why a send's note cannot take the words, or null: a book, a shared note over the lock screen, a name not sure of
  /// over the lock screen or between notes that are all refused, or a name that finds nothing and comes near nothing.
  String? _sendRefused(Found<LiveCandidate<N>> found, String name, LiveContext<N> ctx) {
    switch (found) {
      case FoundResolved<LiveCandidate<N>>():
        return _refusal(found.note, ctx);
      case FoundUnsure<LiveCandidate<N>>():
        final choices = found.candidates.where((candidate) => _refusal(candidate, ctx) == null);
        if (choices.isEmpty) return _refusal(found.candidates[0], ctx) ?? 'Not sure which note, so the words stay here.';
        return ctx.locked ? 'Not sure which note, so the words stay here.' : null;
      case FoundMissing<LiveCandidate<N>>():
        if (ctx.locked) return 'No note by that name, so the words stay here.';
        return found.near.any((candidate) => _refusal(candidate, ctx) == null) ? null : 'No note called “$name”, so the words stay here.';
      case FoundCurrent<LiveCandidate<N>>():
        return null;
    }
  }

  /// A send that is not sure of its note: the same card a command's name gets, holding the words as said since it,
  /// which are on the page ([taken]); a note chosen takes them, and Keep here puts them back where they were ([from]).
  List<LiveStep<N>> _askSend(Found<LiveCandidate<N>> found, String name, List<Segment> taken, String unitText, _Where from, Segment segment, LiveContext<N> ctx, int now) {
    _tookBackYet = true;
    final unsure = found is FoundUnsure<LiveCandidate<N>>;
    final heading = unsure ? 'Add to which note?' : 'No note called “$name”';
    final offered = switch (found) {
      FoundUnsure<LiveCandidate<N>>(:final candidates) => candidates,
      FoundMissing<LiveCandidate<N>>(:final near) => near,
      _ => <LiveCandidate<N>>[],
    };
    final candidates = offered.where((candidate) => _refusal(candidate, ctx) == null).take(unsure ? 3 : 2).toList();
    return [
      _spanStep(segment),
      ..._raise(
        form: unsure ? LiveCardForm.unsure : LiveCardForm.missing,
        heading: heading,
        candidates: candidates,
        reading: namedAs(name),
        payload: unitText,
        whole: segment,
        atStart: false,
        now: now,
        stays: _Stays(text: unitText, after: taken, from: from),
        ctx: ctx,
      ),
      LiveStepLog(line: 'Took back “$unitText”, asking which note'),
    ];
  }

  /// The words taken back, sent: into the note found, as a one-shot that shows its lines once the Undo goes; or, for
  /// the note being written to, as an item of its list, under a heading named for it. What the chip and the log say.
  ({List<LiveStep<N>> steps, _Outcome outcome, ({int id, String title})? sent, RouteView view, String line}) _sendTaken(Found<LiveCandidate<N>> found, List<Segment> taken, String unitText, LiveContext<N> ctx, int undo) {
    final steps = <LiveStep<N>>[];
    if (found is FoundCurrent<LiveCandidate<N>>) {
      final aim = ctx.aim;
      String? spot;
      final heading = found.heading;
      if (aim != null && heading != null && heading.isNotEmpty) {
        final placing = placingFor(liveNoteBody(aim), said: const Said(task: false), heading: heading, lane: heading);
        steps.add(LiveStepPlacing(placing: placing));
        spot = spotOf(liveNoteBody(aim), placing);
      }
      for (final piece in taken) {
        for (final item in payloadWords(piece, quoted(piece.text), item: true)) {
          steps.add(_place(_take, item, true));
        }
      }
      return (
        steps: steps,
        outcome: _Outcome.placed,
        sent: null,
        view: RouteViewTookBack(said: _cut(unitText), outcome: TookBackPlaced(placed: spot ?? 'in a list'), undo: undo),
        line: 'Put “$unitText” ${spot ?? 'in its list'}',
      );
    }
    final candidate = (found as FoundResolved<LiveCandidate<N>>).note;
    final note = candidate.note;
    final title = ctx.locked ? 'the note you named' : candidate.title;
    final id = _nextId++;
    for (final piece in taken) {
      _record(_Where.insert(id), piece);
    }
    steps.addAll([
      LiveStepInsert(id: id, note: note, title: title, placing: placingFor(liveNoteBody(note), said: const Said(task: false, paragraph: false)), segments: taken),
      const LiveStepHaptic(haptic: Haptic.success),
    ]);
    return (
      steps: steps,
      outcome: _Outcome.sent,
      sent: (id: id, title: title),
      view: RouteViewTookBack(said: _cut(unitText), outcome: TookBackSent(sent: title), undo: undo),
      line: 'Took back “$unitText” and sent it to $title',
    );
  }

  /// "Add it to Groceries" said in the breath after a bare "Scratch that": the drop's second half. The words go to
  /// the note found, or into this note's list; a name that is not sure asks on the card, the words on the page; a note
  /// the reader cannot write to, or a name said with the keyword that finds nothing, puts them back and says why. Null
  /// when a name said without the keyword finds nothing, so the phrase is words ("Put it in the oven").
  List<LiveStep<N>>? _sendAfter(_TookBack open, String name, Segment segment, LiveContext<N> ctx, int now) {
    final found = _findNamed(name, ctx);
    final refused = _sendRefused(found, name, ctx);
    if (refused != null && found is FoundMissing<LiveCandidate<N>> && findKeyword(segment.text) == null) return null;
    final steps = _dropHold().steps;
    if (refused != null) {
      // The words back where they were, the drop's own stretches marked and the words' not: with the live phrases
      // handed on, they survive the better words.
      _undoable = null;
      steps.addAll(_putBack(open));
      steps.add(open.headBeforeKeyword ? LiveStepKeyword(span: _spanOf(open.phrase)) : LiveStepCommand(span: _spanOf(open.phrase)));
      steps.add(_spanStep(segment));
      steps.addAll([LiveStepChip(view: RouteViewSaid(text: refused)), const LiveStepHaptic(haptic: Haptic.warning), LiveStepLog(line: refused)]);
      return steps;
    }
    if (found is FoundUnsure<LiveCandidate<N>> || found is FoundMissing<LiveCandidate<N>>) {
      // The card a send in one breath raises, the words on the page while it asks; the drop settles now, since the
      // card is the moment.
      steps.addAll(_settleTakeBack());
      for (final piece in open.taken) {
        steps.add(_place(_take, piece));
      }
      return [...steps, ..._askSend(found, name, open.taken, open.quote, open.removed.isNotEmpty ? open.removed[0].where : _take, segment, ctx, now)];
    }
    final before = Set<_Placed>.identity()..addAll(_said);
    final went = _sendTaken(found, open.taken, open.quote, ctx, open.id);
    steps.addAll([...went.steps, LiveStepChip(view: went.view), LiveStepLog(line: went.line)]);
    open.outcome = went.outcome;
    open.sent = went.sent;
    open.placed.addAll(_said.where((entry) => !before.contains(entry)));
    open.dropOnly = false;
    // The send's own phrase never lands: its stretch is the take-back's too, marked with it when it settles.
    open.sends = [...?open.sends, segment];
    open.since = now;
    return steps;
  }

  /// What a take-back put in their place, out, and what went, back where it was: Undo's and a refused send's.
  List<LiveStep<N>> _putBack(_TookBack took) {
    final steps = <LiveStep<N>>[];
    for (final placed in took.placed.reversed.toList()) {
      steps.add(_takeOut(placed.where, [placed.segment]));
    }
    for (final placed in took.removed) {
      steps.add(_place(placed.where, placed.segment));
      if (_pending != null && placed.where.isTake) _pending!.after.add(placed.segment);
    }
    if (took.doneReader != null) _doneReader.add(took.doneReader!);
    return steps;
  }

  /// A safe take-back at a command with nothing said for it yet cancels the command, and nothing else is taken back:
  /// a held opener, an empty one-shot, a note routed to and waiting, or a card with nothing said since. No Undo (say
  /// the command again). With nothing on the page afterwards the take is at its start again, so the corrected command
  /// is sticky.
  List<LiveStep<N>> _cancel(TakeBack read, Segment segment, LiveContext<N> ctx, int now) {
    final steps = <LiveStep<N>>[];
    var what = '';
    final held = _held;
    if (held != null) {
      _held = null;
      what = _heldWords(held);
      steps.addAll(held.segments.map(_spanStep));
    } else if (_opened != null && _opened!.count == 0) {
      what = _opened!.words;
      steps.addAll(_closeInsert());
    } else if (_routed?.awaiting == true) {
      what = _routed!.words;
      _routed = null;
      steps.addAll([..._settleTakeBack(), const LiveStepHome()]);
    } else if (_pending != null) {
      final pending = _pending!;
      _tookBackYet = true;
      // A take-back's own send, still asking: the words go back, and the card goes.
      if (pending.stays != null) return [...steps, _spanStep(segment), ..._settle(const CardChoiceKeep(), ctx)];
      what = withoutFinalStop(_commandWordsOf(pending.command.text));
      _pending = null;
      steps.add(const LiveStepCard(card: null));
    }
    _tookBackYet = true;
    if (_said.isEmpty) _engagedYet = false;
    steps.addAll([
      _spanStep(segment),
      LiveStepChip(view: RouteViewTookBack(said: _cut(what), outcome: const TookBackGone())),
      const LiveStepHaptic(haptic: Haptic.selection),
      LiveStepLog(line: 'Took back the command “$what”'),
    ]);
    if (read.rest.isNotEmpty && read.send == null) steps.addAll(_heard(_withText(segment, _sentence(read.rest)), ctx, now));
    return steps;
  }

  /// A take-back settled: its stretches marked for the better words, which are pushed only now because the
  /// recorder's command spans cannot be undone; a send's one-shot shown with its Not this note, which is the way back
  /// after the window. At [closing] (Done) the quote is kept for the note's toast, since its Undo could not be tapped.
  List<LiveStep<N>> _settleTakeBack([bool closing = false]) {
    final took = _undoable;
    if (took == null) return [];
    _undoable = null;
    final marks = <String, (int, LiveStep<N>)>{};
    void mark(Segment segment, [bool keyword = false]) {
      final key = '${segment.startMs}-${segment.endMs}';
      marks.putIfAbsent(key, () => (segment.startMs, keyword ? LiveStepKeyword<N>(span: _spanOf(segment)) : LiveStepCommand<N>(span: _spanOf(segment))));
    }

    // The phrase first: on the stretch it shares with its head, its own mark is the one that stands.
    mark(took.phrase, took.headBeforeKeyword);
    for (final placed in took.removed) {
      mark(placed.segment);
    }
    for (final send in took.sends ?? const <Segment>[]) {
      mark(send);
    }
    final ordered = marks.values.toList();
    _sort<(int, LiveStep<N>)>(ordered, (a, b) => a.$1 - b.$1);
    final steps = <LiveStep<N>>[for (final (_, step) in ordered) step];
    if (took.sent != null && !closing) steps.add(LiveStepInsertEnd(id: took.sent!.id));
    if (closing) _closedWith.add(took.quote);
    return steps;
  }

  // ---- reading ----------------------------------------------------------------------------------

  LiveStep<N> _words(Segment segment, [bool payload = false]) => _place(_take, segment, payload);

  /// A phrase put somewhere, on the record: at its place by time, after those said at the same time, so a phrase's
  /// pieces keep their order. Anything placed after a bare drop is what "it" now means, so a send in the next breath
  /// follows the drop only.
  void _record(_Where where, Segment segment) {
    if (_undoable?.dropOnly == true) _undoable!.dropOnly = false;
    var at = _said.length;
    while (at > 0 && _said[at - 1].segment.startMs > segment.startMs) {
      at -= 1;
    }
    _said.insert(at, _Placed(where: where, segment: segment, from: _fromOf(where, segment)));
  }

  /// The one way words go on the page or into a one-shot: recorded, and the step that puts them there.
  LiveStep<N> _place(_Where where, Segment segment, [bool payload = false]) {
    _record(where, segment);
    if (!where.isTake) return LiveStepInsertWords(id: where.id!, segments: [segment]);
    return payload ? LiveStepWords(segment: segment, payload: payload) : LiveStepWords(segment: segment);
  }

  /// Phrases off the record: taken out of the take, or of a one-shot, or a card's said-since.
  void _forget(List<Segment> segments) {
    _said = _said.where((placed) => !segments.any((gone) => _same(gone, placed.segment))).toList();
    if (_pending != null) _pending!.after = _pending!.after.where((after) => !segments.any((gone) => _same(gone, after))).toList();
  }

  /// The one way words leave the take (`unword`), or a one-shot (`insert-unword`): off the record, and the step.
  LiveStep<N> _unword(List<Segment> segments) {
    _forget(segments);
    return LiveStepUnword(segments: [...segments]);
  }

  LiveStep<N> _unwordInsert(int id, List<Segment> segments) {
    _forget(segments);
    return LiveStepInsertUnword(id: id, segments: [...segments]);
  }

  /// A command's payload as the take's words ([payloadWords]). The phrase it was read from is marked, so the better
  /// words put these in its place rather than the phrase as heard, "The note is" and all (refine_text.dart).
  List<LiveStep<N>> _payload(Segment whole, String payload, {bool item = false, bool task = false}) {
    final words = payloadWords(whole, payload, item: item, task: task);
    return words.isNotEmpty ? [LiveStepCommand(span: _spanOf(whole)), for (final segment in words) _words(segment, true)] : [];
  }

  void _engage() {
    _engagedYet = true;
  }

  /// Whether [words] after a mishearing of the keyword are a command for a note named clearly: the gate every bare
  /// phrase passes (live_command.dart `misheardShape`, `_clear`), since a mishearing is exactly as trustworthy as no
  /// keyword.
  bool _readsAsRoute(String words, LiveContext<N> ctx) => misheardShape(commandWords(words), (reading) => _clear(reading, _find(reading, ctx), ctx));

  /// The gate a phrase passes with no trustworthy keyword, with what only the live reader knows: the note found is one
  /// it may write to (`_refusal`), and whether the take is at the start of a fresh recording, where a route may wait
  /// for its words (live_command.dart `bareCommand`).
  bool _clear(Reading reading, Found<LiveCandidate<N>> found, LiveContext<N> ctx) =>
      found is FoundResolved<LiveCandidate<N>> &&
      _refusal(found.note, ctx) == null &&
      bareCommand(reading, (title: found.note.title, body: liveNoteBody(found.note.note)), found.score, atStart: _atStart && !ctx.own);

  /// What `_bare` carries out, and what a risky opener before it is not a correction of: the readings of [words] that
  /// pass the bare gate, the best of them chosen as a keyed command's is (`_choose`). Null when none does.
  ({Reading reading, LiveCandidate<N> note, double score})? _bareReading(String words, LiveContext<N> ctx) {
    final passing = readRoute(words).where((reading) => bareShape(reading) && _clear(reading, _find(reading, ctx), ctx)).toList();
    final chosen = _choose(passing, ctx);
    final found = chosen?.found;
    if (chosen == null || found is! FoundResolved<LiveCandidate<N>>) return null;
    return (reading: chosen.reading, note: found.note, score: found.score);
  }

  /// Why a note is never written to from here, or null: it is a notebook or a journal, whose words are its index (an
  /// entry is made by a tap, docs/DESIGN.md §127 and §142), or it is shared and the phone is locked.
  String? _refusal(LiveCandidate<N> candidate, LiveContext<N> ctx) {
    final body = liveNoteBody(candidate.note);
    if (isJournalBody(body)) return '“${candidate.title}” is a journal, so the words stay here.';
    if (isBookBody(body)) return '“${candidate.title}” is a notebook, so the words stay here.';
    if (ctx.locked && ctx.published?.call(liveNoteId(candidate.note)) == true) return 'That note is shared, so the words stay here.';
    return null;
  }

  /// Keyworded phrases at the take's start that were left as words for the reader at Done, once the live reader has
  /// done something: the reader at Done no longer runs, so each is taken out of the words and queued or left out, as
  /// one said mid-take is ("Hey Ghost, fix the spelling." | … | "Hey Ghost, add call Sam to House TODOs."). Before the
  /// phrase's own steps, so an ask said later is the one kept.
  List<LiveStep<N>> _late(List<LiveStep<N>> steps, LiveContext<N> ctx) {
    if (!_engagedYet || _doneReader.isEmpty) return steps;
    final out = <LiveStep<N>>[];
    final entries = [..._doneReader];
    _doneReader.clear();
    for (final entry in entries) {
      out.add(_unword(entry.segments));
      out.addAll(entry.segments.map(_spanStep));
      final done = _notRoute(entry.words, ctx, atStart: false);
      if (!identical(done, _doneReaderMark)) out.addAll(done);
    }
    return [...out, ...steps];
  }

  /// Phrases the reader at Done is to read: words for now, remembered in case the live reader engages later (`_late`).
  List<LiveStep<N>> _leftForDone(List<Segment> segments, String words) {
    _doneReader.add(_DoneEntry(segments: segments, words: words));
    return [for (final segment in segments) _words(segment)];
  }

  Found<LiveCandidate<N>> _findNamed(String name, LiveContext<N> ctx) {
    final aim = ctx.aim;
    return findNote(name, ctx.notes, aim: aim == null ? null : Aim(id: liveNoteId(aim), body: liveNoteBody(aim)));
  }

  Found<LiveCandidate<N>> _find(Reading reading, LiveContext<N> ctx) => _findNamed(reading.name, ctx);

  List<LiveStep<N>> _read(Segment segment, LiveContext<N> ctx, int now) {
    final text = segment.text;
    final atStart = _atStart;
    final heard = hearKeyword(text, (words) => _readsAsRoute(words, ctx));
    if (heard == null) {
      // "Okay." or "Hey." before the command, or Whisper's "Thank you." on a silence: held for the next phrase.
      if (atStart && (onlyLead(text) || onlyFillerPhrase(text) || silenceLine(text))) {
        _held = _Held(segments: [segment], why: onlyLead(text) ? _Why.lead : _Why.filler, lastAt: now);
        return [];
      }
      return _bare(segment, ctx, now);
    }
    final before = heard.before.trim();
    final words = before.isNotEmpty && !onlyFiller(before);
    // "The heating is fixed now, hey Ghost, add…": the words before it are the take's, a phrase of their own.
    final kept = <LiveStep<N>>[if (words) _words(_withText(segment, _endsWithStop.hasMatch(before) ? before : '$before.'))];
    final LiveStep<N> mark = words ? LiveStepKeyword(span: _spanOf(segment)) : LiveStepCommand(span: _spanOf(segment));
    final said = commandWords(heard.after);
    final outcome = _command(said, segment, ctx, now, atStart: atStart && !words);
    if (identical(outcome, _doneReaderMark)) return _leftForDone([segment], said);
    if (identical(outcome, _heldMark)) return [...kept, ..._heldChip()];
    return [...kept, mark, ...outcome];
  }

  /// The chip while a command is held: "Looking for “house”" once a name is heard, and until then the keyword's.
  List<LiveStep<N>> _heldChip() {
    final name = _held?.name;
    final RouteView view = name != null && name.isNotEmpty ? RouteViewHearing(name: name) : const RouteViewCommand(words: '');
    return [LiveStepChip(view: view), const LiveStepHaptic(haptic: Haptic.light)];
  }

  /// A held command read again with the phrase just committed.
  List<LiveStep<N>> _readHeld(Segment segment, LiveContext<N> ctx, int now) {
    final held = _held!;
    _held = null;
    final segments = [...held.segments, segment];
    // Joined, each phrase's own stop gone but the last one's, which ends the command as it ends the phrase.
    final joined = [for (var i = 0; i < segments.length; i += 1) i < segments.length - 1 ? withoutFinalStop(segments[i].text) : segments[i].text].join(' ');
    final whole = Segment(text: joined, startMs: segments[0].startMs, endMs: segment.endMs);
    final spans = <LiveStep<N>>[for (final s in segments) LiveStepCommand(span: _spanOf(s))];
    final heard = hearKeyword(joined, (words) => _readsAsRoute(words, ctx));
    if (held.why == _Why.lead || held.why == _Why.filler) {
      // "Hey." | "Ghost, add…", "Okay." | "Hey Ghost, add…": one command, or the held phrase given back.
      if (heard != null && onlyFiller(heard.before)) {
        final said = commandWords(heard.after);
        final outcome = _command(said, whole, ctx, now, atStart: true);
        if (identical(outcome, _doneReaderMark)) return _leftForDone(segments, said);
        if (identical(outcome, _heldMark)) return _heldChip();
        return [...spans, ...outcome];
      }
      // No keyed command came of it: this phrase is read on its own, and the held one is words after all, unless the
      // phrase was a bare command ("Okay." | "Add a note to House TODOs, call Sam.", "Um." | "New note."), which the
      // filler was said before: then it is marked with the command, as after the keyword, and makes no note of "Okay.".
      // Decided after the read, since `_record` places by time; a phrase read as a command starts with its mark.
      final rest = _read(segment, ctx, now);
      final commanded = rest.isNotEmpty && rest[0] is LiveStepCommand<N>;
      return commanded ? [...held.segments.map(_spanStep), ...rest] : [_words(held.segments[0]), ...rest];
    }
    final words = commandWords(heard != null ? heard.after : joined);
    if (isOpener(words) && held.why == _Why.keyword) {
      _held = _Held(segments: segments, why: held.why, lastAt: now);
      if (segments.length < liveTiming.holdPhrases) return [LiveStepChip(view: RouteViewCommand(words: words))];
      // This many phrases and still no name: it gives up, as it does after a quiet.
      return _letGoHeld(ctx, now);
    }
    final outcome = _command(words, whole, ctx, now, atStart: _atStart, fromHold: true);
    if (identical(outcome, _doneReaderMark)) return _leftForDone(segments, words);
    if (identical(outcome, _heldMark)) return _heldChip();
    return [...spans, ...outcome];
  }

  /// A held command that got no name: its words back, or, once the reader has engaged, left out.
  List<LiveStep<N>> _letGoHeld(LiveContext<N> ctx, int now) {
    final held = _held;
    _held = null;
    if (held == null) return [];
    if (held.why == _Why.lead || held.why == _Why.filler) return [_words(held.segments[0])];
    if (held.why == _Why.unsure) {
      // An unsure name that did not grow: its card now.
      final first = held.segments[0];
      final heard = hearKeyword(first.text, (_) => true);
      final outcome = _command(commandWords(heard?.after ?? first.text), first, ctx, now, atStart: _atStart, fromHold: true);
      if (identical(outcome, _doneReaderMark) || identical(outcome, _heldMark)) return [_words(first)];
      return [LiveStepCommand(span: _spanOf(first)), ...outcome];
    }
    if (_engagedYet) return [const LiveStepChip(view: RouteViewSaid(text: 'No note was named, so that was left out.'))];
    final back = <LiveStep<N>>[];
    for (var i = 0; i < held.segments.length; i += 1) {
      final segment = held.segments[i];
      final heard = i == 0 ? hearKeyword(segment.text, (_) => true) : null;
      final text = heard != null ? heard.after : segment.text;
      if (text.trim().isNotEmpty) back.add(_words(_withText(segment, _sentence(withoutFinalStop(text)))));
    }
    return [
      ...back,
      const LiveStepLog(line: 'Heard “hey Ghost” but no note named, so those words stayed in the note'),
      const LiveStepChip(view: RouteViewSaid(text: 'No note was named, so the words stay here.')),
    ];
  }

  /// A command's words after the keyword: a route, a to-do for here, a new note; held for its name (`_heldMark`); or
  /// no route at all (`_doneReaderMark` at the take's start). [whole] is the stretch of the recording it was said over.
  List<LiveStep<N>> _command(String said, Segment whole, LiveContext<N> ctx, int now, {required bool atStart, bool fromHold = false}) {
    // "Actually, add a note to House TODOs": the command, said as people say it (take_back.dart).
    final words = commandAfterOpener(said);
    if (words.isEmpty || isOpener(words)) {
      _held = _Held(segments: [whole], why: _Why.keyword, lastAt: now);
      return _heldMark;
    }
    // A command said while a note switched to waits for its words: they are not what comes next.
    if (_routed != null) _routed!.awaiting = false;
    final readings = [...readRoute(words), ...readNameFirst(words)];
    final chosen = _choose(readings, ctx);
    if (chosen == null) return _notRoute(words, ctx, atStart: atStart);
    final found = chosen.found;
    final reading = _endedAs(chosen.reading, whole.text);
    if (reading.newNote) return _newNoteSaid(ctx, atStart: atStart);
    if (reading.self) return _self(reading, whole, ctx);
    // An unsure name at the phrase's end, with nothing after it, may still be growing: one more phrase first.
    if (found is FoundUnsure<LiveCandidate<N>> && !reading.stopped && reading.payload.isEmpty && !fromHold) {
      _held = _Held(segments: [whole], why: _Why.unsure, lastAt: now, name: reading.name);
      return _heldMark;
    }
    return _act(reading, found, whole, ctx, now, atStart: atStart);
  }

  /// The best reading of a command: a clear note beats the note being written to, which beats an unsure name, which
  /// beats one that matched nothing; then the better score; then the reading that leaves the payload as it was said.
  _Scored<N>? _choose(List<Reading> readings, LiveContext<N> ctx) {
    for (final r in readings) {
      if (r.newNote) return _Scored(r, FoundMissing<LiveCandidate<N>>(near: const []));
    }
    final scored = <_Scored<N>>[];
    for (final reading in readings) {
      if (reading.self) continue;
      final found = _find(reading, ctx);
      if (found is FoundResolved<LiveCandidate<N>> && _declined.contains('${found.note.id}|${reading.name.toLowerCase()}')) continue;
      // "call the electrician" is a name only when a note is plainly called that: "Call log".
      if (reading.verb) {
        if (found is! FoundResolved<LiveCandidate<N>> || found.score < 0.9) continue;
        final titleWords = nameWords(found.note.title).words;
        final saidWords = nameWords(reading.name).words;
        if ((titleWords.isEmpty ? null : titleWords[0]) != (saidWords.isEmpty ? null : saidWords[0])) continue;
      } else if (reading.nameFirst) {
        if (found is! FoundResolved<LiveCandidate<N>>) continue;
      }
      scored.add(_Scored(reading, found));
    }
    Reading? self;
    for (final r in readings) {
      if (r.self) {
        self = r;
        break;
      }
    }
    int rank(Found<LiveCandidate<N>> found) => switch (found) {
      FoundResolved<LiveCandidate<N>>() => 4,
      FoundCurrent<LiveCandidate<N>>() => 3,
      FoundUnsure<LiveCandidate<N>>() => 2,
      FoundMissing<LiveCandidate<N>>() => 1,
    };
    double score(Found<LiveCandidate<N>> found) => switch (found) {
      FoundResolved<LiveCandidate<N>>(:final score) => score,
      FoundUnsure<LiveCandidate<N>>(:final score) => score,
      FoundCurrent<LiveCandidate<N>>() => 1,
      FoundMissing<LiveCandidate<N>>() => 0,
    };
    int lead(Reading r) => payloadLead.hasMatch(r.payload) ? 1 : 0;
    bool placed(_Scored<N> x) {
      final heading = x.reading.heading;
      final found = x.found;
      return heading != null && found is FoundResolved<LiveCandidate<N>> && headingIn(liveNoteBody(found.note.note), heading);
    }

    num better(_Scored<N> a, _Scored<N> b) {
      if (rank(a.found) != rank(b.found)) return rank(b.found) - rank(a.found);
      if (score(a.found) != score(b.found)) return score(b.found) - score(a.found);
      if (lead(a.reading) != lead(b.reading)) return lead(b.reading) - lead(a.reading);
      if (a.reading.stopped != b.reading.stopped) return a.reading.stopped ? -1 : 1;
      // The same name read two ways: "add fix the tap under Kitchen in home jobs" is under a heading the note has, and
      // "add clean under the sofa in house to-dos" is one to-do, since House TODOs has no heading "the sofa".
      if (a.reading.name.toLowerCase() == b.reading.name.toLowerCase()) {
        if (placed(a) != placed(b)) return placed(a) ? -1 : 1;
        if ((a.reading.heading != null) != (b.reading.heading != null)) return a.reading.heading != null ? 1 : -1;
        return 0;
      }
      // One name the start of the other: the longer when what it adds is kind words ("house chores"), else the shorter.
      final aShort = a.reading.name.length <= b.reading.name.length;
      final short = aShort ? a : b;
      final long = aShort ? b : a;
      if (long.reading.name.toLowerCase().startsWith(short.reading.name.toLowerCase())) {
        final extra = nameWords(long.reading.name.substring(short.reading.name.length));
        final kindOnly = extra.words.isNotEmpty && extra.distinctive.isEmpty;
        return identical(kindOnly ? long : short, a) ? -1 : 1;
      }
      return a.reading.split == b.reading.split ? 0 : (a.reading.split ? 1 : -1);
    }

    final ranked = [...scored];
    _sort(ranked, better);
    final bestFound = ranked.isEmpty ? null : ranked[0];
    if (self != null && (bestFound == null || bestFound.found is! FoundResolved<LiveCandidate<N>> || !bestFound.reading.verb)) {
      return _Scored(self, FoundCurrent<LiveCandidate<N>>(heading: null));
    }
    if (bestFound == null) return null;
    // A name from a split point that matched nothing says nothing, unless every reading matched nothing.
    for (final c in ranked) {
      if (!(c.found is FoundMissing<LiveCandidate<N>> && c.reading.split)) return c;
    }
    return bestFound;
  }

  /// What a chosen reading of a keyed command does, by how sure the name is.
  List<LiveStep<N>> _act(Reading reading, Found<LiveCandidate<N>> found, Segment whole, LiveContext<N> ctx, int now, {required bool atStart}) {
    final payload = payloadOf(reading.payload);
    switch (found) {
      case FoundCurrent<LiveCandidate<N>>():
        return _here(reading, payload, whole, ctx, found.heading);
      case FoundResolved<LiveCandidate<N>>():
        return _resolved(reading, found.note, found.score, payload, whole, ctx, now, atStart: atStart);
      case FoundUnsure<LiveCandidate<N>>():
        if (ctx.locked) return _keep(_keptWords(reading, payload), whole, 'Not sure which note, so the words stay here.');
        // A card never offers a note the words can't go into: "hello trade the book" between two books is no choice.
        final choices = found.candidates.where((candidate) => _refusal(candidate, ctx) == null).toList();
        if (choices.isEmpty) return _keep(payload, whole, _refusal(found.candidates[0], ctx), reading.trailing);
        return _raise(form: LiveCardForm.unsure, heading: 'Add to which note?', candidates: choices.take(3).toList(), reading: reading, payload: payload, whole: whole, atStart: atStart, now: now, ctx: ctx);
      case FoundMissing<LiveCandidate<N>>():
        final near = found.near.where((candidate) => _refusal(candidate, ctx) == null).toList();
        if (!ctx.locked && (near.isNotEmpty || reading.noun)) {
          return _raise(form: LiveCardForm.missing, heading: 'No note called “${reading.name}”', candidates: near.take(2).toList(), reading: reading, payload: payload, whole: whole, atStart: atStart, now: now, ctx: ctx);
        }
        return _keep(_keptWords(reading, payload), whole, ctx.locked ? 'No note by that name, so the words stay here.' : 'No note called “${reading.name}”, so the words stay here.', reading.trailing);
    }
  }

  /// A clear note: the take goes there, or its words do, or, for the note already being written to, only how they go.
  List<LiveStep<N>> _resolved(Reading reading, LiveCandidate<N> candidate, double score, String payload, Segment whole, LiveContext<N> ctx, int now, {required bool atStart}) {
    final note = candidate.note;
    final body = liveNoteBody(note);
    final refused = _refusal(candidate, ctx);
    if (refused != null) return _keep(payload, whole, refused, reading.trailing);
    final aim = ctx.aim;
    if (aim != null && liveNoteId(aim) == liveNoteId(note)) return _here(reading, payload, whole, ctx, reading.heading);
    final placing = placingFor(body, said: _saidOf(reading), heading: reading.heading, move: reading.move);
    // Where the words go, by what they say when they were said: "under Electrical".
    final spot = payload.isNotEmpty
        ? (placeTake(body, renderNote(payloadWords(whole, payload), '', const RenderOptions(titled: false)).markdown, placing).spot ?? spotOf(body, placing))
        : spotOf(body, placing);
    final title = ctx.locked ? 'the note you named' : candidate.title;
    _engage();
    final steps = <LiveStep<N>>[];
    final words = withoutFinalStop(_commandWordsOf(whole.text));
    final sticky = reading.move || (atStart && !ctx.own && _routed == null);
    if (sticky) {
      _routed = _Routed(id: liveNoteId(note), title: title, awaiting: payload.isEmpty && !reading.move, name: reading.name, words: words);
      steps.addAll([..._settleTakeBack(), LiveStepRoute(note: note, title: title, placing: placing, move: reading.move, spot: spot), const LiveStepHaptic(haptic: Haptic.success)]);
      steps.add(LiveStepLog(line: '${reading.move ? 'Moved this recording to' : 'Writing to'} ${candidate.title}'));
      steps.addAll(_payload(whole, payload, task: reading.placing == ReadingPlacing.task));
      steps.add(LiveStepChip(view: payload.isNotEmpty || reading.move ? RouteViewMoved(title: title, spot: spot) : RouteViewWaiting(title: title)));
      if (!reading.stopped && score < 1 && !reading.move) _growing = _Growing(reading: reading, score: score, command: whole, words: words, into: null, note: note);
    } else {
      final id = _nextId++;
      final theirs = payloadWords(whole, payload, task: reading.placing == ReadingPlacing.task);
      for (final piece in theirs) {
        _record(_Where.insert(id), piece);
      }
      steps.addAll([LiveStepInsert(id: id, note: note, title: title, placing: placing, segments: theirs), const LiveStepHaptic(haptic: Haptic.success)]);
      steps.add(LiveStepLog(line: 'Added to ${candidate.title}${spot != null && spot.isNotEmpty ? ', $spot' : ''}'));
      if (payload.isNotEmpty) {
        steps.add(LiveStepInsertEnd(id: id));
        if (!reading.stopped && score < 1) _growing = _Growing(reading: reading, score: score, command: whole, words: words, into: id, note: note);
      } else {
        _opened = _Opened(id: id, note: note, title: title, count: 0, lastAt: now, words: words);
        steps.add(LiveStepChip(view: RouteViewWaiting(title: title)));
      }
    }
    if (reading.trailing.isNotEmpty) steps.add(_words(_withText(whole, _sentence(reading.trailing))));
    return steps;
  }

  /// The note being written to, named: its words go on as they were, only placed as the command said.
  List<LiveStep<N>> _here(Reading reading, String payload, Segment whole, LiveContext<N> ctx, String? heading) {
    _engage();
    final steps = <LiveStep<N>>[];
    final task = reading.placing == ReadingPlacing.task;
    final aim = ctx.aim;
    final headed = heading != null && heading.isNotEmpty;
    if (aim != null && (headed || task)) steps.add(LiveStepPlacing(placing: placingFor(liveNoteBody(aim), said: Said(task: task), heading: heading, lane: heading)));
    // Said for a list ("add milk to the list", "…to Kitchen"), the words are an item of it.
    steps.addAll(_payload(whole, payload, item: true, task: task));
    if (reading.trailing.isNotEmpty) steps.add(_words(_withText(whole, _sentence(reading.trailing))));
    return steps;
  }

  /// "Remind me to call Sam": a to-do in the note being written to.
  List<LiveStep<N>> _self(Reading reading, Segment whole, LiveContext<N> ctx) {
    _engage();
    final aim = ctx.aim;
    final aimed = aim != null ? runsOf(liveNoteBody(aim).split('\n')) : const <Run>[];
    final task = reading.placing == ReadingPlacing.task || aimed.any((run) => run.style.task) || (aim != null && semanticListKind(liveNoteBody(aim)) == TitleKind.task);
    final words = _payload(whole, reading.payload, item: true, task: task);
    return words.isNotEmpty ? [...words, const LiveStepHaptic(haptic: Haptic.selection)] : [];
  }

  /// "New note": at the start of a fresh take it is one already.
  List<LiveStep<N>> _newNoteSaid(LiveContext<N> ctx, {required bool atStart}) {
    if (atStart && !ctx.own && _routed == null) return [const LiveStepChip(view: RouteViewSaid(text: 'This is a new note already.'))];
    _engage();
    _routed = null;
    // The words so far are sealed with the note they were said for: out of a take-back's reach.
    final steps = _settleTakeBack();
    _said = [];
    _sealedYet = true;
    return [...steps, const LiveStepNewNote(), const LiveStepChip(view: RouteViewMoved(title: 'New note')), const LiveStepHaptic(haptic: Haptic.selection), const LiveStepLog(line: 'Started a new note')];
  }

  /// The words stay where the take is going: the payload kept, the command left out, and why.
  List<LiveStep<N>> _keep(String payload, Segment whole, String? why, [String trailing = '']) {
    _engage();
    final steps = <LiveStep<N>>[];
    steps.addAll(_payload(whole, payload));
    if (trailing.isNotEmpty) steps.add(_words(_withText(whole, _sentence(trailing))));
    if (why != null && why.isNotEmpty) steps.addAll([LiveStepChip(view: RouteViewSaid(text: why)), const LiveStepHaptic(haptic: Haptic.warning), LiveStepLog(line: why)]);
    return steps;
  }

  /// A card, holding the command phrase; later phrases go to the page as words. One up already, for an earlier
  /// command, takes its default first, Keep here: a card is never dropped with its words.
  List<LiveStep<N>> _raise({
    required LiveCardForm form,
    required String heading,
    required List<LiveCandidate<N>> candidates,
    required Reading reading,
    required String payload,
    required Segment whole,
    required bool atStart,
    required int now,
    _Stays? stays,
    required LiveContext<N> ctx,
  }) {
    final before = _pending != null ? _settle(const CardChoiceKeep(), ctx) : <LiveStep<N>>[];
    _engage();
    final card = LiveCard<N>(id: _nextId++, form: form, heading: heading, candidates: candidates, newTitle: _titleFor(reading.name), payload: _shown(payload));
    // A take-back's send holds what it would send as the words said since, on the page: a note chosen takes them,
    // and Keep here puts them back where they were and says so (`stays`).
    _pending = stays != null
        ? _Pending(card: card, since: now, command: whole, payload: '', reading: reading, atStart: atStart, after: [...stays.after], stays: stays)
        : _Pending(card: card, since: now, command: whole, payload: payload, reading: reading, atStart: atStart, after: []);
    return [...before, LiveStepCard(card: card), const LiveStepHaptic(haptic: Haptic.selection)];
  }

  /// A take-back's send that got no note from its card: the words back where they were, a one-shot's into it (on the
  /// page they never left), and a chip says so, or says [why] the note chosen would not take them.
  List<LiveStep<N>> _restore(_Pending<N> pending, [String? why]) {
    final stays = pending.stays;
    if (stays == null) return [];
    final steps = <LiveStep<N>>[];
    if (!stays.from.isTake) {
      steps.add(_unword(stays.after));
      for (final piece in stays.after) {
        steps.add(_place(stays.from, piece));
      }
    }
    final text = why ?? '“${_cut(stays.text)}” stays ${stays.from.isTake ? 'here' : 'where it was'}.';
    return [...steps, LiveStepChip(view: RouteViewSaid(text: text))];
  }

  /// A spoken answer to the card up now: one of its titles, "the first one", "keep it here", "new note".
  CardChoice? _spokenAnswer(String text) {
    final card = _pending?.card;
    if (card == null) return null;
    final said = withoutFinalStop(text).toLowerCase().replaceFirst(_answerLead, '');
    if (_keepHere.hasMatch(said)) return const CardChoiceKeep();
    if (_aNewNote.hasMatch(said)) return const CardChoiceNew();
    final nth = _nth.firstMatch(said);
    if (nth != null) {
      final at = const ['first', 'second', 'third'].indexOf(nth.group(1)!);
      return at < card.candidates.length ? CardChoiceNote(id: card.candidates[at].id) : null;
    }
    final found = findNote(said, card.candidates);
    return found is FoundResolved<LiveCandidate<N>> && found.score >= 0.85 ? CardChoiceNote(id: found.note.id) : null;
  }

  /// A card settled, by a tap, a spoken answer, its clock or the end of the recording.
  List<LiveStep<N>> _settle(CardChoice choice, LiveContext<N> ctx) {
    final pending = _pending;
    _pending = null;
    if (pending == null) return [];
    final steps = <LiveStep<N>>[const LiveStepCard(card: null)];
    final task = pending.reading.placing == ReadingPlacing.task;
    if (choice is CardChoiceKeep) {
      if (pending.declined != null) return steps;
      if (pending.stays != null) return [...steps, ..._restore(pending)];
      return [...steps, ..._keep(_keptWords(pending.reading, pending.payload), pending.command, null, pending.reading.trailing)];
    }
    if (choice is CardChoiceNew) {
      final title = pending.card.newTitle;
      if (pending.atStart || pending.declined != null) {
        _routed = null;
        steps.addAll([..._settleTakeBack(), LiveStepRouteNew(title: title, task: task || titleKind(title) == TitleKind.task), LiveStepChip(view: RouteViewMoved(title: title))]);
        steps.addAll(_payload(pending.command, pending.payload, task: task));
        return steps;
      }
      if (pending.stays != null) return [...steps, ..._restore(pending)];
      // Not at the start: a new note for the payload alone, made at Done.
      return [...steps, ..._keep(pending.payload, pending.command, 'The words stay here: a new note for them is made from the start of a recording.')];
    }
    final chosenId = (choice as CardChoiceNote).id;
    LiveCandidate<N>? candidate;
    for (final c in [...pending.card.candidates, ...ctx.notes]) {
      if (c.id == chosenId) {
        candidate = c;
        break;
      }
    }
    if (candidate == null) return pending.stays != null ? [...steps, ..._restore(pending)] : steps;
    final body = liveNoteBody(candidate.note);
    final refused = _refusal(candidate, ctx);
    if (refused != null) {
      if (pending.declined != null) return [...steps, LiveStepChip(view: RouteViewSaid(text: refused))];
      if (pending.stays != null) return [...steps, ..._restore(pending, refused)];
      return [...steps, ..._keep(pending.payload, pending.command, refused, pending.reading.trailing)];
    }
    if (pending.atStart || pending.declined != null) {
      final placing = placingFor(body, said: _saidOf(pending.reading), heading: pending.reading.heading, move: pending.declined != null);
      final spot = spotOf(body, placing);
      final routed = _Routed(id: candidate.id, title: candidate.title, awaiting: false, name: pending.reading.name, words: withoutFinalStop(_commandWordsOf(pending.command.text)));
      _routed = routed;
      steps.addAll([
        ..._settleTakeBack(),
        LiveStepRoute(note: candidate.note, title: candidate.title, placing: placing, move: pending.declined != null, spot: spot),
        LiveStepChip(view: RouteViewMoved(title: candidate.title, spot: spot)),
      ]);
      if (pending.payload.isNotEmpty) {
        steps.addAll(_payload(pending.command, pending.payload, task: task));
      } else if (pending.after.isEmpty && pending.declined == null) {
        routed.awaiting = true;
      }
      return steps;
    }
    final placing = placingFor(body, said: _saidOf(pending.reading), heading: pending.reading.heading);
    final id = _nextId++;
    final segments = pending.payload.isNotEmpty ? payloadWords(pending.command, pending.payload, task: task) : pending.after;
    // The words said since, sent there instead: out of the take, and out of its better words.
    if (pending.payload.isEmpty && pending.after.isNotEmpty) {
      final after = pending.after;
      steps.add(_unword(after));
      steps.addAll(after.map(_spanStep));
    }
    for (final segment in segments) {
      _record(_Where.insert(id), segment);
    }
    steps.addAll([LiveStepInsert(id: id, note: candidate.note, title: candidate.title, placing: placing, segments: segments), LiveStepInsertEnd(id: id), const LiveStepHaptic(haptic: Haptic.success)]);
    return steps;
  }

  /// The name the last command ran to the phrase's end with, read again with this phrase.
  List<LiveStep<N>>? _grow(_Growing<N> growing, Segment segment, LiveContext<N> ctx, int now) {
    final joined = '${growing.words} ${withoutFinalStop(segment.text)}';
    final grownName = growing.reading.name.toLowerCase();
    final readings = readRoute(joined).where((r) => r.shape == growing.reading.shape && r.name.toLowerCase().startsWith(grownName) && r.name.length > growing.reading.name.length);
    final before = nameWords(growing.reading.name).words.map(_five).toSet();
    ({Reading reading, FoundResolved<LiveCandidate<N>> found})? best;
    for (final reading in readings) {
      final found = _find(reading, ctx);
      if (found is! FoundResolved<LiveCandidate<N>> || found.score <= growing.score || _refusal(found.note, ctx) != null) continue;
      final title = nameWords(found.note.title);
      final added = nameWords(reading.name.substring(growing.reading.name.length)).words;
      // Grown only by a title word the name lacked, never by one it had ("house" | "Household bills" is words).
      if (!added.any((w) => title.words.contains(w) && !before.contains(_five(w)))) continue;
      if (best == null || found.score > best.found.score) best = (reading: reading, found: found);
    }
    if (best == null) return null;
    final payload = payloadOf(best.reading.payload);
    final steps = <LiveStep<N>>[LiveStepCommand(span: _spanOf(segment))];
    final note = best.found.note;
    final body = liveNoteBody(note.note);
    // Over the lock screen, as for any note named: no title said (`_resolved`).
    final title = ctx.locked ? 'the note you named' : note.title;
    final placing = placingFor(body, said: _saidOf(best.reading));
    final spot = spotOf(body, placing);
    final same = note.id == liveNoteId(growing.note);
    final into = growing.into;
    if (!same) {
      if (into == null) {
        _routed = _Routed(id: note.id, title: title, awaiting: payload.isEmpty, name: best.reading.name, words: joined);
        steps.addAll([..._settleTakeBack(), LiveStepRoute(note: note.note, title: title, placing: placing, move: false, spot: spot)]);
      } else {
        _rehome(into);
        steps.add(LiveStepInsertDrop(id: into));
        final id = _nextId++;
        steps.add(LiveStepInsert(id: id, note: note.note, title: title, placing: placing, segments: const []));
        _opened = _Opened(id: id, note: note.note, title: title, count: 0, lastAt: now, words: joined);
      }
    }
    if (payload.isNotEmpty) {
      if (into == null || !same) {
        if (_routed != null) _routed!.awaiting = false;
        if (into == null) {
          steps.addAll(_payload(segment, payload));
        } else if (_opened != null) {
          final to = _opened!.id;
          for (final piece in payloadWords(segment, payload)) {
            steps.add(_place(_Where.insert(to), piece));
          }
          steps.addAll(_closeInsert());
        }
      } else {
        for (final piece in payloadWords(segment, payload)) {
          steps.add(_place(_Where.insert(into), piece));
        }
      }
    }
    steps.add(LiveStepChip(view: payload.isNotEmpty ? RouteViewMoved(title: title, spot: spot) : RouteViewWaiting(title: title)));
    return steps;
  }

  List<LiveStep<N>> _closeInsert() {
    final opened = _opened;
    _opened = null;
    if (opened == null) return [];
    return [LiveStepInsertEnd(id: opened.id)];
  }

  /// A keyworded phrase that is no route: for the reader at Done at the take's start (`_doneReaderMark`), else queued
  /// or left out.
  List<LiveStep<N>> _notRoute(String words, LiveContext<N> ctx, {required bool atStart}) {
    // "Hey Ghost, fix the spelling", "make a list called packing" first: the recording's one command, read at Done as
    // ever.
    if (atStart) return _doneReaderMark;
    final run = runOf(words);
    _engage();
    if (_routed == null && !ctx.locked) {
      final said = capitalise(withoutFinalStop(words));
      return [
        LiveStepAsk(run: run, instruction: withoutFinalStop(words)),
        LiveStepChip(view: RouteViewSaid(text: "“${said.length > 40 ? '${said.substring(0, 40)}…' : said}” runs when you're done.")),
        LiveStepLog(line: 'Queued “$said” for after the recording'),
      ];
    }
    return [
      const LiveStepChip(view: RouteViewSaid(text: "That can't run in the middle of a recording, so it was left out.")),
      LiveStepLog(line: "Left out “${withoutFinalStop(words)}”: it can't run mid-recording"),
    ];
  }

  /// A phrase with no keyword: a command only when it passes the bare gate (`_bareReading`), carried out as a keyed
  /// clear name is: sticky at the start of a fresh recording, a one-shot mid-take, "move this to X" moving the take.
  /// Else words, untouched. No card, no hold, no chip: what the keyword adds is `_command`, and a "No note called…"
  /// card mid-dictation for a sentence that was never a command is the failure that asked for the keyword in the first
  /// place (§38). "New note" alone starts one; "another note" does not, since "Another note:" is how people introduce
  /// their next point. "Actually, add …" is the command, as after the keyword.
  List<LiveStep<N>> _bare(Segment segment, LiveContext<N> ctx, int now) {
    final words = commandAfterOpener(commandWords(segment.text));
    if (_newNote.hasMatch(withoutFinalStop(words))) return [_spanStep(segment), ..._newNoteSaid(ctx, atStart: _atStart)];
    final chosen = _bareReading(words, ctx);
    if (chosen == null) return [_words(segment)];
    final reading = _endedAs(chosen.reading, segment.text);
    return [_spanStep(segment), ..._resolved(reading, chosen.note, chosen.score, payloadOf(reading.payload), segment, ctx, now, atStart: _atStart)];
  }
}

String _five(String word) => word.length > 5 ? word.substring(0, 5) : word;

final RegExp _phraseEnd = RegExp(r'([.!?…])["”]?\s*$');
final RegExp _closedEnd = RegExp(r'[.!?…]["”]?$');

/// A reading with the phrase's own full stop given back to whatever ends it: the grammar reads without it (a
/// phrase-final stop is never a separator), but the words that end the phrase end with it, so a sentence said next
/// starts a new one.
Reading _endedAs(Reading reading, String phrase) {
  final end = _phraseEnd.firstMatch(phrase)?.group(1) ?? '';
  bool open(String text) => text != '' && !_closedEnd.hasMatch(text);
  if (end.isEmpty) return reading;
  if (reading.trailing.isNotEmpty) return open(reading.trailing) ? reading.copyWith(trailing: '${reading.trailing}$end') : reading;
  return open(reading.payload) ? reading.copyWith(payload: '${reading.payload}$end') : reading;
}

/// The command's words of a phrase: after the keyword, the lead-ins gone.
String _commandWordsOf(String text) {
  final heard = hearKeyword(text, (_) => true);
  return commandWords(heard != null ? heard.after : text);
}

final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether text lays out as anything: "Bullet point." alone does not, until its item comes.
bool _renderable(String text) => _letterOrDigit.hasMatch(text);

/// Where the words will go, in words: "under Electrical", "in its to-do list", or null for the end.
String? spotOf(String body, Placing placing) {
  switch (placing) {
    case PlacingEnd():
      return null;
    case PlacingLane():
      return 'in ${placing.lane}';
    case PlacingLists():
      final heading = placing.heading;
      if (heading != null && heading.isNotEmpty) return 'under $heading';
      final fresh = placing.fresh;
      if (fresh != null) return fresh == PlacingFresh.task ? 'in a new to-do list' : 'in a new list';
      final runs = runsOf(body.split('\n'));
      if (runs.length == 1) return runs[0].style.task ? 'in its to-do list' : 'in its list';
      return placing.task && runs.any((run) => run.style.task) ? 'in its to-do list' : 'in its lists';
  }
}

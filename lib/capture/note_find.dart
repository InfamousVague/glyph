/// The note a spoken name means, read by its words: "house to do's", "the house list", "house chores" and "house" are
/// all House TODOs. A port of `src/app/capture/noteFind.ts`.
///
/// Matt, after "add a note to house to do's" made a new note: "The AI should first step try to find a note that the
/// person is talking about … house to do's, house list items, house chores." The letters-first matcher before this
/// (route.dart `similarity`) scored "house chores" 0.5 against House TODOs and "house list items" 0.4, so a command
/// that named a note plainly found none. Here a name is read as two kinds of word:
///
/// - The distinctive words say which note: "house", "hello trade", "weekend". Every one of them must be in the title
///   (or begin one of its words, "household" for "house"), and the score is how much of the title they cover.
/// - The kind words say what sort of note it is: to-do, task, chore and job, which are specific, and list, item,
///   stuff, thing, note and page, which are generic. They never decide which note. A specific one the title shares,
///   or a generic one where the title or the note's body has a list, backs the match up.
///
/// One spelling of to-do before anything is compared: "to do's", "to-dos", "todos", "2 dos" and "two dos" are "todo".
/// A name made only of kind words ("my to-do list", "tasks") can only mean a title made only of them too. Letter
/// pairs are the fallback for words run together or split ("hello trade" and HelloTrade), and only between strings of
/// about the same length, so "groceries and eggs" is not Groceries.
///
/// The answer says how sure it is: `resolved` (one clear note), `current` (the note being written to: "the list",
/// "here", or one of its headings), `unsure` (a few close titles, for a card to choose between) or `missing` (with
/// any titles that come near). Both readers use it: the one that reads a phrase as it is said (live_route.dart) and
/// the one that reads the finished recording (command.dart, final_instruction.dart). Pure, so every name is a test.
///
/// What differs: the shapes. `FIND` is the record [find]; `Found` is a sealed class with one subclass per `status`
/// ([FoundResolved], [FoundCurrent], [FoundUnsure], [FoundMissing]); `titleKind` answers a [TitleKind] or null where
/// the web answers `'task' | 'bullet' | null`; the note being written to is an [Aim]; a candidate's optional
/// `note?.body` is read through `Candidate.noteBody`; `nameScore` takes `hasList` and `findNote` takes `aim` as named
/// parameters.
library;

import 'dart:math' as math;

import '../core/boards.dart' show lanesOf;
import '../core/front_matter.dart' show frontMatterEnd;
import '../core/item_syntax.dart' show listLead;
import 'route.dart' show Candidate, dice;

/// The bars a name has to clear, in one place (docs/DESIGN.md §126), the web's `FIND`.
///
/// - `resolved`, `margin`: the best score this high, and clear of the next by `margin`, is the note.
/// - `exact`: two titles this close to perfect are a tie, whatever the margin.
/// - `unsure`, `within`: below `resolved` but this high: unsure, with the titles within `within` of the best.
/// - `near`: a title this near a name that matched nothing is offered beside it.
/// - `clear`: a note this sure is the one meant with no keyword said, or after a mishearing of it (live_command.dart
///   `bareCommand`): the whole of the title's distinctive words. A name that is only the start of a title scores
///   0.85 (`covered`), which is not clear: "bank" is not Bank statements, "weekend" is not Weekend trip.
const ({double resolved, double margin, double exact, double unsure, double within, double near, double clear}) find = (
  resolved: 0.72,
  margin: 0.08,
  exact: 0.99,
  unsure: 0.6,
  within: 0.15,
  near: 0.4,
  clear: 0.9,
);

/// Kind words that name a kind of list: a to-do list and a chore list are both lists of things to do.
const Set<String> _specific = {'todo', 'task', 'chore', 'job'};

/// Kind words that say only that it is a list, or a note.
const Set<String> _generic = {'list', 'item', 'stuff', 'thing', 'note', 'page'};

/// Words that carry nothing of a name.
const Set<String> _stop = {'the', 'my', 'a', 'an', 'our', 'your', 'and', 'of', 'around'};

/// A name or a title, as its words: all of them, the distinctive ones, and the kind words by kind.
class NameWords {
  const NameWords({required this.words, required this.distinctive, required this.specific, required this.generic});

  final List<String> words;
  final List<String> distinctive;
  final List<String> specific;
  final List<String> generic;

  @override
  bool operator ==(Object other) =>
      other is NameWords &&
      _sameList(other.words, words) &&
      _sameList(other.distinctive, distinctive) &&
      _sameList(other.specific, specific) &&
      _sameList(other.generic, generic);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(words), Object.hashAll(distinctive), Object.hashAll(specific), Object.hashAll(generic));

  @override
  String toString() => '{words: $words, distinctive: $distinctive, specific: $specific, generic: $generic}';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final RegExp _curlyQuotes = RegExp('[’‘`]');
final RegExp _todos = RegExp(r"\b(?:to|two|2)[\s-]*do(?:'?s|es)\b");
final RegExp _todo = RegExp(r'\b(?:to|2)[\s-]*do\b');
final RegExp _notLetters = RegExp(r'[^\p{L}\p{N}\s]+', unicode: true);
final RegExp _spaces = RegExp(r'\s+');

/// Lowercase words, one spelling of to-do, apostrophes and punctuation gone.
String _normalised(String text) => text
    .toLowerCase()
    .replaceAll(_curlyQuotes, "'")
    .replaceAll(_todos, ' todos ')
    .replaceAll(_todo, ' todo ')
    .replaceAll("'", '')
    .replaceAll(_notLetters, ' ')
    .replaceAll(_spaces, ' ')
    .trim();

/// A plural's s dropped, so "chores" is "chore" and "todos" is "todo".
String _single(String word) =>
    word.length > 3 && word.endsWith('s') && !word.endsWith('ss') ? word.substring(0, word.length - 1) : word;

/// The words of a name or a title, sorted by what they say.
NameWords nameWords(String text) {
  final words = [
    for (final word in _normalised(text).split(' '))
      if (word.isNotEmpty && !_stop.contains(word)) _single(word),
  ];
  return NameWords(
    words: words,
    distinctive: [
      for (final word in words)
        if (!_specific.contains(word) && !_generic.contains(word)) word,
    ],
    specific: [
      for (final word in words)
        if (_specific.contains(word)) word,
    ],
    generic: [
      for (final word in words)
        if (_generic.contains(word)) word,
    ],
  );
}

/// The kind of list a title says a note is: a to-do list, or a plain one (the web's `'task' | 'bullet'`).
enum TitleKind { task, bullet }

final RegExp _shopping = RegExp(r'^(?:grocer(?:y|ie)|shopping)$');

/// The kind of list a title says a note is, by the word it ends on: a to-do list ("House TODOs", "Chores", "Task
/// list"), a plain list ("Groceries", "Packing list"), or neither. Only its last word, which is what a title names:
/// "Task Management" is about tasks, not a list of them.
TitleKind? titleKind(String title) {
  final words = nameWords(title).words;
  if (words.isEmpty) return null;
  final head = words.last;
  if (_specific.contains(head)) return TitleKind.task;
  if (head == 'list' || head == 'item') {
    return words.sublist(0, words.length - 1).any(_specific.contains) ? TitleKind.task : TitleKind.bullet;
  }
  if (_shopping.hasMatch(head)) return TitleKind.bullet;
  return null;
}

/// Whether two words are one: the same, or one the start of the other when both are long ("household", "house").
bool _same(String said, String titled) {
  if (said == titled) return true;
  if (math.min(said.length, titled.length) < 5) return false;
  return titled.startsWith(said) || said.startsWith(titled);
}

/// [words] with any two in a row joined where the other side has them as one word: "hello trade" for HelloTrade.
List<String> _joined(List<String> words, List<String> other) {
  final out = <String>[];
  for (var i = 0; i < words.length; i += 1) {
    final word = words[i];
    final next = i + 1 < words.length ? words[i + 1] : null;
    if (next != null && !other.contains(word) && other.contains(word + next)) {
      out.add(word + next);
      i += 1;
    } else {
      out.add(word);
    }
  }
  return out;
}

/// Letter pairs, spaces gone, only between strings of about the same length.
double _letters(NameWords name, NameWords title) {
  final a = name.words.join();
  final b = title.words.join();
  if (a.isEmpty || b.isEmpty) return 0;
  final ratio = a.length / b.length;
  if (ratio < 0.8 || ratio > 1.25) return 0;
  return dice(a, b);
}

/// How well the distinctive words [said] cover [titled], or null when one of them is not in it.
({double score, bool prefix})? _covered(List<String> said, List<String> titled) {
  final saidWords = _joined(said, titled);
  final titleWords = <String>{..._joined(titled, saidWords)}.toList();
  if (!saidWords.every((word) => titleWords.any((title) => _same(word, title)))) return null;
  final share = titleWords.where((title) => saidWords.any((word) => _same(word, title))).length / titleWords.length;
  // The whole start of the title ("weekend" for Weekend trip to the lake) is a fair pick, a little below an exact one.
  var prefix = true;
  for (var i = 0; i < saidWords.length; i += 1) {
    if (i >= titleWords.length || !_same(saidWords[i], titleWords[i])) {
      prefix = false;
      break;
    }
  }
  return (score: 0.6 + 0.3 * share, prefix: prefix);
}

/// JavaScript's `Math.round`: halves go up.
double _round(double value) => (value + 0.5).floorToDouble();

/// How well a spoken name fits a title, 0 to 1. [hasList] says the note's body keeps a list, which backs up a name
/// that said "list".
double nameScore(NameWords name, NameWords title, {bool hasList = false}) {
  if (name.words.isEmpty || title.words.isEmpty) return 0;
  if (name.words.join(' ') == title.words.join(' ')) return 1;
  final sharesKind = name.specific.any(title.specific.contains);
  if (name.distinctive.isEmpty) {
    // Kind words alone: only a title of kind words alone, and a different kind of list is at most a maybe.
    if (title.distinctive.isNotEmpty) return 0;
    if (sharesKind) return 0.9;
    return name.generic.isNotEmpty && (title.specific.isNotEmpty || title.generic.isNotEmpty) ? 0.65 : 0;
  }
  final words = _covered(name.distinctive, title.distinctive);
  if (words == null) return _letters(name, title);
  var score = words.prefix ? math.max(words.score, 0.85) : words.score;
  if (sharesKind) {
    score += 0.1;
  } else if (name.generic.isNotEmpty && (title.specific.isNotEmpty || title.generic.isNotEmpty || hasList)) {
    score += 0.05;
  }
  // Rounded, so a sum of tenths that is 1 compares as 1.
  return math.min(1, _round(score * 1000) / 1000);
}

/// How near a title comes to a name that matched nothing, kind words counted as words: for "No note called …" to
/// offer it.
double _nearScore(NameWords name, NameWords title) {
  final words = _covered(name.words, title.words);
  final a = name.words.join();
  final b = title.words.join();
  return math.max(words?.score ?? 0, a.isNotEmpty && b.isNotEmpty ? dice(a, b) : 0);
}

/// A list in [body], after its front matter: any list, or a to-do one.
bool _listIn(String body, [bool todo = false]) {
  final lines = body.split('\n');
  return lines.sublist(frontMatterEnd(lines)).any((line) {
    final lead = listLead(line);
    return lead != null && (!todo || lead.done != null);
  });
}

final RegExp _fenceMarker = RegExp(r'^\s*(`{3,}|~{3,})');
final RegExp _headingLine = RegExp(r'^#{1,6}\s+(.+?)\s*#*\s*$');
final RegExp _titleLine = RegExp(r'^#\s');
final RegExp _labelLine = RegExp(r'^[^\s:][^:]{0,40}:\s*$');
final RegExp _labelColon = RegExp(r':\s*$');

/// The headings of a note, fence-aware and after its front matter, with its "Label:" lines and its board's lanes:
/// the places inside it a name can mean. Not the note's own title, which names the note.
List<String> headingsOf(String body) {
  final lines = body.split('\n');
  final start = frontMatterEnd(lines);
  final out = <String>[];
  String? fence;
  var titled = false;
  for (var i = start; i < lines.length; i += 1) {
    final line = lines[i];
    final marker = _fenceMarker.firstMatch(line)?.group(1);
    if (marker != null && marker.isNotEmpty) {
      if (fence == null) {
        fence = marker[0];
      } else if (marker[0] == fence) {
        fence = null;
      }
      continue;
    }
    if (fence != null || line.trim().isEmpty) continue;
    final heading = _headingLine.firstMatch(line);
    if (heading != null) {
      if (!titled && out.isEmpty && _titleLine.hasMatch(line)) {
        titled = true;
        continue;
      }
      out.add(heading.group(1)!);
    } else if (_labelLine.hasMatch(line) && listLead(line) == null) {
      out.add(line.trim().replaceFirst(_labelColon, ''));
    }
    titled = true;
  }
  return [...out, for (final lane in lanesOf(body)) lane.name];
}

/// Whether [body] has a heading, a "Label:" line or a lane that [heading] names ([headingsOf]), as surely as a note
/// is found (`find.resolved`): "under the sofa" in House TODOs names none, so it is words of the thing, not a place.
bool headingIn(String body, String heading) {
  final said = nameWords(heading);
  return headingsOf(body).any((text) => nameScore(said, nameWords(text)) >= find.resolved);
}

/// The note being written to, as `findNote` reads it: its id and its body (the web's `{ id: string; body: string }`).
class Aim {
  const Aim({required this.id, required this.body});

  final String id;
  final String body;
}

/// What a spoken name came to (`Found`).
sealed class Found<N> {
  const Found();

  /// The web's `status`: `resolved`, `current`, `unsure` or `missing`.
  String get status;
}

/// One clear note.
final class FoundResolved<N> extends Found<N> {
  const FoundResolved({required this.note, required this.score});

  final N note;
  final double score;

  @override
  String get status => 'resolved';

  @override
  bool operator ==(Object other) => other is FoundResolved && other.note == note && other.score == score;

  @override
  int get hashCode => Object.hash(status, note, score);

  @override
  String toString() => '{status: resolved, note: $note, score: $score}';
}

/// The note being written to: "the list", "here", or one of its own headings ([heading]).
final class FoundCurrent<N> extends Found<N> {
  const FoundCurrent({required this.heading});

  final String? heading;

  @override
  String get status => 'current';

  @override
  bool operator ==(Object other) => other is FoundCurrent && other.heading == heading;

  @override
  int get hashCode => Object.hash(status, heading);

  @override
  String toString() => '{status: current, heading: $heading}';
}

/// A few titles close together: a card chooses.
final class FoundUnsure<N> extends Found<N> {
  const FoundUnsure({required this.candidates, required this.score});

  final List<N> candidates;
  final double score;

  @override
  String get status => 'unsure';

  @override
  bool operator ==(Object other) => other is FoundUnsure && _sameList(other.candidates, candidates) && other.score == score;

  @override
  int get hashCode => Object.hash(status, Object.hashAll(candidates), score);

  @override
  String toString() => '{status: unsure, candidates: $candidates, score: $score}';
}

/// Nothing clear: [near] are the titles that came closest, if any came near at all.
final class FoundMissing<N> extends Found<N> {
  const FoundMissing({required this.near});

  final List<N> near;

  @override
  String get status => 'missing';

  @override
  bool operator ==(Object other) => other is FoundMissing && _sameList(other.near, near);

  @override
  int get hashCode => Object.hash(status, Object.hashAll(near));

  @override
  String toString() => '{status: missing, near: $near}';
}

/// A name that means the note being written to, whatever it is called.
final RegExp _here = RegExp(r'^(?:(?:the|this|my)\s+(?:list|note|page)|here|in\s+here|this\s+one)$', caseSensitive: false);

final RegExp _quotes = RegExp('[“”"]');
final RegExp _stops = RegExp(r'[.,;:!?]+');

/// A spoken name, cleaned for reading: quotes, punctuation and a leading "the", "my" or "our" gone.
String spokenName(String raw) => raw.replaceAll(_quotes, '').replaceAll(_stops, ' ').replaceAll(_spaces, ' ').trim();

/// [items] best first by [score], equals in the order they came, as JavaScript's stable sort leaves them.
List<({T item, double score})> _ranked<T>(Iterable<T> items, double Function(T) score) {
  final out = <({T item, double score})>[];
  for (final item in items) {
    final scored = (item: item, score: score(item));
    var at = out.length;
    while (at > 0 && out[at - 1].score < scored.score) {
      at -= 1;
    }
    out.insert(at, scored);
  }
  return out;
}

/// The note [raw] names, and how sure that is. [notes] are the candidates, newest first; [aim] is the note being
/// written to, whose own lists and headings a name can mean.
Found<N> findNote<N extends Candidate>(String raw, Iterable<N> notes, {Aim? aim}) {
  final said = spokenName(raw);
  if (_here.hasMatch(said)) return FoundCurrent<N>(heading: null);
  final name = nameWords(said);
  if (name.words.isEmpty) return FoundMissing<N>(near: const []);
  // "My to-do list", "the tasks", said with a note open that has such a list: that note.
  if (aim != null && name.distinctive.isEmpty && (name.specific.isNotEmpty ? _listIn(aim.body, true) : _listIn(aim.body))) {
    return FoundCurrent<N>(heading: null);
  }

  final titled = [
    for (final note in notes)
      if (note.title.trim().isNotEmpty) note,
  ];
  final ranked = _ranked<N>(titled, (note) {
    final body = note.noteBody;
    return nameScore(name, nameWords(note.title), hasList: body != null ? _listIn(body) : false);
  });

  // A heading or a lane of the note being written to, named better than any other note: that note, under it.
  if (aim != null) {
    final headings = _ranked<String>(headingsOf(aim.body), (text) => nameScore(name, nameWords(text)));
    if (headings.isNotEmpty) {
      final heading = headings.first;
      var other = 0.0;
      for (final candidate in ranked) {
        if (candidate.item.id != aim.id) {
          other = candidate.score;
          break;
        }
      }
      if (heading.score >= find.resolved && heading.score > other) return FoundCurrent<N>(heading: heading.item);
    }
  }

  if (ranked.isEmpty || ranked.first.score < find.unsure) {
    final near = _ranked<N>(titled, (note) => _nearScore(name, nameWords(note.title)))
        .where((candidate) => candidate.score >= find.near)
        .take(5)
        .map((candidate) => candidate.item)
        .toList();
    return FoundMissing<N>(near: near);
  }
  final best = ranked.first;
  final exact = ranked.where((candidate) => candidate.score >= find.exact).toList();
  if (exact.length > 1) {
    return FoundUnsure<N>(candidates: [for (final c in exact.take(3)) c.item], score: best.score);
  }
  final close = ranked.where((candidate) => best.score - candidate.score < find.margin).toList();
  if (best.score >= find.resolved && close.length == 1) return FoundResolved<N>(note: best.item, score: best.score);
  final within = ranked.where((candidate) => candidate.score >= find.unsure && best.score - candidate.score <= find.within);
  return FoundUnsure<N>(candidates: [for (final c in within.take(3)) c.item], score: best.score);
}

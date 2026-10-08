/// "Add to Weekend trip": sending what is being said to a note by naming it. A port of `src/app/capture/route.ts`.
///
/// Two halves, both pure so they are tested without a microphone:
///
/// - [parseRoute] finds the spoken command in a phrase. It accepts the ways people say it ("add to", "add this to",
///   "put that in", "move it to my", "switch to", "go to … note", "leave a note for … that says") at the start or
///   the end of a phrase, and hands back the words around it so they can be kept. "New note" said on its own is the
///   other command. A name that could still be growing - a phrase that stops without a full stop right after it -
///   does not count yet, and a name of a letter or two never does.
///
/// - [matchNote] finds the note a spoken name means. Speech recognition hears "week end trip", "weekend trips" and
///   "the weekend trip note", so titles are compared by their words and by their letters, and the best one only
///   counts when it clearly wins. "Put it in the oven" routes nowhere unless there is a note called Oven: a command
///   that moves words to the wrong note is worse than one that is missed, which only means saying it again.
///
/// What differs: the shapes. The web's `RouteCommand` union is a sealed class with one subclass per `kind`
/// ([RouteCommandNote], [RouteCommandItem], [RouteCommandLeave], [RouteCommandNew]), and `TargetResolution` one per
/// `status` ([TargetResolutionResolved], [TargetResolutionAmbiguous], [TargetResolutionNotFound]). The web's
/// `Candidate` is structural (anything with an id and a title); here it is a class to construct or extend, and the
/// optional `note?: { body }` a candidate may carry on the web is its `noteBody` getter, null unless overridden.
/// `matchNote` and `resolveTarget` take `threshold` and `margin` as named parameters where the web takes an options
/// object.
library;

import 'dart:math' as math;

/// The route command a phrase carries (`RouteCommand`).
sealed class RouteCommand {
  const RouteCommand({required this.rest});

  /// The web's `kind`: `note`, `item`, `leave` or `new`.
  String get kind;

  /// What was said before and after the command in the same phrase.
  final String rest;
}

/// `kind: 'note'`: the words go to the note named.
final class RouteCommandNote extends RouteCommand {
  const RouteCommandNote({required this.name, required super.rest});

  /// The name as heard, cleaned of "my", "the" and a trailing "note".
  final String name;

  @override
  String get kind => 'note';

  @override
  bool operator ==(Object other) => other is RouteCommandNote && other.name == name && other.rest == rest;

  @override
  int get hashCode => Object.hash(kind, name, rest);

  @override
  String toString() => '{kind: note, name: $name, rest: $rest}';
}

/// `kind: 'item'`. "New item for AttackFM": an item for that note's list, not the whole take.
final class RouteCommandItem extends RouteCommand {
  const RouteCommandItem({required this.name, required super.rest, required this.task, required this.many});

  final String name;

  /// "task" or "to-do" was said: a note with no list starts a to-do list.
  final bool task;

  /// "items" or "tasks": every phrase until a pause is an item, not just the next one.
  final bool many;

  @override
  String get kind => 'item';

  @override
  bool operator ==(Object other) =>
      other is RouteCommandItem && other.name == name && other.rest == rest && other.task == task && other.many == many;

  @override
  int get hashCode => Object.hash(kind, name, rest, task, many);

  @override
  String toString() => '{kind: item, name: $name, rest: $rest, task: $task, many: $many}';
}

/// `kind: 'leave'`. "Leave a note on the page for AttackFM that says …": the words go into that note where they fit,
/// into its list when it has one. With nothing after the name, the next phrase is the note.
final class RouteCommandLeave extends RouteCommand {
  const RouteCommandLeave({required this.name, required super.rest});

  final String name;

  @override
  String get kind => 'leave';

  @override
  bool operator ==(Object other) => other is RouteCommandLeave && other.name == name && other.rest == rest;

  @override
  int get hashCode => Object.hash(kind, name, rest);

  @override
  String toString() => '{kind: leave, name: $name, rest: $rest}';
}

/// `kind: 'new'`: "new note" said on its own.
final class RouteCommandNew extends RouteCommand {
  const RouteCommandNew({required super.rest});

  @override
  String get kind => 'new';

  @override
  bool operator ==(Object other) => other is RouteCommandNew && other.rest == rest;

  @override
  int get hashCode => Object.hash(kind, rest);

  @override
  String toString() => '{kind: new, rest: $rest}';
}

const String _verb = r'(?:add|put|send|save|move|stick|file|append)';
const String _object = r'(?:\s+(?:this|that|it|these|those|them|everything)(?:\s+(?:bit|part|stuff))?)?';
const String _prep = r'\s+(?:to|in|into|onto|on)';
const String _switch = r'(?:switch|go|jump|change)\s+(?:back\s+)?to';
const String _opener = '(?:$_verb$_object$_prep|$_switch)';

/// "my", "the", "our" before a name, "note" or "notes" after it.
final RegExp _fillerBefore = RegExp(r'^(?:(?:the|my|our|a)\s+)+', caseSensitive: false);
final RegExp _fillerAfter = RegExp(r'\s+(?:note|notes|list|page)$', caseSensitive: false);

/// The command and the name after it, running to the end of the phrase.
final RegExp _atEnd = RegExp('(?:^|[.,;!?]\\s+|\\s+and\\s+|\\s+)$_opener\\s+(.+?)[.!?]*\\s*\$', caseSensitive: false);

/// The command at the start, its name ending at the first stop or comma.
final RegExp _atStart = RegExp('^\\s*$_opener\\s+([^.,;!?]+)[.,;!?]\\s*(.+)\$', caseSensitive: false);

/// "New note", and what base.en writes for it said quickly: "new notes", "new node".
final RegExp _newNote = RegExp(r'^\s*(?:new|start\s+a\s+new|another)\s+(?:notes?|node)[.!]?\s*$', caseSensitive: false);

/// "New item for AttackFM", "add a task to the backlog", "new to-dos for work: call Sam, email Jo". The name runs to
/// the first stop or comma; the item, if it came in the same phrase, is what follows. A command at the START of the
/// phrase only: "the new item for AttackFM is great" is a sentence.
final RegExp _itemCommand = RegExp(
  r'^\s*(?:(?:ok(?:ay)?|so|and)[,\s]+)?(?:(?:add|put|make)\s+(?:a|an|another|some)?\s*|(?:a\s+|an\s+)?(?:new|another)\s+)(items?|tasks?|to-?\s?dos?|entry|entries|points?|things?)\s+(?:for|to|on|in(?:to)?)\s+(?:the\s+|my\s+|our\s+)?([^.,;:!?]+?)(?:\s+(?:note|list))?(?:[.,;:!?]\s*(.*))?\s*$',
  caseSensitive: false,
);

/// "Leave a note on the page for AttackFM that says the login is broken", "add a note to shopping saying we're out
/// of eggs", "write a line in work: call Sam". The name runs to what introduces the note ("that says", "saying",
/// "that", a comma or colon); a phrase that stops after the name is waiting for the note to be said. A command at
/// the START of a phrase only.
final RegExp _leave = RegExp(
  r'^\s*(?:(?:ok(?:ay)?|so|and|please|hey)[,\s]+)?(?:(?:can|could|would)\s+you\s+)?(?:leave|add|put|write|drop|make|jot(?:\s+down)?|stick|pop)\s+(?:(?:a|an|another|one\s+more)\s+)?(?:quick\s+|little\s+|short\s+)?(?:note|line|comment|reminder|memo)\s+(?:on|in|to|for|into|onto|under)\s+(?:(?:the|my|our)\s+)?(?:(?:page|note)\s+(?:for|called|named|titled|about)\s+)?(?:(?:the|my|our)\s+)?([^.,;:!?]+?)(?:\s+(?:page|note))?(?:\s*(?:[,:;]|\s(?:that\s+says|which\s+says|that\s+reads|saying|to\s+say|that))\s*(.*?))?[.!?]*\s*$',
  caseSensitive: false,
);

final RegExp _namePunctuation = RegExp(r'[.,;:!?"“”]+');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _trailingAnd = RegExp(r'\s+and\s*$', caseSensitive: false);
final RegExp _restEdges = RegExp(r'^[\s,;:]+|[\s,;:]+$');
final RegExp _stopAtEnd = RegExp(r'[.!?]\s*$');
final RegExp _taskNoun = RegExp(r'^(?:task|to-?do)');

String _cleanName(String raw) => raw
    .replaceAll(_namePunctuation, ' ')
    .replaceAll(_spaces, ' ')
    .trim()
    .replaceFirst(_fillerBefore, '')
    .replaceFirst(_fillerAfter, '')
    .trim();

String _tidyRest(String text) => text.replaceFirst(_trailingAnd, '').replaceAll(_restEdges, '').trim();

/// The route command in [text], if there is one.
RouteCommand? parseRoute(String text) {
  if (_newNote.hasMatch(text)) return const RouteCommandNew(rest: '');
  final leave = _leave.firstMatch(text);
  final leaveName = leave?.group(1);
  if (leave != null && leaveName != null && leaveName.isNotEmpty) {
    final name = _cleanName(leaveName);
    final said = leave.group(2)?.trim() ?? '';
    // "Leave a note for attack" may still be growing into its name: not yet, until the phrase ends or the note
    // itself follows.
    final ended = said != '' || _stopAtEnd.hasMatch(text);
    if (name.length >= 3 && ended) return RouteCommandLeave(name: name, rest: said);
  }
  final item = _itemCommand.firstMatch(text);
  final itemNoun = item?.group(1);
  final itemName = item?.group(2);
  if (item != null && itemNoun != null && itemNoun.isNotEmpty && itemName != null && itemName.isNotEmpty) {
    final name = _cleanName(itemName);
    final noun = itemNoun.toLowerCase().replaceAll(_spaces, '');
    // A phrase with no stop after the name ("new item for attack") may still be growing: not yet, until it ends or
    // the item follows.
    final ended = item.group(3) != null || _stopAtEnd.hasMatch(text);
    if (name.length >= 3 && ended) {
      return RouteCommandItem(
        name: name,
        rest: _tidyRest(item.group(3) ?? ''),
        task: _taskNoun.hasMatch(noun),
        many: noun.endsWith('s'),
      );
    }
  }
  final start = _atStart.firstMatch(text);
  final startName = start?.group(1);
  final startRest = start?.group(2);
  if (startName != null && startName.isNotEmpty && startRest != null && startRest.isNotEmpty) {
    final name = _cleanName(startName);
    if (name.isNotEmpty) return RouteCommandNote(name: name, rest: _tidyRest(startRest));
  }
  final end = _atEnd.firstMatch(text);
  final endName = end?.group(1);
  if (end != null && endName != null && endName.isNotEmpty) {
    final name = _cleanName(endName);
    // A name of real length: "add to we" is a sentence being said, not a note.
    if (name.length >= 3) {
      return RouteCommandNote(name: name, rest: _tidyRest(text.substring(0, end.start)));
    }
  }
  return null;
}

// ---- matching a name to a note ------------------------------------------------------------------------------------

/// A note a spoken name can mean: its id and the title it is known by (`Candidate`).
class Candidate {
  const Candidate({required this.id, required this.title});

  final String id;
  final String title;

  /// The body of the note this candidate carries, when it carries one: the web's optional `note?.body`, which
  /// `findNote` (note_find.dart) reads to see whether the note keeps a list. Null for a title alone.
  String? get noteBody => null;

  @override
  bool operator ==(Object other) =>
      other is Candidate && other.runtimeType == runtimeType && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);

  @override
  String toString() => '{id: $id, title: $title}';
}

/// A note and how well a name fitted it (`Match`).
class Match<T extends Candidate> {
  const Match({required this.note, required this.score});

  final T note;

  /// 0 to 1.
  final double score;

  @override
  bool operator ==(Object other) => other is Match<T> && other.note == note && other.score == score;

  @override
  int get hashCode => Object.hash(note, score);

  @override
  String toString() => '{note: $note, score: $score}';
}

/// What a spoken title came to (`TargetResolution`).
sealed class TargetResolution<T extends Candidate> {
  const TargetResolution();

  /// The web's `status`: `resolved`, `ambiguous` or `not-found`.
  String get status;
}

/// `status: 'resolved'`.
final class TargetResolutionResolved<T extends Candidate> extends TargetResolution<T> {
  const TargetResolutionResolved({required this.note, required this.score});

  final T note;
  final double score;

  @override
  String get status => 'resolved';

  @override
  bool operator ==(Object other) =>
      other is TargetResolutionResolved<T> && other.note == note && other.score == score;

  @override
  int get hashCode => Object.hash(status, note, score);

  @override
  String toString() => '{status: resolved, note: $note, score: $score}';
}

/// `status: 'ambiguous'`.
final class TargetResolutionAmbiguous<T extends Candidate> extends TargetResolution<T> {
  const TargetResolutionAmbiguous({required this.candidates});

  final List<T> candidates;

  @override
  String get status => 'ambiguous';

  @override
  bool operator ==(Object other) {
    if (other is! TargetResolutionAmbiguous<T> || other.candidates.length != candidates.length) return false;
    for (var i = 0; i < candidates.length; i += 1) {
      if (other.candidates[i] != candidates[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(status, Object.hashAll(candidates));

  @override
  String toString() => '{status: ambiguous, candidates: $candidates}';
}

/// `status: 'not-found'`.
final class TargetResolutionNotFound<T extends Candidate> extends TargetResolution<T> {
  const TargetResolutionNotFound();

  @override
  String get status => 'not-found';

  @override
  bool operator ==(Object other) => other is TargetResolutionNotFound;

  @override
  int get hashCode => status.hashCode;

  @override
  String toString() => '{status: not-found}';
}

final RegExp _notWordCharacter = RegExp(r'[^a-z0-9\s]');
const List<String> _fillerWords = ['the', 'my', 'a', 'our', 'note', 'notes'];

/// Lowercase words with punctuation and filler gone, and a plural's s dropped.
List<String> _wordsOf(String text) => text
    .toLowerCase()
    .replaceAll(_notWordCharacter, ' ')
    .split(_spaces)
    .where((w) => w.isNotEmpty && !_fillerWords.contains(w))
    .map((w) => w.length > 3 && w.endsWith('s') && !w.endsWith('ss') ? w.substring(0, w.length - 1) : w)
    .toList();

Map<String, int> _bigrams(String text) {
  final squashed = text.replaceAll(_spaces, '');
  final counts = <String, int>{};
  for (var i = 0; i < squashed.length - 1; i += 1) {
    final pair = squashed.substring(i, i + 2);
    counts[pair] = (counts[pair] ?? 0) + 1;
  }
  return counts;
}

/// Sørensen-Dice over letter pairs, spaces ignored: "week end trip" and "weekend trip" score 1.
double dice(String a, String b) {
  final x = _bigrams(a);
  final y = _bigrams(b);
  var total = 0;
  for (final n in x.values) {
    total += n;
  }
  for (final n in y.values) {
    total += n;
  }
  if (total == 0) return a == b ? 1 : 0;
  var shared = 0;
  x.forEach((pair, n) => shared += math.min(n, y[pair] ?? 0));
  return (2 * shared) / total;
}

/// How well a spoken [name] fits a note [title], 0 to 1.
double similarity(String name, String title) {
  final said = _wordsOf(name);
  final titled = _wordsOf(title);
  if (said.isEmpty || titled.isEmpty) return 0;
  final letters = dice(said.join(' '), titled.join(' '));
  final shared = said.where(titled.contains).length;
  final words = shared / math.max(said.length, titled.length);
  // A name that is the whole start of the title ("weekend" for "Weekend trip to the lake") is a fair pick, a little
  // below an exact one.
  final prefix = titled.take(said.length).join(' ') == said.join(' ') ? 0.85 : 0.0;
  return math.max(letters, math.max(words, prefix));
}

/// The note [name] means, if one clearly does: the best score must reach [threshold] and beat the runner-up by
/// [margin]. Ties go to the earlier candidate, so pass them most recent first.
Match<T>? matchNote<T extends Candidate>(String name, Iterable<T> notes, {double threshold = 0.72, double margin = 0.08}) {
  final resolved = resolveTarget<T>(name, notes, threshold: threshold, margin: margin);
  return resolved is TargetResolutionResolved<T> ? Match<T>(note: resolved.note, score: resolved.score) : null;
}

/// Resolve a spoken title without throwing away why it was unsafe to choose.
TargetResolution<T> resolveTarget<T extends Candidate>(
  String name,
  Iterable<T> notes, {
  double threshold = 0.72,
  double margin = 0.08,
}) {
  // The web's sort is stable, and ties go to the earlier candidate: an insertion sort, best first.
  final ranked = <Match<T>>[];
  for (final note in notes) {
    if (note.title.trim().isEmpty) continue;
    final scored = Match<T>(note: note, score: similarity(name, note.title));
    var at = ranked.length;
    while (at > 0 && ranked[at - 1].score < scored.score) {
      at -= 1;
    }
    ranked.insert(at, scored);
  }
  if (ranked.isEmpty) return TargetResolutionNotFound<T>();
  final best = ranked.first;
  if (best.score < threshold) return TargetResolutionNotFound<T>();
  final exact = ranked.where((candidate) => candidate.score >= 0.99).toList();
  if (exact.length > 1) return TargetResolutionAmbiguous<T>(candidates: [for (final c in exact) c.note]);
  final close = ranked.where((candidate) => best.score - candidate.score < margin).toList();
  if (close.length > 1 && best.score < 0.99) {
    return TargetResolutionAmbiguous<T>(candidates: [for (final c in close) c.note]);
  }
  return TargetResolutionResolved<T>(note: best.note, score: best.score);
}

/// Hearing a command in one committed phrase, as it is said: the keyword, and the shapes of "words for a note you
/// name". A port of `src/app/capture/liveCommand.ts`. Pure grammar, with no notes: which readings a phrase has is
/// decided here, and which note a name means is note_find.dart's and the live reader's (live_route.dart).
///
/// Whisper commits a phrase after a short quiet, so a phrase is not a sentence: nearly every one ends with Whisper's
/// own full stop, whether or not the speaker stopped there. A phrase-final stop is therefore never a separator. A
/// stop, a comma, a colon or "that says" inside the phrase is.
///
/// A command needs no keyword (docs/DESIGN.md §136; Matt: "Remove the function which expects hey ghost before
/// commands"). Without one, or after a mishearing of it, a phrase is a command only through one gate, [bareCommand]:
/// the plainest shapes, a note named clearly, the evidence that a note was meant, and its words in the same breath.
/// Both readers ask it, so a mishearing means the same to each.
///
/// What differs: the shapes. A [Reading]'s `shape` is an `Object`: the int 1 to 8, or the string `'S'`, as the web's
/// `1 | … | 8 | 'S'`. Its `placing` is a [ReadingPlacing], and [nameable] answers a [Nameable]. The note
/// `bareEvidence` and `bareCommand` weigh is a `({title, body})` record, and `bareCommand` takes `atStart` as a
/// named parameter.
library;

import 'dart:math' as math;

import 'command.dart' show findKeyword, findMisheard, leadIns, onlyFiller, withoutPayloadLead;
import 'note_find.dart' show find, headingIn, nameWords;

// ---- the keyword --------------------------------------------------------------------------------------------------

/// The keyword as heard in a phrase (`HeardKeyword`).
class HeardKeyword {
  const HeardKeyword({required this.before, required this.after, required this.misheard});

  /// Words before the keyword in the phrase: the take's own, unless they are only filler ("Um,").
  final String before;

  /// What followed it: the command.
  final String after;

  /// A mishearing of the keyword ("Hey, like", "Hey goes"), which counts only when a command follows.
  final bool misheard;

  @override
  bool operator ==(Object other) =>
      other is HeardKeyword && other.before == before && other.after == after && other.misheard == misheard;

  @override
  int get hashCode => Object.hash(before, after, misheard);

  @override
  String toString() => '{before: $before, after: $after, misheard: $misheard}';
}

/// The keyword in a phrase, said anywhere in it, or misheard at its very start when [reads] says a command follows.
HeardKeyword? hearKeyword(String text, bool Function(String words) reads) {
  final said = findKeyword(text);
  if (said != null) return HeardKeyword(before: said.before, after: said.after, misheard: false);
  final misheard = findMisheard(text, (after) => reads(commandWords(after)));
  return misheard != null ? HeardKeyword(before: '', after: misheard.after, misheard: true) : null;
}

final RegExp _onlyLead = RegExp(r'^\s*(?:hey|hi|ok(?:ay)?|so)[\s.,!?]*$', caseSensitive: false);

/// A phrase that is only a keyword's lead, which Whisper cut from its keyword: "Hey." | "Ghost, add…".
bool onlyLead(String text) => _onlyLead.hasMatch(text);

final RegExp _letter = RegExp(r'\p{L}', unicode: true);

/// A phrase that is only filler, said before anything ("Okay.", "Um.").
bool onlyFillerPhrase(String text) => onlyFiller(text) && _letter.hasMatch(text);

final RegExp _silence = RegExp(r'^\s*(?:thank you|thanks for watching|bye|you)[\s.!]*$', caseSensitive: false);

/// What Whisper writes for a silence: never the start of a note.
bool silenceLine(String text) => _silence.hasMatch(text);

final RegExp _leadingMarks = RegExp(r'^[\s.,;:!?…"“]+');

/// The command's words, the lead-ins gone ("like, add…", "can you add…", "I want to add…").
String commandWords(String text) {
  var words = text.replaceFirst(_leadingMarks, '');
  for (var pass = 0; pass < 3; pass += 1) {
    final before = words;
    words = words.replaceFirst(leadIns, '').trim();
    if (words == before) break;
  }
  return words;
}

final RegExp _finalStop = RegExp(r'[\s.!?…]+$');

/// A phrase-final stop taken off: never a separator, never "stopped".
String withoutFinalStop(String text) => text.replaceFirst(_finalStop, '').trim();

/// What introduced a payload ("The note is …"), taken off it.
String payloadOf(String text) => withoutPayloadLead(text).trim();

// ---- the readings -------------------------------------------------------------------------------------------------

/// What the noun said: a to-do, an item, a paragraph, or a note left where it fits (`Reading['placing']`).
enum ReadingPlacing { task, item, paragraph, leave }

/// One reading of a command's words (`Reading`).
class Reading {
  const Reading({
    required this.shape,
    required this.name,
    this.payload = '',
    this.trailing = '',
    this.tail = '',
    this.placing = ReadingPlacing.leave,
    this.heading,
    this.move = false,
    this.plainMove = false,
    this.nameFirst = false,
    this.newNote = false,
    this.self = false,
    this.stopped = false,
    this.noun = false,
    this.filed = false,
    this.split = false,
    this.verb = false,
  });

  /// Which shape of command (docs/DESIGN.md §126): the int 1 to 8, or the string `'S'`.
  final Object shape;

  /// The note's name as heard.
  final String name;

  /// What goes in it, when it was said in the same phrase; '' when it is still to come.
  final String payload;

  /// Words after the command that are the take's own again: what follows a full stop after a shape-4 name.
  final String trailing;

  /// Everything said after the verb (and a noun and preposition before the name), as said: what a name that finds no
  /// note gives back when the grammar cannot tell where it ends (live_route.dart `keptWords`).
  final String tail;

  /// What the noun said: a to-do, an item, a paragraph, or a note left where it fits.
  final ReadingPlacing placing;

  /// "…under Kitchen in Home jobs": the heading whose list the words go in.
  final String? heading;

  /// "Move this to …": the take goes there.
  final bool move;

  /// "Move this to …" or "switch this to …" as said: the move said plainly, which a phrase with no keyword must be.
  /// "Go to work", "carry on in the garage" and "move it to …" are `move` but not this: bare, they are words ("it"
  /// is a send's word, take_back.dart). Nor are "move everything to the garage" and "move these to the kitchen",
  /// which is how people talk about boxes.
  final bool plainMove;

  /// "For Groceries, …", "House TODOs: …": the name came first.
  final bool nameFirst;

  /// "New note".
  final bool newNote;

  /// "Remind me to …": for the note being written to.
  final bool self;

  /// The name ended at a separator inside the phrase, so it can grow no more.
  final bool stopped;

  /// A note or item noun was said ("a note", "a to-do"): it was plainly about a note.
  final bool noun;

  /// "Add a note to …", "put an item in …", "new item for …": a verb and a noun for filing words in a note. "Leave a
  /// note for Mum", "send a note to Sam", "drop a line to the team" and "another point for the agenda" are messages
  /// and meeting talk: with no keyword said, such a phrase is a command only when its name says it is a list
  /// ([bareEvidence]).
  final bool filed;

  /// The name ends at a split point the grammar chose, not at a separator or the phrase's end.
  final bool split;

  /// The name starts with a verb a note is never named by ("call the electrician"): a name only when it finds a
  /// title that starts with the same word, clearly (live_route.dart), and otherwise what to do.
  final bool verb;

  Reading copyWith({
    Object? shape,
    String? name,
    String? payload,
    String? trailing,
    String? tail,
    ReadingPlacing? placing,
    Object? heading = _unset,
    bool? move,
    bool? plainMove,
    bool? nameFirst,
    bool? newNote,
    bool? self,
    bool? stopped,
    bool? noun,
    bool? filed,
    bool? split,
    bool? verb,
  }) => Reading(
    shape: shape ?? this.shape,
    name: name ?? this.name,
    payload: payload ?? this.payload,
    trailing: trailing ?? this.trailing,
    tail: tail ?? this.tail,
    placing: placing ?? this.placing,
    heading: identical(heading, _unset) ? this.heading : heading as String?,
    move: move ?? this.move,
    plainMove: plainMove ?? this.plainMove,
    nameFirst: nameFirst ?? this.nameFirst,
    newNote: newNote ?? this.newNote,
    self: self ?? this.self,
    stopped: stopped ?? this.stopped,
    noun: noun ?? this.noun,
    filed: filed ?? this.filed,
    split: split ?? this.split,
    verb: verb ?? this.verb,
  );

  @override
  bool operator ==(Object other) =>
      other is Reading &&
      other.shape == shape &&
      other.name == name &&
      other.payload == payload &&
      other.trailing == trailing &&
      other.tail == tail &&
      other.placing == placing &&
      other.heading == heading &&
      other.move == move &&
      other.plainMove == plainMove &&
      other.nameFirst == nameFirst &&
      other.newNote == newNote &&
      other.self == self &&
      other.stopped == stopped &&
      other.noun == noun &&
      other.filed == filed &&
      other.split == split &&
      other.verb == verb;

  @override
  int get hashCode => Object.hash(
    shape,
    name,
    payload,
    trailing,
    tail,
    placing,
    heading,
    move,
    plainMove,
    nameFirst,
    newNote,
    self,
    stopped,
    noun,
    filed,
    split,
    verb,
  );

  @override
  String toString() =>
      '{shape: $shape, name: $name, payload: $payload, trailing: $trailing, tail: $tail, placing: ${placing.name}, '
      'heading: $heading, move: $move, plainMove: $plainMove, nameFirst: $nameFirst, newNote: $newNote, self: $self, '
      'stopped: $stopped, noun: $noun, filed: $filed, split: $split, verb: $verb}';
}

const Object _unset = Object();

const String _verb = r'(?:add|put|stick|write|jot(?:\s+down)?|append|save|file|pop|drop|leave|make|note|send)';
const String _taskNoun = r'(?:tasks?|to-?\s?dos?|todos?|reminders?)';
const String _itemNoun = r'(?:items?|entry|entries|bullets?|points?|things?|bugs?|issues?)';
const String _noteNoun = r'(?:note|line|comment|memo)';
const String _noun = '(?:(?:list\\s+)?$_itemNoun|$_taskNoun|$_noteNoun)';
const String _nounOpen = r'(?:(?:a|an|another|one\s+more|some|new)\s+)?(?:(?:quick|little|short|new)\s+)?';

/// The verbs and nouns that file words in a note (`Reading.filed`), not send a message or raise a point.
final RegExp _filingVerb = RegExp(r'^(?:add|put|stick|pop|append|save|file)\b', caseSensitive: false);
final RegExp _filingNoun = RegExp('^(?:(?:list\\s+)?(?:items?|entry|entries|bullets?|bugs?|issues?)|$_taskNoun|note)\$', caseSensitive: false);
const String _prep = r'(?:to|in|into|onto|on|for|under)';
const String _owner = r'(?:(?:the|my|our)\s+)?';
const String _label = r'(?:(?:page|note|list)\s+(?:for|called|named|titled|label(?:l)?ed)\s+)?';

/// What ends a name inside a phrase: a comma, colon, semicolon or full stop, or "that says".
final RegExp _sep = RegExp(r'\s*[,:;]\s*|\.\s+|\s+(?:that\s+says|which\s+says|that\s+reads|saying|to\s+say)\s+', caseSensitive: false);

final RegExp _shape1 = RegExp('^$_verb\\s+$_nounOpen($_noun)\\s+$_prep\\s+$_owner$_label(.+)\$', caseSensitive: false);
final RegExp _shape2 = RegExp('^(?:(?:a|an)\\s+)?(?:new|another)\\s+($_noun)\\s+(?:for|to|on|in|into)\\s+$_owner(.+)\$', caseSensitive: false);
final RegExp _shape3 = RegExp('^$_verb\\s+(?:(?:this|these|the\\s+following)\\s+)?$_prep\\s+$_owner$_label(.+)\$', caseSensitive: false);
final RegExp _shape4Verb = RegExp('^$_verb\\s+', caseSensitive: false);
final RegExp _prepSplit = RegExp('\\s+$_prep\\s+', caseSensitive: false);
final RegExp _shape5 = RegExp(
  '^(move|switch|carry\\s+on|continue|go|jump)\\s+(?:(this|it|everything|these)\\s+)?(?:over\\s+)?(?:back\\s+)?(?:to|into|onto|on|in)\\s+$_owner$_label([^,:;.]+)\$',
  caseSensitive: false,
);
final List<RegExp> _shape6 = [
  RegExp('^for\\s+$_owner([^,:;.]+?)\\s*,\\s*(.+)\$', caseSensitive: false),
  RegExp('^on\\s+$_owner([^,:;.]+?)\\s*,?\\s+(?:add|put)\\s+(.+)\$', caseSensitive: false),
  RegExp(r'^([^,:;.]{2,40}):\s*(.+)$', caseSensitive: false),
];
final RegExp _shape7 = RegExp(r'^(?:(?:a|an)\s+)?(?:new|start\s+a\s+new|another)\s+(?:notes?|node)$', caseSensitive: false);
final RegExp _shape8 = RegExp('^$_verb\\s+(?:(.+?)\\s+)?(?:under|in)\\s+$_owner(.+?)\\s+(?:in|on)\\s+$_owner(.+)\$', caseSensitive: false);
final List<({RegExp rule, bool task})> _selfRules = [
  (rule: RegExp(r'''^(?:remind\s+me\s+to|i\s+need\s+to|i\s+have\s+to|don['’]?t\s+forget\s+to)\s+(.+)$''', caseSensitive: false), task: true),
  (rule: RegExp(r'^add\s+(?:(?:a|an)\s+)?(?:to-?\s?do|todo|task)\s*[:,]\s*(.+)$', caseSensitive: false), task: true),
  (rule: RegExp(r'^add\s+(?:(?:a|an)\s+)?item\s*[:,]\s*(.+)$', caseSensitive: false), task: false),
  (rule: RegExp(r'^(?:add|put)\s+(.+?)\s+here$', caseSensitive: false), task: false),
];

/// Verbs a note is never named by, so a "name" that starts with one is what to do: "make a note to call the
/// electrician" is the to-do "Call the electrician", not a note called "call the electrician".
final RegExp _notNames = RegExp(
  r'^(?:call|fix|book|buy|get|ask|email|send|pick|make|check|clean|take|see|find|try|set|sort|look|do|go|pay|ring|text|order|tell|remember|finish|write|read)\b',
  caseSensitive: false,
);

/// A command for something other than words: a table, a board, a book or a chapter, which the live reader leaves
/// alone.
final RegExp _notWords = RegExp(
  r'^(?:(?:add|make|create|start|put|insert|draw|build|begin|new)\s+(?:(?:a|an|another|one|the)\s+)?(?:new\s+)?(?:table|board|kanban|book|chapter)s?\b|(?:make|turn|change)\s+(?:this|it|the\s+note|this\s+note|the\s+list|this\s+list)\s+(?:into\s+)?(?:a\s+)?(?:kanban\s+)?(?:board|kanban|table|book)\b)',
  caseSensitive: false,
);

/// Whether a name can be one (the web's `'name' | 'verb' | 'not'`).
enum Nameable { name, verb, not }

final RegExp _article = RegExp(r'^(?:a|an)\s', caseSensitive: false);
final RegExp _position = RegExp(r'^(?:the\s+)?(?:top|bottom|end|start|beginning|middle)\b', caseSensitive: false);

/// Whether a name can be one: not "a table", not "the top", and not a thing to do (`NOT_NAMES`).
Nameable nameable(String name) {
  final said = name.trim();
  if (_article.hasMatch(said)) return Nameable.not;
  if (_position.hasMatch(said)) return Nameable.not;
  if (_notNames.hasMatch(said)) return Nameable.verb;
  return Nameable.name;
}

/// A reading for a name alone, with nothing said for it: "Not this note" offering the others for that name.
Reading namedAs(String name) => Reading(shape: 3, name: name.trim());

final RegExp _taskNounOnly = RegExp('^$_taskNoun\$', caseSensitive: false);
final RegExp _itemNounOnly = RegExp('^(?:list\\s+)?$_itemNoun\$', caseSensitive: false);

ReadingPlacing _placingOf(String noun) {
  if (_taskNounOnly.hasMatch(noun.trim())) return ReadingPlacing.task;
  if (_itemNounOnly.hasMatch(noun.trim())) return ReadingPlacing.item;
  return ReadingPlacing.leave;
}

final RegExp _spaces = RegExp(r'\s+');

/// A name and what follows it: up to a separator when there is one (`stopped`), and otherwise the whole of it, and
/// every split of its first one to six words with the rest as the payload.
List<({String name, String payload, bool stopped, bool split})> _namesIn(String tail) {
  final sep = _sep.firstMatch(tail);
  if (sep != null && sep.start > 0) {
    return [(name: tail.substring(0, sep.start), payload: tail.substring(sep.end).trim(), stopped: true, split: false)];
  }
  final words = tail.trim().split(_spaces);
  final out = [(name: tail.trim(), payload: '', stopped: false, split: false)];
  for (var k = 1; k <= math.min(6, words.length - 1); k += 1) {
    out.add((name: words.sublist(0, k).join(' '), payload: words.sublist(k).join(' '), stopped: false, split: true));
  }
  return out;
}

/// "a list item", "a task", "a note that says" at the front of what is added: the kind of thing, not the thing.
final RegExp _thingNoun = RegExp('^$_nounOpen($_noun)(?:\\s+(?:about|that\\s+says|saying|which\\s+says|called|:|,))?\\s+', caseSensitive: false);
final RegExp _bareThing = RegExp(r'^(?:this|that|it|everything|these|those|them)$', caseSensitive: false);

/// "Add a paragraph to Groceries that says…": the kind of words, which go on the note's end, not the words.
final RegExp _paragraph = RegExp(r'^(?:(?:a|an|another|one\s+more|new)\s+)?(?:(?:new|short|quick|little)\s+)?paragraph$', caseSensitive: false);

final RegExp _instead = RegExp(r'\s+instead$', caseSensitive: false);
final RegExp _plainMover = RegExp(r'^(?:move|switch)$', caseSensitive: false);
final RegExp _ownerLead = RegExp(r'^(?:(?:the|my|our)\s+)', caseSensitive: false);
final RegExp _nameStop = RegExp(r'^([^.,;:]+?)\s*(?:\.\s+(.+)|(?:[,;:]|\s(?:that\s+says|which\s+says|that\s+reads|saying|to\s+say)\s)\s*(.+))$');
final RegExp _andMore = RegExp(r'^and\s+\S', caseSensitive: false);
final RegExp _andLead = RegExp(r'^and\s+', caseSensitive: false);

bool _truthy(String? group) => group != null && group.isNotEmpty;

String _both(String a, String b) => [a, b].where((part) => part.isNotEmpty).join(', ');

/// Every reading of a command's words (the keyword and the lead-ins already gone, [commandWords]). Empty when the
/// words are not a command for a note: "fix the spelling", "put the dates in a table", "add a summary to the top".
List<Reading> readRoute(String text) {
  // "Add it to Groceries instead": the word after the name is not the name's (a take-back's send, take_back.dart).
  final words = withoutFinalStop(text).replaceFirst(_instead, '');
  if (words.isEmpty) return [];
  // A table, a board, a book or a chapter is asked for, not words for a note: "add a table to this note" is no
  // bullet.
  if (_notWords.hasMatch(words)) return [];
  if (_shape7.hasMatch(words)) return [const Reading(shape: 7, name: '', newNote: true)];
  for (final (:rule, :task) in _selfRules) {
    final self = rule.firstMatch(words);
    if (self != null && _truthy(self.group(1))) {
      return [Reading(shape: 'S', name: '', self: true, payload: self.group(1)!.trim(), placing: task ? ReadingPlacing.task : ReadingPlacing.item)];
    }
  }
  final out = <Reading>[];
  void named(int shape, String tail, {ReadingPlacing placing = ReadingPlacing.leave, bool noun = false, bool filed = false}) {
    for (final found in _namesIn(tail)) {
      final kind = nameable(found.name);
      if (kind == Nameable.not) continue;
      // "Make a note to call the electrician": a thing to do, for the note being written to, unless a note is
      // plainly called that.
      if (kind == Nameable.verb && shape == 1 && !found.split) {
        out.add(Reading(shape: 'S', name: '', self: true, payload: _both(found.name, found.payload), placing: ReadingPlacing.task, noun: true));
      }
      out.add(
        Reading(
          shape: shape,
          name: found.name.trim(),
          placing: placing,
          noun: noun,
          filed: filed,
          payload: found.payload,
          tail: tail.trim(),
          stopped: found.stopped,
          split: found.split,
          verb: kind == Nameable.verb,
        ),
      );
    }
  }

  final one = _shape1.firstMatch(words);
  if (one != null && _truthy(one.group(1)) && _truthy(one.group(2))) {
    named(1, one.group(2)!, placing: _placingOf(one.group(1)!), noun: true, filed: _filingVerb.hasMatch(words) && _filingNoun.hasMatch(one.group(1)!.trim()));
  }
  final two = _shape2.firstMatch(words);
  if (two != null && _truthy(two.group(1)) && _truthy(two.group(2))) {
    named(2, two.group(2)!, placing: _placingOf(two.group(1)!), noun: true, filed: _filingNoun.hasMatch(two.group(1)!.trim()));
  }
  final three = _shape3.firstMatch(words);
  if (three != null && _truthy(three.group(1))) named(3, three.group(1)!);
  final eight = _shape8.firstMatch(words);
  if (eight != null && _truthy(eight.group(2)) && _truthy(eight.group(3)) && nameable(eight.group(2)!) == Nameable.name) {
    final thing = eight.group(1) ?? '';
    for (final found in _namesIn(eight.group(3)!)) {
      if (found.split || nameable(found.name) != Nameable.name) continue;
      out.add(
        Reading(
          shape: 8,
          name: found.name.trim(),
          heading: eight.group(2)!.trim(),
          payload: _bareThing.hasMatch(thing) ? found.payload : _both(thing, found.payload),
          tail: words.replaceFirst(_shape4Verb, ''),
          stopped: found.stopped,
        ),
      );
    }
  }
  final five = _shape5.firstMatch(words);
  if (five != null && _truthy(five.group(1)) && _truthy(five.group(3)) && nameable(five.group(3)!) == Nameable.name) {
    final plainMove = _plainMover.hasMatch(five.group(1)!) && five.group(2)?.toLowerCase() == 'this';
    out.add(Reading(shape: 5, name: five.group(3)!.trim(), move: true, plainMove: plainMove));
  }

  // "Add call Sam to House TODOs": at every preposition, the thing before it and the name after.
  if (_shape4Verb.hasMatch(words) && one == null && three == null) {
    final after = words.replaceFirst(_shape4Verb, '');
    for (final split in _prepSplit.allMatches(after)) {
      final thing = after.substring(0, split.start).trim();
      final tail = after.substring(split.end).replaceFirst(_ownerLead, '');
      if (thing.isEmpty || tail.isEmpty) continue;
      final spaced = '$thing ';
      final noun = _thingNoun.firstMatch(spaced);
      final paragraph = _paragraph.hasMatch(thing);
      final said = paragraph
          ? ''
          : noun != null
          ? spaced.substring(noun.group(0)!.length).trim()
          : thing;
      final placing = paragraph
          ? ReadingPlacing.paragraph
          : noun != null && _truthy(noun.group(1))
          ? _placingOf(noun.group(1)!)
          : ReadingPlacing.leave;
      // The name runs to a stop, where the take's words begin again, or to a comma, a colon or "that says", where
      // more of the thing is.
      final stop = _nameStop.firstMatch(tail);
      final name = stop != null ? stop.group(1)! : tail;
      final kind = nameable(name);
      if (kind == Nameable.not) continue;
      final payload = _bareThing.hasMatch(said) ? '' : said;
      out.add(
        Reading(
          shape: 4,
          name: name.trim(),
          payload: stop != null && _truthy(stop.group(3)) ? _both(payload, stop.group(3)!) : payload,
          trailing: stop?.group(2)?.trim() ?? '',
          tail: after,
          placing: placing,
          noun: noun != null,
          stopped: stop != null,
          verb: kind == Nameable.verb,
        ),
      );
      // "Add milk to groceries and eggs": a title, and more of the thing after it.
      final joined = stop != null ? const <String>[] : name.split(_spaces);
      for (var k = 1; k < joined.length; k += 1) {
        final rest = joined.sublist(k).join(' ');
        if (!_andMore.hasMatch(rest)) continue;
        out.add(
          Reading(
            shape: 4,
            name: joined.sublist(0, k).join(' ').trim(),
            payload: _both(payload, rest.replaceFirst(_andLead, '')),
            placing: placing,
            noun: noun != null,
            split: true,
          ),
        );
      }
    }
  }
  return out;
}

// ---- the gate a phrase passes with no keyword ---------------------------------------------------------------------

/// When, not where: "move this to Tuesday" is a meeting moved, whatever a note is called.
final RegExp _when = RegExp(
  r'^(?:(?:next|this|last)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|weekend|month|year|morning|afternoon|evening|january|february|march|april|may|june|july|august|september|october|november|december)$|^(?:today|tomorrow|tonight|later)$',
  caseSensitive: false,
);

/// The shapes a command has to have with no keyword said, or a mishearing of it, by its words alone (docs/DESIGN.md
/// §136): a note or an item said for it, the name run to a separator or the phrase's end and never to a split the
/// grammar chose ("add a note to house to-dos, call Sam"; "another item on the agenda is the budget" is meeting
/// talk); "put this in X, …" stopped at a separator; "add X to Y" and "add X under H in Y"; and "move this to X"
/// said plainly, to a note rather than a day. Never a to-do for here ("remind me to …" is prose in a voice note),
/// "new note", a name said first, a name that starts with a verb, or "go to X": "Go to work" moved a whole recording
/// once.
bool bareShape(Reading r) {
  if (r.self || r.newNote || r.verb || r.nameFirst) return false;
  if (r.shape == 1 || r.shape == 2) return r.noun && !r.split;
  if (r.shape == 3) return r.stopped;
  if (r.shape == 5) return r.plainMove && !_when.hasMatch(r.name);
  return r.shape == 4 || r.shape == 8;
}

final RegExp _shopping = RegExp(r'^(?:grocer(?:y|ie)|shopping)$');

/// Whether a name says what kind of list its note is: a kind word ("house to-dos", "the work list", "packing list")
/// or a shopping word ("groceries"). A title that says so is not enough on its own: "house" is House TODOs and
/// "garden" is Garden jobs at 0.9, and "put the washing in the house" is a sentence.
bool _saysList(String name) {
  final said = nameWords(name);
  return said.specific.length + said.generic.length > 0 || said.words.any(_shopping.hasMatch);
}

/// What a bare phrase has to show that a note was meant: for "put this in X", "add X to Y", a heading, and a note or
/// an item said with a verb that sends or raises it rather than files it (`Reading.filed`), the name says what kind
/// of list it is (`saysList`); and the heading is one the note has. "Add a note", "new item" and "move this" are
/// their own evidence. Nearly every note has one bullet, so a list in the body is no evidence: "send this to Sam,
/// the deposit is due" beside a note called Sam is a sentence, and so is "leave a note for Mum, dinner is in the
/// oven".
bool bareEvidence(Reading r, ({String title, String body}) note) {
  final filing = r.shape == 1 || r.shape == 2 ? r.filed : r.shape == 5;
  if (!filing && !_saysList(r.name)) return false;
  if (r.shape == 8) return r.heading != null && headingIn(note.body, r.heading!);
  return true;
}

/// The gate a phrase passes with no trustworthy keyword: the shape ([bareShape]), a note named clearly
/// (`find.clear`), the evidence ([bareEvidence]), and its words in the same phrase unless the take is at its start,
/// where a route may wait for them in the open, or it moves the take. A bare command with nothing said for it opened
/// a one-shot that took the next three phrases of dictation, which is why the words must come in the same breath
/// mid-take. Both readers ask this (live_route.dart `clear`, ai/instruction.ts), and the live reader's mishearing
/// path, so a mishearing means the same to each.
bool bareCommand(Reading r, ({String title, String body}) note, double score, {required bool atStart}) =>
    bareShape(r) && score >= find.clear && bareEvidence(r, note) && (atStart || r.payload != '' || r.plainMove);

/// Whether a command's words after a mishearing of the keyword ("Hey, like, …", "Hey goes …") are a command for a
/// note: the gate every bare phrase passes ([bareShape]), and the caller's [clear], which is [bareCommand] with its
/// own find. "Hey, like, I need to call my mum" and "Hey, like, put the parcel in the post" are words.
bool misheardShape(String words, bool Function(Reading reading) clear) => readRoute(words).any((r) => bareShape(r) && clear(r));

/// "For Groceries, eggs", "on the work list, add call Sam", "House TODOs: call Sam": the name said first. After the
/// keyword only.
List<Reading> readNameFirst(String text) {
  final words = withoutFinalStop(text);
  final out = <Reading>[];
  for (final rule in _shape6) {
    final found = rule.firstMatch(words);
    if (found != null && _truthy(found.group(1)) && _truthy(found.group(2)) && nameable(found.group(1)!) == Nameable.name) {
      out.add(Reading(shape: 6, name: found.group(1)!.trim(), payload: found.group(2)!.trim(), nameFirst: true, stopped: true));
    }
  }
  return out;
}

final RegExp _openerWhole = RegExp(
  '^(?:$_verb(?:\\s+$_nounOpen$_noun)?(?:\\s+(?:this|these|the\\s+following))?|(?:new|another)\\s+$_noun|move(?:\\s+this)?|switch|carry\\s+on|go|for|on)\$',
  caseSensitive: false,
);
final RegExp _openerToPrep = RegExp('^(?:$_verb|move|switch|(?:new|another)\\s+$_noun).*\\s$_prep(?:\\s+(?:the|my|our))?\$', caseSensitive: false);

/// An opener with no name yet: "add a note to", "put this in", "new item for", "move this to", "for". The live
/// reader holds it for the next phrase, where the name is.
bool isOpener(String text) {
  final words = withoutFinalStop(text);
  if (words.isEmpty) return true;
  if (_shape7.hasMatch(words)) return false;
  return _openerWhole.hasMatch(words) || _openerToPrep.hasMatch(words);
}

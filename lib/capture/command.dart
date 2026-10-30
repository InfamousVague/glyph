/// "Glyph, add buy milk to HelloTrade": the keyword, and the plan a command's words make, for the reader at Done
/// (final_instruction.dart). A port of `src/app/capture/command.ts`.
///
/// Matt, after "add a note to hello trade" became a new note called "To the hello trade" (docs/DESIGN.md §38): "have
/// it listen for keywords and not do anything until it hears the keyword and confirms the action". The keyword has
/// been optional since §136 (Matt: "Remove the function which expects hey ghost before commands"); the reader at
/// Done still reads the recording's whole transcript through [finalCommandWords], which never needed one, and a bare
/// command it cannot carry out is the note's words. So:
///
/// - "Glyph" or "hey Ghost" is heard anywhere in a phrase ([findKeyword]), or a mishearing of it followed by a
///   command ([findMisheard]). What comes before it in the phrase stays in the note.
/// - The command is read loosely ([planCommand]), since the keyword already says it is one: "add buy milk to hello
///   trade", "add a list item to HelloTrade", "put call Sam on the work list", plus every phrasing route.dart knew,
///   the note found by its words (note_find.dart).
/// - A plan read at Done is shown on a card and waits for a tap. Only two are carried out, words for a note and a new
///   list by name; the rest - a table, a book or a chapter, a board, a move, a new note - are read so that the reader
///   can turn them down rather than take them for words to add. What the live reader (live_route.dart) carries out
///   as it is said, it reads with its own grammar (live_command.dart), which shares the keyword, its mishearings and
///   the lead-ins with this.
///
/// Pure, so every phrasing is a test.
///
/// What differs: the shapes. `Plan` is a sealed class with one subclass per `kind` ([PlanPlace], [PlanAwait],
/// [PlanMove], [PlanNew], [PlanCreateList], [PlanTable], [PlanBoard], [PlanBook], [PlanChapter], [PlanNoNote]), and
/// `FinalPlan` - on the web `Extract<Plan, { kind: 'place' | 'create-list' }>` - is the sealed class between, which
/// [PlanPlace] and [PlanCreateList] extend. A place or an await carries its `Placement` fields beside its own, as on
/// the web, and gives them back whole as `placement`. `how` is a [PlacementHow]. `findKeyword`, `findMisheard` and
/// `findSoundAlike` answer a `({before, after})` record. `planCommand` takes `notes` as a named parameter, so
/// `PlanOptions` has no type of its own. `LEAD_INS` and `PAYLOAD_LEAD` are [leadIns] and [payloadLead]. A note is a
/// book when its candidate's `noteBody` (the web's `note?.body`) says so, read with `lib/core/book.dart`.
library;

import 'template_ask.dart';
import 'dart:math' as math;

import '../core/book.dart' show isBookBody;
import '../core/text.dart' show capitalise, escapeRegExp;
import 'note_find.dart' show FoundResolved, findNote, nameWords, spokenName;
import 'route.dart' show Candidate, RouteCommandItem, RouteCommandLeave, RouteCommandNew, RouteCommandNote, parseRoute;
import 'spoken/numbers.dart' show oneToTen;
import 'spoken_list.dart' show spokenListItems;

// ---- the keyword --------------------------------------------------------------------------------------------------

/// The word a command follows, and what speech recognition writes for it. "Glyph" is a rare word, so the small model
/// sometimes spells it the way it sounds, and "hey" or "OK" before it are part of the keyword but not needed.
/// "Ghost" - the app's name since it became Ghost.md - is a common word, so a note that begins "Ghost stories…" would
/// have been a command with no command in it; Matt chose "hey Ghost": the new word only counts after "hey", "hi",
/// "OK" or "so", and the old word keeps working as it always did.
final RegExp _keyword = RegExp(
  r'''(^|[\s,.;:!?"“])(?:(?:hey|hi|ok(?:ay)?|so)[,\s]+(?:ghost|ghosts|goast|gost|ghos|ghoast|ghossed|ghosed)|(?:(?:hey|hi|ok(?:ay)?|so)[,\s]+)?(?:glyph|glyphs|glyphe|glyf|glif|gliff|glyff|gliph|glyth|glith|glithe|clith|clyph|gleef|gliv|glive|glit|bliff))(?=$|[\s,.;:!?"”'])[,.;:!?"”]*\s*''',
  caseSensitive: false,
);

/// What base.en writes for "Glyph" that is a word of its own: "Life. Add eggs to my list", "Live, new note", "Head
/// life, put call Sam on the work list". Twelve synthesised voices were run through the phone's model saying
/// "Glyph, …"; half came back as one of these. They are ordinary words, so one only counts at the very start of a
/// phrase, followed by a stop or a comma, and only when what follows reads as a command ([findSoundAlike]); "We
/// climbed the cliff at dawn" and "Life is short" stay words.
///
/// Only the phrase-at-a-time reader that has gone (docs/DESIGN.md §127) used these: neither the live reader nor the
/// reader at Done does, so they are kept here, tested, until it is decided whether the live reader's mishearings
/// take them.
final RegExp _soundAlike = RegExp(
  r'^\s*(?:(?:hey|hi|ok(?:ay)?|so|a|add|head|hade|hate|take|tag)[,\s]+)?(?:life|live|lift|lip|cliff|clip|glide|slip)[,.;:!?]+\s*',
  caseSensitive: false,
);

/// What Whisper writes for "hey Ghost" and "hey Glyph" as words of their own: "Hey, like, add a note to…" (Glyph
/// heard as "like", "life" or "live"), "Hey goes add…", "Hi coast, add…" (Ghost). Matt said "hey, like add a note to
/// house to do's" and it became a note of its words. These are ordinary words, so one counts only at the very start
/// of a phrase, and only when what follows reads as a command ([findMisheard], and each reader's own guard). Not
/// "okay, like", nor "hey, go", "hey, most" or "hey, post", which are how people talk: "Okay, like, I have to say it
/// was a great run."
final RegExp _misheard = RegExp(
  r'^\s*(?:hey|hi)[,.\s]+(?:like|life|live|goes|coast|host|toast|gost)(?=$|[\s,.;:!?])[,.;:!?]*\s*',
  caseSensitive: false,
);

/// A mishearing of the keyword at the start of [text], when [reads] says the rest is a command: the same shape as
/// [findKeyword].
({String before, String after})? findMisheard(String text, bool Function(String words) reads) {
  final found = _misheard.firstMatch(text);
  if (found == null) return null;
  final after = text.substring(found.group(0)!.length).trim();
  return after.isNotEmpty && reads(after) ? (before: '', after: after) : null;
}

/// What a person says before the command itself, taken off for reading and never from the words kept: "um", "okay",
/// "like", "please", "can you", and "I want to" or "let's" when "add" or "put" follows (`LEAD_INS`).
final RegExp leadIns = RegExp(
  r'''^\s*(?:(?:um+|uh+|er+|hmm+|ok(?:ay)?|alright|all right|so|and|like|well|right|please|just|now|hey|hi)(?:[,.\s]+|$)|(?:can|could|would|will)\s+you(?:[,.\s]+|$)|(?:i\s+want\s+to|i['’]?d\s+like\s+to|i\s+need\s+to|let['’]?s|go\s+ahead\s+and)\s+(?=(?:add|put|append)\b))+''',
  caseSensitive: false,
);

final RegExp _fillerMarks = RegExp(r'[\s,.;:!?…"“]+');

/// Whether [text] is only filler, which may come before the keyword and leave it the first thing said ("Um, hey
/// Ghost").
bool onlyFiller(String text) => text.replaceAll(_fillerMarks, ' ').trim().replaceFirst(leadIns, '').trim() == '';

/// "…to the Glyph note": the word as a note's name, not the keyword. Matt has a note called Glyph, and "add a note to
/// the Glyph note saying testing if this works", said without the keyword first, took the name for the keyword: the
/// words before it became a note titled "Add a note to" and the rest was lost. A preposition before and "note" or
/// "page" after say it is a name.
final RegExp _namedBefore = RegExp(
  r'(?:^|\s)(?:to|in|into|on|onto|for|under|about|called|named|titled)\s+(?:(?:the|my|our|a)\s+)?$',
  caseSensitive: false,
);
final RegExp _namedAfter = RegExp(r'^\s*(?:notes?|pages?|list)\b', caseSensitive: false);
final RegExp _trailingSeparators = RegExp(r'[\s,;:]+$');

/// The keyword in [text]: the words before it (kept as words) and after it (the command).
({String before, String after})? findKeyword(String text) {
  for (final found in _keyword.allMatches(text)) {
    final at = found.start + (found.group(1)?.length ?? 0);
    final end = found.end;
    if (_namedBefore.hasMatch(text.substring(0, at)) && _namedAfter.hasMatch(text.substring(end))) continue;
    return (before: text.substring(0, at).replaceFirst(_trailingSeparators, '').trim(), after: text.substring(end).trim());
  }
  return null;
}

/// A sound-alike of the keyword at the start of [text] ("Life. Add eggs to work."), when [reads] says the rest is a
/// command: the same shape as [findKeyword], nothing before it.
({String before, String after})? findSoundAlike(String text, bool Function(String words) reads) {
  final found = _soundAlike.firstMatch(text);
  if (found == null) return null;
  final after = text.substring(found.group(0)!.length).trim();
  return after.isNotEmpty && reads(after) ? (before: '', after: after) : null;
}

// ---- the plan -----------------------------------------------------------------------------------------------------

/// How words go into a note: "leave", into the list it fits, or a paragraph (list_append.dart `leaveNote`); "item",
/// always a list item; "paragraph", always its own paragraph.
enum PlacementHow { leave, item, paragraph }

bool _sameItems(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// How a command's words are placed (`Placement`).
class Placement {
  const Placement({required this.how, required this.task, required this.many, this.near, this.items});

  final PlacementHow how;
  final bool task;

  /// "Items", "tasks": every phrase until a pause is one.
  final bool many;

  /// Semantic list area named explicitly by the command: `'bugs'`, or none.
  final String? near;

  /// The items already told apart ("a list with…"), so a comma inside one ("Parkersburg, West Virginia") stays in it.
  final List<String>? items;

  /// This placement with how many it places, or which, changed.
  Placement copyWith({bool? many, List<String>? items}) => Placement(how: how, task: task, many: many ?? this.many, near: near, items: items ?? this.items);

  @override
  bool operator ==(Object other) =>
      other is Placement &&
      other.how == how &&
      other.task == task &&
      other.many == many &&
      other.near == near &&
      _sameItems(other.items, items);

  @override
  int get hashCode => Object.hash(how, task, many, near, items == null ? null : Object.hashAll(items!));

  @override
  String toString() =>
      '{how: ${how.name}, task: $task, many: $many${near == null ? '' : ', near: $near'}${items == null ? '' : ', items: $items'}}';
}

/// What a command's words ask for (`Plan`).
sealed class Plan<N extends Candidate> {
  const Plan();

  /// The web's `kind`: `place`, `await`, `move`, `new`, `create-list`, `table`, `board`, `book`, `chapter` or
  /// `no-note`.
  String get kind;
}

/// The plans the reader at Done carries out, once their card is tapped: words for a note, and a new list by name
/// (`FinalPlan`).
sealed class FinalPlan<N extends Candidate> extends Plan<N> {
  const FinalPlan();
}

/// Words into a note.
final class PlanPlace<N extends Candidate> extends FinalPlan<N> {
  const PlanPlace({
    required this.note,
    required this.text,
    required this.how,
    required this.task,
    required this.many,
    this.near,
    this.items,
  });

  final N note;
  final String text;
  final PlacementHow how;
  final bool task;
  final bool many;
  final String? near;
  final List<String>? items;

  /// The placing fields alone, as the web passes the plan where a `Placement` is wanted.
  Placement get placement => Placement(how: how, task: task, many: many, near: near, items: items);

  PlanPlace<N> copyWith({String? text}) =>
      PlanPlace<N>(note: note, text: text ?? this.text, how: how, task: task, many: many, near: near, items: items);

  @override
  String get kind => 'place';

  @override
  bool operator ==(Object other) =>
      other is PlanPlace && other.note == note && other.text == text && other.placement == placement;

  @override
  int get hashCode => Object.hash(kind, note, text, placement);

  @override
  String toString() => '{kind: place, note: $note, text: $text, placement: $placement}';
}

/// A note named, but not yet what goes in it: the next phrase is that.
final class PlanAwait<N extends Candidate> extends Plan<N> {
  const PlanAwait({required this.note, required this.how, required this.task, required this.many, this.near, this.items});

  final N note;
  final PlacementHow how;
  final bool task;
  final bool many;
  final String? near;
  final List<String>? items;

  /// The placing fields alone.
  Placement get placement => Placement(how: how, task: task, many: many, near: near, items: items);

  @override
  String get kind => 'await';

  @override
  bool operator ==(Object other) => other is PlanAwait && other.note == note && other.placement == placement;

  @override
  int get hashCode => Object.hash(kind, note, placement);

  @override
  String toString() => '{kind: await, note: $note, placement: $placement}';
}

/// This take's words move to a note and carry on there.
final class PlanMove<N extends Candidate> extends Plan<N> {
  const PlanMove({required this.note});

  final N note;

  @override
  String get kind => 'move';

  @override
  bool operator ==(Object other) => other is PlanMove && other.note == note;

  @override
  int get hashCode => Object.hash(kind, note);

  @override
  String toString() => '{kind: move, note: $note}';
}

/// This take becomes a new note.
final class PlanNew<N extends Candidate> extends Plan<N> {
  const PlanNew();

  @override
  String get kind => 'new';

  @override
  bool operator ==(Object other) => other is PlanNew;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => '{kind: new}';
}

/// A standalone Speak request creates a separately titled list note, with the items said for it.
final class PlanCreateList<N extends Candidate> extends FinalPlan<N> {
  const PlanCreateList({required this.title, this.items});

  final String title;
  final List<String>? items;

  @override
  String get kind => 'create-list';

  @override
  bool operator ==(Object other) => other is PlanCreateList && other.title == title && _sameItems(other.items, items);

  @override
  int get hashCode => Object.hash(kind, title, items == null ? null : Object.hashAll(items!));

  @override
  String toString() => '{kind: create-list, title: $title${items == null ? '' : ', items: $items'}}';
}

/// A new note with words in it, by name ("make a note called directions and put go north"), from a finished
/// recording (`create-note`; on the web `FinalPlan` has it beside `Plan`'s). [body] is the words as sentences, or ''
/// for a note with a title alone.
final class PlanCreateNote<N extends Candidate> extends FinalPlan<N> {
  const PlanCreateNote({required this.title, required this.body, this.template, this.place});

  final String title;
  final String body;

  /// A template said for it, by a word of its name, and the notebook or folder it goes in ("new bug in Kiln";
  /// template_ask.dart): the root makes it from that template there.
  final String? template;
  final String? place;

  @override
  String get kind => 'create-note';

  @override
  bool operator ==(Object other) => other is PlanCreateNote && other.title == title && other.body == body && other.template == template && other.place == place;

  @override
  int get hashCode => Object.hash(kind, title, body, template, place);

  @override
  String toString() => '{kind: create-note, title: $title, body: $body${template == null ? '' : ', template: $template, in: $place'}}';
}

/// A table asked for, in a named note or this one: read so the reader at Done can turn it down, since a recording
/// makes none.
final class PlanTable<N extends Candidate> extends Plan<N> {
  const PlanTable({required this.note, required this.columns});

  final N? note;
  final List<String> columns;

  @override
  String get kind => 'table';

  @override
  bool operator ==(Object other) => other is PlanTable && other.note == note && _sameItems(other.columns, columns);

  @override
  int get hashCode => Object.hash(kind, note, Object.hashAll(columns));

  @override
  String toString() => '{kind: table, note: $note, columns: $columns}';
}

/// "Glyph, make this a board": read so the reader at Done can turn it down (a board is made with More > Make a
/// board).
final class PlanBoard<N extends Candidate> extends Plan<N> {
  const PlanBoard();

  @override
  String get kind => 'board';

  @override
  bool operator ==(Object other) => other is PlanBoard;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => '{kind: board}';
}

/// "Make a book called Field guide with Trees, Birds and Rivers": a book note, its pages the notes named or chapters
/// still to write (docs/BOOKS.md).
final class PlanBook<N extends Candidate> extends Plan<N> {
  const PlanBook({required this.title, required this.pages});

  final String title;
  final List<String> pages;

  @override
  String get kind => 'book';

  @override
  bool operator ==(Object other) => other is PlanBook && other.title == title && _sameItems(other.pages, pages);

  @override
  int get hashCode => Object.hash(kind, title, Object.hashAll(pages));

  @override
  String toString() => '{kind: book, title: $title, pages: $pages}';
}

/// A chapter for a book: "add a chapter called Trees to the field guide". [title] null is this note: "put this in the
/// field guide".
final class PlanChapter<N extends Candidate> extends Plan<N> {
  const PlanChapter({required this.note, required this.title});

  final N note;
  final String? title;

  @override
  String get kind => 'chapter';

  @override
  bool operator ==(Object other) => other is PlanChapter && other.note == note && other.title == title;

  @override
  int get hashCode => Object.hash(kind, note, title);

  @override
  String toString() => '{kind: chapter, note: $note, title: $title}';
}

/// A note was named that there is no note for.
final class PlanNoNote<N extends Candidate> extends Plan<N> {
  const PlanNoNote({required this.name});

  final String name;

  @override
  String get kind => 'no-note';

  @override
  bool operator ==(Object other) => other is PlanNoNote && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => '{kind: no-note, name: $name}';
}

final RegExp _lead = RegExp(r'^\s*(?:(?:please|can you|could you|would you|and|so|ok(?:ay)?|um+|uh+)[,\s]+)+', caseSensitive: false);
final RegExp _movers = RegExp(r'^\s*(?:switch|go|jump|change|move|carry on|continue)\b', caseSensitive: false);

/// "a list item", "a task", "a note that says" at the front of what is being added: the kind of thing, not the
/// thing. The noun ends at a word's end, so "a notebook" is not "a note" and the word "book" (docs/DESIGN.md §142),
/// and "a bugfix for login" is not "a bug" and "fix for login".
final RegExp _objectNoun = RegExp(
  r'^(?:(?:a|an|another|one more|some|new)\s+)?(?:quick\s+)?(?:(list\s+)?(items?|entry|entries|bullets?|points?)|(tasks?|to-?\s?dos?|check\s?box(?:es)?)|(notes?|lines?|reminders?|comments?|memos?)|(bugs?|issues?|defects?))\b(?:\s+(?:about|that\s+says|saying|which\s+says|called|:|,))?\s*',
  caseSensitive: false,
);

final RegExp _table = RegExp(
  r'^(?:add|make|create|start|put|insert|draw|build|new)\s+(?:(?:a|an|another|one)\s+)?(?:new\s+)?table\b(.*)$',
  caseSensitive: false,
);
final RegExp _createList = RegExp(
  r'^(?:(?:please\s+)?(?:make|create|start)\s+(?:(?:me\s+)?(?:a|another)\s+)?(?:new\s+)?list|(?:i\s+(?:need|want|would\s+like))\s+(?:a\s+)?new\s+list)\s+(?:called|named|titled)[?.,:]*\s+(.+)$',
  caseSensitive: false,
);
final RegExp _createNote = RegExp(
  r'^(?:(?:please\s+)?(?:make|create|start)\s+(?:(?:me\s+)?(?:a|another)\s+)?(?:new\s+)?note|(?:i\s+(?:need|want|would\s+like))\s+(?:a\s+)?new\s+note)\s+(?:called|named|titled|label(?:ed|led)(?:\s+of)?)[?.,:]*\s+(.+)$',
  caseSensitive: false,
);
final RegExp _addToList = RegExp(
  r'^(?:please\s+)?(?:add|put|append)\s+(?:these\s+)?(?:items?\s+)?(?:to|in|into|on)\s+(?:the\s+)?(.+?)\s+list(?:\s+(?:that\s+)?(?:i\s+(?:need|want)|with|containing|:))?\s+(.+)$',
  caseSensitive: false,
);
final RegExp _directAppend = RegExp(
  r"^(?:please\s+)?(?:add|put|append)\s+(?:(?:this|these|the\s+following)\s+)?to\s+(?:(?:the|my|our)\s+)?(?:(?:note|list|page)\s+(?:that(?:'s|\s+is)\s+)?(?:label(?:ed|led)|called|named|titled|of)\s+|note\s+)?(.+)$",
  caseSensitive: false,
);

/// What is added, when it says it is a list: "a list with…", "a to-do list of…", "the following items:", "these
/// tasks…". The words after it are the items, told apart by `spokenListItems`.
final RegExp _listIntro = RegExp(
  r'^(?:(?:a|an|the|this|my)\s+)?(?:(?:new|short|quick)\s+)?(?:(?:bullet(?:ed)?|bulleted|numbered|check(?:ed)?|(to-?\s?do|task|check)|shopping|grocery)\s+)?(?:list|items?|(tasks?|to-?\s?dos?|check\s?list))\s*(?:(?:of|with|containing|including|that\s+(?:has|says|includes)|saying|for)\b|:|,|-)\s*|^(?:the\s+following(?:\s+(?:items?|things|places|(tasks?|to-?\s?dos?)))?|(?:these|those)\s+(?:items?|things|places|(tasks?|to-?\s?dos?)))\s*(?::|,|-)?\s*',
  caseSensitive: false,
);

/// "…and add to the list", "…then put", ", add these": where a new list's title ends and its items begin.
final RegExp _thenAdd = RegExp(
  r'(?:\s*[,.;:?!]\s*|\s+)(?:(?:and|then|and\s+then)\s+)?(?:(?:on|to|in)\s+(?:the|that|this|my)\s+(?:new\s+)?(?:list|note)\s*[,.;:]?\s*)?(?:add|put)\b[\s,.;:]*',
  caseSensitive: false,
);

/// "…with", "…containing", "…:": the same, when what follows is plainly several items.
final RegExp _withItems = RegExp(r'\s+(?:with|containing|including|that\s+has|of)\s+|\s*:\s*', caseSensitive: false);
const String _theList = r'(?:(?:the|that|this|my)\s+)?(?:new\s+)?(?:list|note|it)';
final RegExp _intoListFirst = RegExp('^(?:to|in|on|into|onto)\\s+$_theList\\b\\s*[,:]?\\s*', caseSensitive: false);

/// "…peanut butter. Add to list.": a closing "add to the list" is a repeated request, not another item.
final RegExp _intoListLast = RegExp(
  r'[\s,.;:?!]+(?:(?:and|then)\s+)?(?:(?:add|put)(?:\s+(?:it|them|these|those))?\s+)?(?:to|in|on|into|onto)\s+' + _theList + r'[\s.!?]*$',
  caseSensitive: false,
);

/// "…and in the note, make a list called. Can you make the list have prep, cook": a list made inside the note just
/// named.
final RegExp _inTheNote = RegExp(
  r'^(.*?)[\s,.;:]+(?:(?:and|then)\s+)*(?:in|inside|into)\s+(?:the|that|this)\s+(?:new\s+)?note[\s,.;:]+(?:(?:and|then|can\s+you|please)[\s,]+)*(?:make|create|put|add|start)\s+(?:(?:me\s+)?(?:a|another)\s+)?(?:new\s+)?(?:list|checklist)\b[\s,.;:?]*(?:(?:called|named|titled)[\s?.,:]*)?(?:(?:(?:and|then|can\s+you|please)[\s,]+)*(?:make|have)\s+(?:the|that|it|this)\s+(?:list\s+)?(?:have|with|contain|include)\s+)?(.*)$',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _these = RegExp(r'^(?:(?:these|the\s+following)(?:\s+(?:items?|things))?|items?)\s*[,:]?\s+', caseSensitive: false);

/// "Comic books and add to the list Spider-Man, Batman and Superman": the new list's title, and its items when some
/// were said. A title that merely contains "with" ("Books with pictures") stays a title: only several items split it.
({String title, List<String> items, String? rest}) _titleAndItems(String said) {
  final added = _thenAdd.firstMatch(said);
  if (added != null && added.start > 0) {
    final title = _cleanTitle(said.substring(0, added.start));
    // "Add to the games list. Zelda…": the list is named again, and the name is not an item.
    final named = RegExp(
      r'^(?:to|in|on|into|onto)\s+(?:(?:the|that|this|my)\s+)?(?:new\s+)?(?:(?:' +
          title.split(_spaces).map(escapeRegExp).join(r'\s+') +
          r')\b\s*(?:(?:list|note|it)\b)?|(?:list|note|it)\b)[\s,.;:?!]*',
      caseSensitive: false,
    );
    final rest = said
        .substring(added.end)
        .replaceFirst(named, '')
        .replaceFirst(_intoListFirst, '')
        .replaceFirst(_intoListLast, '')
        .replaceFirst(_these, '')
        .trim();
    final items = spokenListItems(rest);
    if (title.isNotEmpty && items.isNotEmpty) return (title: title, items: items, rest: rest);
  }
  final listed = _withItems.firstMatch(said);
  if (listed != null && listed.start > 0) {
    final items = spokenListItems(said.substring(listed.end).replaceFirst(_these, ''));
    if (items.length > 1) return (title: _cleanTitle(said.substring(0, listed.start)), items: items, rest: null);
  }
  // Whisper ends a name said before the note's words with a question mark or a full stop ("called stream ideas? I want
  // to stream…"): the name is the sentence it ends, and the rest is the note's. A full stop only counts after a word
  // of four letters or more, so "Mr. Smith's trip" stays whole.
  final named = _nameThenWords.firstMatch(said);
  if (named != null) {
    final title = _cleanTitle(named.group(1)!);
    final rest = named.group(2)!.trim();
    if (title.isNotEmpty && title.split(_spaces).length <= 6 && rest.isNotEmpty) return (title: title, items: const [], rest: rest);
  }
  return (title: _cleanTitle(said), items: const [], rest: null);
}

final RegExp _nameThenWords = RegExp(r'^(.+?(?:[?!]|(?<=\p{L}{4})\.))\s+(\S.*)$', unicode: true, dotAll: true);
final RegExp _pauses = RegExp(r'(?:\s*[.!?]+){2,}');
final RegExp _runOfSpaces = RegExp(r'\s+');
final RegExp _leadingJunk = RegExp(r'^[\s,.;:]+');
final RegExp _trailingJunk = RegExp(r'[\s,;:]+$');
final RegExp _endsSentence = RegExp(r'[.!?]$');

/// "We go north. . Then east" as the words of a note: pauses are not sentence ends.
String _sentences(String text) {
  final clean = text.replaceAll(_pauses, '.').replaceAll(_runOfSpaces, ' ').replaceFirst(_leadingJunk, '').replaceFirst(_trailingJunk, '');
  return clean.isEmpty ? '' : '${clean[0].toUpperCase()}${clean.substring(1)}${_endsSentence.hasMatch(clean) ? '' : '.'}';
}

/// "We should…", "it was…": a piece that starts like a sentence is not an item.
final RegExp sentenceStart = RegExp(
  r"^(?:i|i'm|we|we're|you|he|she|it|it's|they|this|that|there|so|if|when|because|after|before|with)\b",
  caseSensitive: false,
);

final RegExp _titleTail = RegExp(r'[\s.,;:!?]+$');

/// Whisper's punctuation is not part of a name: "games?" is Games.
String _cleanTitle(String title) => title.trim().replaceFirst(_titleTail, '').trim();

bool _truthy(String? group) => group != null && group.isNotEmpty;

/// A named note's words, as a list when they say they are one.
({String text, PlacementHow how, bool task, bool many, List<String>? items}) _directPayload(String text) {
  final intro = _listIntro.firstMatch(text);
  final rest = intro != null ? text.substring(intro.group(0)!.length).trim() : '';
  if (intro == null || rest.isEmpty) return (text: text, how: PlacementHow.leave, task: false, many: false, items: null);
  final items = spokenListItems(rest);
  final task = _truthy(intro.group(1)) || _truthy(intro.group(2)) || _truthy(intro.group(3)) || _truthy(intro.group(4));
  return (text: items.join(', '), how: PlacementHow.item, task: task, many: items.length > 1, items: items);
}

final RegExp _stopCue = RegExp(r'(?:[.!?]\s*)?\b(?:end|stop)\s*[.!?]*\s*$', caseSensitive: false);

/// [text] without an "end" or "stop" said last: a stop cue is the recording's control, never the command's words.
String _stripStopCue(String text) => text.replaceFirst(_stopCue, '').trim();

/// [_stripStopCue], for the scan of a whole recording for a command (command_scan.dart).
String stripStopCue(String text) => _stripStopCue(text);

final RegExp _leadingMarks = RegExp(r'^[\s.,;:!?…"“]+');

/// The command in a finished recording, or null when it is not one: what is left once a leading "hey Ghost", "okay",
/// "um" or "can you" is gone, if that starts like a command. Only the very start counts, so a command said inside a
/// sentence ("I told Sam, add to…") stays words.
String? finalCommandWords(String text) {
  var words = _stripStopCue(text.trim()).replaceFirst(_leadingMarks, '');
  var keyed = false;
  for (var pass = 0; pass < 3; pass += 1) {
    final before = words;
    final keyword = findKeyword(words) ?? findMisheard(words, (after) => isStandaloneCommandLike(after.replaceFirst(leadIns, '')));
    if (keyword != null && onlyFiller(keyword.before)) {
      words = keyword.after;
      keyed = true;
    }
    // After the keyword, what a person says before a command goes too ("like, add…", "I want to add…"); without it,
    // only the words that never start a sentence of their own, so "Just put the parcel in the post" stays one.
    words = words.replaceFirst(keyed ? leadIns : _plainLead, '').trim();
    if (words == before) break;
  }
  return isStandaloneCommandLike(words) ? words : null;
}

/// What comes before a command said without the keyword that is not the command: "okay", "um", "can you".
final RegExp _plainLead = RegExp(
  r'^\s*(?:(?:hey|hi|please|can you|could you|would you|will you|and|so|ok(?:ay)?|alright|all right|um+|uh+|er+|hmm+)[,.\s]+)+',
  caseSensitive: false,
);

final RegExp _standalone = RegExp(
  r'^(?:please\s+)?(?:make|create|new|add|put|append|i\s+(?:need|want|would\s+like)\s+(?:a\s+)?new)\b',
  caseSensitive: false,
);

/// Narrow gate for no-wake commands in a fresh main Speak capture.
bool isStandaloneCommandLike(String text) => _standalone.hasMatch(_stripStopCue(text));

final RegExp _iNeed = RegExp(r'^(?:that\s+)?i\s+(?:need|want)\s+', caseSensitive: false);
final RegExp _stopsAtEnd = RegExp(r'[.!?]+$');
final RegExp _itemBreak = RegExp(r'\s*(?:,|;|\band\b)\s*', caseSensitive: false);
final RegExp _spaces = RegExp(r'\s+');
final RegExp _bareWord = RegExp(r"^[\p{L}\p{N}'-]+$", unicode: true);

/// Split only unmistakable short enumerations; preserve ordinary phrases.
List<String> _splitSpokenItems(String text, [bool allowBareWords = false]) {
  final cleaned = text.trim().replaceFirst(_iNeed, '').replaceFirst(_stopsAtEnd, '').trim();
  final punctuated = cleaned.split(_itemBreak).where((part) => part.isNotEmpty).toList();
  if (punctuated.length > 1) return punctuated;
  final words = cleaned.split(_spaces).where((word) => word.isNotEmpty).toList();
  return allowBareWords && words.length >= 2 && words.length <= 8 && words.every(_bareWord.hasMatch) ? words : [cleaned];
}

/// "…with columns bug, owner and status": the labels said with a table, read as its shape is (`TABLE`).
final RegExp _tableColumns = RegExp(
  r'\s*,?\s*(?:with|using|that has|having)\s+(?:the\s+)?(?:columns?|column labels?|headings?|headers?|labels?)\s*(?:of|:|,)?\s*(.+)$',
  caseSensitive: false,
);

/// Words that name a column or row position, said before a cell: "column one, bug".
final RegExp _position = RegExp(
  '^(?:(?:column|row|cell)\\s+(?:\\d+|$oneToTen)|first|second|third|fourth|fifth|next|then|last)[,:\\s]+',
  caseSensitive: false,
);

/// A position said with nothing after it ("column two"): no cell at all.
final RegExp _positionAlone = RegExp('^(?:column|row)\\s+(?:\\d+|$oneToTen)\$', caseSensitive: false);

final RegExp _leadingStops = RegExp(r'^[\s.,;:!?]+');
final RegExp _stopThenSpace = RegExp(r'\.\s+');
final RegExp _commaOrSemicolon = RegExp(r'[,;]');
final RegExp _commaBreak = RegExp(r'\s*[,;]\s*');
final RegExp _andBreak = RegExp(r'\s+and\s+', caseSensitive: false);
final RegExp _andThen = RegExp(r'^(?:and|then)\s+', caseSensitive: false);

/// What was said, as cells: a table's column labels, or a book's pages. People say them the way they say a list, so
/// commas (or semicolons) split it, with "and" before the last one; with no commas, "and" alone does. "Column one,
/// bug, column two, owner" keeps only the cells.
List<String> cellsOf(String text) {
  // Whisper often writes the pauses between cells as full stops: "Item. Where. Packed."
  final said = text.trim().replaceFirst(_leadingStops, '').replaceFirst(_stopsAtEnd, '').replaceAll(_stopThenSpace, ', ').trim();
  if (said.isEmpty) return [];
  // "Bug, owner and status": the last of a comma list carries the "and".
  final List<String> parts;
  if (_commaOrSemicolon.hasMatch(said)) {
    final all = said.split(_commaBreak);
    parts = [
      for (var i = 0; i < all.length; i += 1)
        if (i == all.length - 1) ...all[i].split(_andBreak) else all[i],
    ];
  } else {
    parts = said.split(_andBreak);
  }
  return [
    for (final raw in parts)
      if (raw.replaceFirst(_andThen, '').replaceFirst(_position, '').trim() case final part
          when part.isNotEmpty && !_positionAlone.hasMatch(part))
        capitalise(part),
  ];
}

/// A preposition that can end what is added and start the note's name.
final RegExp _into = RegExp(r'(?:^|\s+)(?:to|in|into|onto|on|under|for)\s+', caseSensitive: false);

final RegExp _node = RegExp(r'\s+node$', caseSensitive: false);

/// The note a spoken name means, when one clearly does (note_find.dart): "the house list" and "house chores" are
/// House TODOs. Only a resolved note counts here; a name that is unsure, or means the note being written to, is no
/// note.
({N note, double score})? _noteNamed<N extends Candidate>(String raw, List<N> notes) {
  // "Node" is how base.en writes "note" said quickly.
  final name = spokenName(raw).replaceFirst(_node, '').trim();
  if (name.length < 2) return null;
  final found = findNote<N>(name, notes);
  return found is FoundResolved<N> ? (note: found.note, score: found.score) : null;
}

final RegExp _notLetters = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Match an actual title at the start of a spoken tail, case/punctuation-insensitively.
({N note, String text})? _titledPrefix<N extends Candidate>(String tail, List<N> notes) {
  final found = <({N note, String text})>[];
  for (final note in notes) {
    final words = note.title.trim().replaceAll(_notLetters, ' ').trim().split(_spaces).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) continue;
    final pattern = words.map(escapeRegExp).join(r'[\s\p{P}_]+');
    final match = RegExp('^\\s*$pattern(?:[\\s\\p{P}_]+)(.+)\$', caseSensitive: false, unicode: true).firstMatch(tail);
    final text = match?.group(1)?.trim() ?? '';
    if (text.isNotEmpty) found.add((note: note, text: text));
  }
  return found.length == 1 ? found.first : null;
}

final RegExp _nameThenStop = RegExp(r'^([^,:;]+?)\s*[,:;]\s*(.+)$');

/// A spoken name at the start of a tail, found as any name is (note_find.dart), and what follows it: up to a comma,
/// colon or semicolon when there is one ("add to house to-dos, call an electrician"), otherwise the first few words
/// that name a note clearly, the best of them ("add to house to-dos call an electrician").
({N note, String text})? _namedPrefix<N extends Candidate>(String tail, List<N> notes) {
  final stop = _nameThenStop.firstMatch(tail);
  if (stop != null && _truthy(stop.group(1)) && (stop.group(2)?.trim() ?? '').isNotEmpty) {
    final found = _noteNamed(stop.group(1)!, notes);
    return found != null ? (note: found.note, text: stop.group(2)!.trim()) : null;
  }
  final words = tail.trim().split(_spaces);
  // The whole tail a name as good as any part of it: it is the name ("add this to the field guide"), with nothing
  // after.
  final whole = _noteNamed(tail, notes);
  ({N note, double score, String text})? best;
  for (var k = 1; k <= math.min(6, words.length - 1); k += 1) {
    final found = _noteNamed(words.sublist(0, k).join(' '), notes);
    // A kind word that scores the same belongs to the name: "house chores", not "house" and then "chores call…".
    final kind = nameWords(words[k - 1]).distinctive.isEmpty;
    if (found != null && (best == null || found.score > best.score || (found.score == best.score && kind))) {
      best = (note: found.note, score: found.score, text: words.sublist(k).join(' '));
    }
  }
  return best != null && (whole == null || best.score > whole.score) ? (note: best.note, text: best.text) : null;
}

final RegExp _pluralTask = RegExp(r's$|es$', caseSensitive: false);
final RegExp _pluralItem = RegExp(r's$|ies$', caseSensitive: false);

Placement _placementOf(RegExpMatch? noun) {
  final task = noun?.group(3);
  if (_truthy(task)) return Placement(how: PlacementHow.item, task: true, many: _pluralTask.hasMatch(task!));
  // Group 2 is "items"/"bullets", group 5 is "bugs"/"issues": both are list items. A bug request also carries its
  // semantic area to list placement.
  final bug = noun?.group(5);
  if (_truthy(bug)) return Placement(how: PlacementHow.item, task: false, many: _pluralItem.hasMatch(bug!), near: 'bugs');
  final item = noun?.group(2);
  if (_truthy(item)) return Placement(how: PlacementHow.item, task: false, many: _pluralItem.hasMatch(item!));
  return const Placement(how: PlacementHow.leave, task: false, many: false);
}

PlanPlace<N> _place<N extends Candidate>(N note, String text, Placement placement) => PlanPlace<N>(
  note: note,
  text: text,
  how: placement.how,
  task: placement.task,
  many: placement.many,
  near: placement.near,
  items: placement.items,
);

PlanAwait<N> _await<N extends Candidate>(N note, Placement placement) => PlanAwait<N>(
  note: note,
  how: placement.how,
  task: placement.task,
  many: placement.many,
  near: placement.near,
  items: placement.items,
);

final RegExp _quoteCue = RegExp(r'\bquote\s+(.+?)\s+quote\b', caseSensitive: false);
final RegExp _trailingMarks = RegExp(r'[\s.,;:!?]+$');

final RegExp _itemEnd = RegExp(r'\s*(?:[.!?;,]+|\band\b)\s*', caseSensitive: false);
final RegExp _addLead = RegExp(r'^(?:(?:and|then|also)\s+)?(?:add|put)\s+', caseSensitive: false);
final RegExp _separatedRest = RegExp(r'[,;.]|\band\b', caseSensitive: false);
final RegExp _restEnd = RegExp(r'[\s.!?]+$');

/// What a finished recording asks for: [planCommand], and a new note made with its text ("make a note called
/// directions and put go north") (`planFinalCommand`). A [PlanCreateNote] is the one plan this answers that
/// [planCommand] never does.
Plan<N>? planFinalCommand<N extends Candidate>(String words, {required List<N> notes}) {
  // "New bug in Kiln": a note from a template, in a notebook or a folder (template_ask.dart).
  final asked = templateAsk(_stripStopCue(words.replaceFirst(_lead, '').trim()));
  if (asked != null) return PlanCreateNote<N>(title: asked.title ?? '', body: '', template: asked.template, place: asked.place);
  final said = _createNote.firstMatch(_stripStopCue(words.replaceFirst(_lead, '').trim()))?.group(1);
  if (said != null && said.isNotEmpty) {
    final inside = _inTheNote.firstMatch(said.replaceFirst(_stopsAtEnd, '').trim());
    if (inside != null) {
      // Said slowly, the items arrive as sentences ("Prep the vegetables, cook the meat. Sauté. Add cheese"): every
      // pause and comma is an item end.
      final items = [
        for (final item in (inside.group(2) ?? '').replaceFirst(_intoListLast, '').split(_itemEnd)) item.replaceFirst(_addLead, '').trim(),
      ].where((item) => item.isNotEmpty).toList();
      final title = _cleanTitle(inside.group(1) ?? '');
      if (title.isNotEmpty) return items.isNotEmpty ? PlanCreateList<N>(title: title, items: items) : PlanCreateNote<N>(title: title, body: '');
    }
    final made = _titleAndItems(said.replaceFirst(_stopsAtEnd, '').trim());
    if (made.title.isEmpty) return null;
    final rest = made.rest;
    // Several short things, said with commas, "and" or pauses ("add magnesium, aluminum and copper"), are a list; a
    // sentence or a run of words is the note's text.
    final separated = rest != null && _separatedRest.hasMatch(rest.replaceFirst(_restEnd, ''));
    final short = separated && made.items.length > 1 && made.items.every((item) => item.split(_spaces).length <= 4 && !sentenceStart.hasMatch(item));
    if (short) return PlanCreateList<N>(title: made.title, items: made.items);
    return PlanCreateNote<N>(title: made.title, body: rest != null && rest.isNotEmpty ? _sentences(rest) : '');
  }
  return planCommand<N>(words, notes: notes);
}

/// What the words after the keyword ask for, or null when they don't say yet. [notes] are the notes that can be
/// named.
Plan<N>? planCommand<N extends Candidate>(String words, {required List<N> notes}) {
  final plan = _readCommand<N>(words, notes);
  // What is added is words, not the end of a spoken sentence, and not how it was introduced ("The note is …").
  // Spoken quote cues are user punctuation, not literal command prose.
  return plan is PlanPlace<N>
      ? plan.copyWith(
          text: withoutPayloadLead(plan.text).replaceAllMapped(_quoteCue, (m) => '"${m.group(1)}"').replaceFirst(_trailingMarks, ''),
        )
      : plan;
}

/// How a person introduces what a note should say, which is not what it says: "The note is call an electrician", "it
/// says…", "the item is…". Matt's "add a note to house to do's, the note is call an electrician to fix the light
/// sockets" put "The note is" in the list (`PAYLOAD_LEAD`).
final RegExp payloadLead = RegExp(
  r'^\s*(?:(?:and\s+)?(?:the|my|this)\s+(?:note|item|task|to-?\s?do|reminder|line|entry)\s+(?:is|says|reads|should\s+say|will\s+say)|it\s+says|that\s+says|which\s+says|saying|to\s+say)(?:\s*[:,-]\s*|\s+)(?=\S)',
  caseSensitive: false,
);

/// [text] without the words that introduced it ([payloadLead]).
String withoutPayloadLead(String text) => text.replaceFirst(payloadLead, '');

/// "Make this a board", "turn the list into a kanban board".
final RegExp _makeBoard = RegExp(
  r'^(?:make|turn|change)\s+(?:this|it|this\s+note|the\s+note|this\s+list|the\s+list)\s+(?:into\s+)?(?:a\s+)?(?:kanban\s+)?(?:board|kanban)[.!]?$',
  caseSensitive: false,
);

/// "Make a book called Field guide", "new book, Trip". Not "add a book to…": that is a book for a list.
final RegExp _makeBook = RegExp(r'^(?:make|create|start|begin|new)\s+(?:(?:a|an|another|one|the)\s+)?(?:new\s+)?book\b(.*)$', caseSensitive: false);

/// "…with Trees, Birds and Rivers" after the name: its pages.
final RegExp _bookPages = RegExp(
  r'\s*,?\s*(?:with|holding|containing|out of)\s+(?:the\s+)?(?:notes?|pages?|chapters?)?\s*(?:of|:|,)?\s*(.+)$',
  caseSensitive: false,
);

/// "a chapter called", "the page named": the kind of thing a book gets, not the thing.
final RegExp _chapterNoun = RegExp(
  r'^(?:(?:a|an|another|one more|new|the)\s+)?(?:new\s+)?(?:chapters?|pages?|sections?|parts?)(?:\s+(?:called|named|titled|that says|saying|for|:|,))?\s*',
  caseSensitive: false,
);

/// The note being recorded, named as the thing: "add this to the field guide".
final RegExp _self = RegExp(
  r'^(?:this|that|it|this note|that note|the note|this one|this page|these|those|them|everything)$',
  caseSensitive: false,
);

/// A note that is a book (core/book.dart): what is added "to" it is a chapter, not words.
bool _isBook(Candidate named) {
  final body = named.noteBody;
  return body != null && isBookBody(body);
}

final RegExp _edgeQuotes = RegExp('^["“]|["”]\$');

/// What "add … to a book" adds: a chapter with that title ("a chapter called Trees", "Trees"), this note when that
/// is what was said ("add this to the field guide"), or nothing yet, and then the next phrase names it.
Plan<N> _chapterFor<N extends Candidate>(N note, String words) {
  final said = words.replaceFirst(_trailingMarks, '').trim();
  if (_self.hasMatch(said)) return PlanChapter<N>(note: note, title: null);
  final title = said.replaceFirst(_chapterNoun, '').replaceAll(_edgeQuotes, '').trim();
  return title.isNotEmpty
      ? PlanChapter<N>(note: note, title: capitalise(title))
      : PlanAwait<N>(note: note, how: PlacementHow.leave, task: false, many: false);
}

/// A plan read for a book (docs/BOOKS.md): words placed in it are a chapter, and moving this recording there makes
/// this note one. Every plan the rules make goes through it, so "add Trees to the field guide" is a chapter, which
/// the reader at Done turns down, and never words for the book's index.
Plan<N> forBook<N extends Candidate>(Plan<N> plan) {
  if (plan is PlanPlace<N> && _isBook(plan.note)) return _chapterFor<N>(plan.note, plan.text);
  if (plan is PlanMove<N> && _isBook(plan.note)) return PlanChapter<N>(note: plan.note, title: null);
  return plan;
}

Plan<N>? _readCommand<N extends Candidate>(String words, List<N> notes) {
  final plan = _readWords<N>(words, notes);
  return plan != null ? forBook<N>(plan) : null;
}

final RegExp _quotedName = RegExp(r'^["“]([^"”]+)["”]\s*(.*)$');
final RegExp _listWordAfterTitle = RegExp(r'^(?:[\s\p{P}]*\b(?:note|notes|list|page)\b(?=[\s\p{P}]|$))?[\s\p{P}]+', unicode: true);
final RegExp _leadingMarkJoins = RegExp(r'^[\s,:;.?!-]+');
final RegExp _bookNameLead = RegExp(r'^(?:called|named|titled|for|about|on)\s+', caseSensitive: false);
final RegExp _pagesEnd = RegExp(r'[\s.!?]+$');
final RegExp _endsInStop = RegExp(r'[.!?]\s*$');
final RegExp _tableInto = RegExp(r'^\s*(?:to|in|into|on|onto|for|under)\s+(.+?)[.!?]*\s*$', caseSensitive: false);
final RegExp _ownerLead = RegExp(r'^(?:(?:the|my|our)\s+)+', caseSensitive: false);
final RegExp _noteOrPage = RegExp(r'\s+(?:note|page)$', caseSensitive: false);
final RegExp _blankOrStop = RegExp(r'[\s.!?]');
final RegExp _verb = RegExp(
  r'^\s*(?:add|put|stick|write|jot(?:\s+down)?|append|save|file|pop|drop|note|leave|send|move|switch|go|jump|change)\s+',
  caseSensitive: false,
);
final RegExp _nameAndRest = RegExp(r'^([^.,;:!?]+)(?:[.,;:!?]\s*(.*))?$');
final RegExp _bareOrNothing = RegExp(r'^(?:this|that|it|everything|these|those|them)?$', caseSensitive: false);
final RegExp _bare = RegExp(r'^(?:this|that|it|everything|these|those|them)$', caseSensitive: false);

Plan<N>? _readWords<N extends Candidate>(String words, List<N> notes) {
  final text = _stripStopCue(words.replaceFirst(_lead, '').trim());
  if (text.isEmpty) return null;
  if (_makeBoard.hasMatch(text)) return PlanBoard<N>();
  final createList = _createList.firstMatch(text);
  if (createList != null && _truthy(createList.group(1))) {
    final made = _titleAndItems(createList.group(1)!.replaceFirst(_stopsAtEnd, '').trim());
    if (made.title.isEmpty) return null;
    return PlanCreateList<N>(title: made.title, items: made.items.isNotEmpty ? made.items : null);
  }
  final addList = _addToList.firstMatch(text);
  final addsToList = addList != null && _truthy(addList.group(1)) && _truthy(addList.group(2));
  if (addsToList) {
    final found = _noteNamed(addList.group(1)!, notes);
    if (found != null) {
      final items = _splitSpokenItems(addList.group(2)!, true);
      return PlanPlace<N>(note: found.note, text: items.join(', '), how: PlacementHow.item, task: false, many: items.length > 1);
    }
  }
  // "Add to my note labeled Go a list with…" also reads as "add to <my note labeled Go a> list with…": when that
  // name is no note, the labeled note is the reading, and the no-note answer waits until it has failed too.
  final Plan<N>? missing = addsToList ? PlanNoNote<N>(name: addList.group(1)!.replaceFirst(_trailingMarks, '').trim()) : null;
  final directAppend = _directAppend.firstMatch(text);
  if (directAppend != null && _truthy(directAppend.group(1))) {
    final direct = directAppend.group(1)!;
    // 'labeled "Go" a list…': the quotes are the title's, not the words'.
    final named = _quotedName.firstMatch(direct);
    final tail = named != null ? '${named.group(1)} ${named.group(2)}' : direct;
    final found = _titledPrefix(tail, notes) ?? _namedPrefix(tail, notes);
    if (found != null) {
      // "…my groceries list? Cauliflower…": the "list" or "note" after the title, and whatever mark Whisper put after
      // it, name the note; they are not the first thing added.
      final payload = _directPayload(found.text.replaceFirst(_listWordAfterTitle, '').replaceFirst(_leadingMarkJoins, ''));
      return PlanPlace<N>(note: found.note, text: payload.text, how: payload.how, task: payload.task, many: payload.many, items: payload.items);
    }
    // "Add this to the field guide": a whole title with nothing after it is this recording going there, which the
    // rules below read (a chapter, when the note is a book). Only a shape with words after the title fails closed
    // here, when no unique title is found.
    if (_noteNamed(direct, notes) == null) {
      return missing ?? PlanNoNote<N>(name: direct.replaceFirst(_trailingMarks, '').trim());
    }
  }
  if (missing != null) return missing;

  // "Make a book called Field guide with Trees, Birds and Rivers" (docs/BOOKS.md). Said with no name, it waits for
  // one.
  final making = _makeBook.firstMatch(text);
  if (making != null) {
    var tail = (making.group(1) ?? '').replaceFirst(_leadingStops, '');
    var pages = <String>[];
    final listed = _bookPages.firstMatch(tail);
    if (listed != null) {
      pages = [
        for (final page in cellsOf((listed.group(1) ?? '').replaceFirst(_pagesEnd, ''))) _noteNamed(page, notes)?.note.title ?? page,
      ];
      tail = tail.substring(0, listed.start);
    }
    final name = tail.replaceFirst(_bookNameLead, '').replaceFirst(_trailingMarks, '').replaceAll(_edgeQuotes, '').trim();
    return name.isNotEmpty ? PlanBook<N>(title: capitalise(name), pages: pages) : null;
  }

  // The phrase is committed: a command that stops after a name has ended.
  final ended = _endsInStop.hasMatch(text) ? text : '$text.';
  N? find(String name) => _noteNamed(name, notes)?.note;

  // "Add a table to the AttackFM bugbash note (with columns bug, owner and status)".
  final table = _table.firstMatch(text);
  if (table != null) {
    var tail = table.group(1) ?? '';
    var columns = <String>[];
    final labelled = _tableColumns.firstMatch(tail);
    if (labelled != null) {
      columns = cellsOf(labelled.group(1) ?? '');
      tail = tail.substring(0, labelled.start);
    }
    final into = _tableInto.firstMatch(tail);
    if (into != null && _truthy(into.group(1))) {
      final found = _noteNamed(into.group(1)!, notes);
      return found != null
          ? PlanTable<N>(note: found.note, columns: columns)
          : PlanNoNote<N>(name: into.group(1)!.replaceFirst(_ownerLead, '').replaceFirst(_noteOrPage, ''));
    }
    return tail.replaceAll(_blankOrStop, '').isNotEmpty ? null : PlanTable<N>(note: null, columns: columns);
  }

  final route = parseRoute(ended);
  if (route is RouteCommandNew) return PlanNew<N>();
  if (route is RouteCommandItem) {
    final note = find(route.name);
    if (note == null) return PlanNoNote<N>(name: route.name);
    final placement = Placement(how: PlacementHow.item, task: route.task, many: route.many);
    return route.rest.isNotEmpty ? _place(note, route.rest, placement) : _await(note, placement);
  }
  if (route is RouteCommandLeave) {
    final note = find(route.name);
    if (note == null) return PlanNoNote<N>(name: route.name);
    const placement = Placement(how: PlacementHow.leave, task: false, many: false);
    return route.rest.isNotEmpty ? _place(note, route.rest, placement) : _await(note, placement);
  }

  // "Add buy milk to hello trade", "put a list item on the work list: call Sam": every place the thing could end and
  // the note's name begin, and the one whose name is the best match for a note.
  final verb = _verb.firstMatch(text);
  if (verb != null) {
    final after = text.substring(verb.group(0)!.length);
    ({N note, double score, String thing, String rest})? best;
    for (final split in _into.allMatches(after)) {
      final thing = after.substring(0, split.start).trim();
      final tail = after.substring(split.end);
      // The name runs to a stop or colon, and anything after that is the thing too ("…to work: call Sam").
      final parts = _nameAndRest.firstMatch(tail);
      final name = parts?.group(1) ?? tail;
      final rest = parts?.group(2) ?? '';
      final found = _noteNamed(name, notes);
      if (found != null && (best == null || found.score > best.score)) {
        best = (note: found.note, score: found.score, thing: thing, rest: rest.trim());
      }
    }
    if (best != null) {
      // A book named: the thing is a chapter, or this note ("put this in the field guide").
      if (_isBook(best.note)) {
        final said = [best.thing, best.rest].where((part) => part.isNotEmpty).join(' ');
        return _chapterFor<N>(best.note, said.isNotEmpty ? said : (_movers.hasMatch(text) ? 'this' : ''));
      }
      if (_movers.hasMatch(text) && _bareOrNothing.hasMatch(best.thing) && best.rest.isEmpty) return PlanMove<N>(note: best.note);
      final noun = _objectNoun.firstMatch(best.thing);
      final placement = _placementOf(noun);
      final thing = [noun != null ? best.thing.substring(noun.group(0)!.length) : best.thing, best.rest]
          .where((part) => part.isNotEmpty)
          .join(' ')
          .trim();
      final bare = _bare.hasMatch(thing);
      return thing.isNotEmpty && !bare ? _place(best.note, thing, placement) : _await(best.note, placement);
    }
  }

  if (route is RouteCommandNote) {
    final note = find(route.name);
    if (note == null) return PlanNoNote<N>(name: route.name);
    if (route.rest.isNotEmpty) {
      return PlanPlace<N>(note: note, text: route.rest, how: PlacementHow.leave, task: false, many: false);
    }
    return _movers.hasMatch(text)
        ? PlanMove<N>(note: note)
        : PlanAwait<N>(note: note, how: PlacementHow.leave, task: false, many: false);
  }
  return null;
}

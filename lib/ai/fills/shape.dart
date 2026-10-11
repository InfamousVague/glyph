/// The shape of a blank, read by code from where it sits and a few plain words (docs/DESIGN.md §145, 2.6), and the
/// check an answer must pass before it is written (5.7). A port of `src/app/ai/fills/shape.ts`.
///
/// The kinds probes gave a small model a worked example per shape and took fifteen blanks from 3 right to 12. Rather
/// than ask a person to write kind words, the shape comes from what they already write: a blank as a note's whole
/// first line is a title, as a whole list item it adds items, in a table cell it answers for that row and column,
/// `{?in Japanese}` is a translation. The shape picks the hint line the model is given, its budget, the check and
/// where it lands.
///
/// The page cannot send the engine a grammar, so the check does that work after: an echo of the line taken off, a
/// title or a summary naming something the note lacks refused, a translation into Japanese without Japanese script
/// refused, and a cap on every shape. A refused answer writes nothing. Each rule's cases are the probes' own answers.
///
/// What differs:
/// - The languages' English names came from `Intl.DisplayNames` on the page; here they are the same list written
///   out, as Node answered it (ICU 78).
/// - Accents come off through ai/support/unaccent.dart, which has no normaliser to call (it says what that costs).
/// - `Checked` is one class with [Checked.ok]; its `why` is a [CheckWhy], whose [CheckWhy.id] is the page's word
///   (`didnt-fit` is no Dart name). A cell is a `({header, row})` record.
library;

import '../../core/blanks.dart';
import '../../core/front_matter.dart';
import '../../core/item_syntax.dart';
import '../support/unaccent.dart';

/// The shapes a blank can have (`Shape`); each name is the page's own word.
enum Shape { title, language, items, cell, summary, number, line, phrase }

/// A language a blank asks for (`Language`).
class Language {
  const Language({required this.name, required this.script});

  final String name;

  /// Its own script, which the check looks for; null for one written in Latin letters.
  final RegExp? script;

  @override
  bool operator ==(Object other) => other is Language && other.name == name && other.script?.pattern == script?.pattern;

  @override
  int get hashCode => Object.hash(name, script?.pattern);

  @override
  String toString() => 'Language($name${script == null ? '' : ', its own script'})';
}

/// What a blank's place and words say of it (`ShapeInfo`).
class ShapeInfo {
  const ShapeInfo({required this.shape, required this.count, required this.language, required this.cell, required this.titleLine, required this.wholeLine, required this.tooShort});

  final Shape shape;

  /// How many items, for an items blank; one otherwise.
  final int count;

  /// The language asked for, for a language blank.
  final Language? language;

  /// A cell's column header and its row's first cell, for a cell (and a language cell).
  final ({String header, String row})? cell;

  /// The blank sits on the note's first line of words, which never holds a mark (6.2).
  final bool titleLine;

  /// The blank is the whole of its line, a heading's `#` or a list's lead aside.
  final bool wholeLine;

  /// A title blank over too few words to be named from: nothing runs.
  final bool tooShort;

  /// This, with the fields given changed.
  ShapeInfo copyWith({Shape? shape, int? count, Language? language, ({String header, String row})? cell, bool? tooShort}) => ShapeInfo(
    shape: shape ?? this.shape,
    count: count ?? this.count,
    language: language ?? this.language,
    cell: cell ?? this.cell,
    titleLine: titleLine,
    wholeLine: wholeLine,
    tooShort: tooShort ?? this.tooShort,
  );

  @override
  bool operator ==(Object other) =>
      other is ShapeInfo &&
      other.shape == shape &&
      other.count == count &&
      other.language == language &&
      other.cell == cell &&
      other.titleLine == titleLine &&
      other.wholeLine == wholeLine &&
      other.tooShort == tooShort;

  @override
  int get hashCode => Object.hash(shape, count, language, cell, titleLine, wholeLine, tooShort);

  @override
  String toString() => 'ShapeInfo(${shape.name}, count $count, $language, $cell, titleLine $titleLine, wholeLine $wholeLine, tooShort $tooShort)';
}

/// The tokens each shape may write, before the three for its `[N] ` (`SHAPE_BUDGET`).
const Map<Shape, int> shapeBudget = {Shape.title: 24, Shape.language: 64, Shape.items: 32, Shape.cell: 24, Shape.summary: 64, Shape.number: 16, Shape.line: 64, Shape.phrase: 32};

/// A blank's whole budget: its shape's, an items blank's times its count, and three for `[N] `.
int budgetOf(ShapeInfo info) => shapeBudget[info.shape]! * (info.shape == Shape.items ? info.count : 1) + 3;

// ---- languages ------------------------------------------------------------------------------------------------------

RegExp _script(String source) => RegExp(source, unicode: true);

/// Scripts of their own, by language code: the check wants one of these in a translation.
final Map<String, RegExp> _scripts = {
  'ja': _script(r'[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}]'),
  'zh': _script(r'\p{Script=Han}'),
  'ko': _script(r'\p{Script=Hangul}'),
  'ru': _script(r'\p{Script=Cyrillic}'),
  'uk': _script(r'\p{Script=Cyrillic}'),
  'el': _script(r'\p{Script=Greek}'),
  'ar': _script(r'\p{Script=Arabic}'),
  'he': _script(r'\p{Script=Hebrew}'),
  'th': _script(r'\p{Script=Thai}'),
  'hi': _script(r'\p{Script=Devanagari}'),
};

/// The page's fixed list of codes, each with the English name `Intl.DisplayNames` gives it.
const List<(String, String)> _codes = [
  ('ja', 'Japanese'), ('zh', 'Chinese'), ('ko', 'Korean'), ('ru', 'Russian'), ('uk', 'Ukrainian'), ('el', 'Greek'), ('ar', 'Arabic'), ('he', 'Hebrew'), //
  ('th', 'Thai'), ('hi', 'Hindi'), ('fr', 'French'), ('de', 'German'), ('es', 'Spanish'), ('it', 'Italian'), ('pt', 'Portuguese'), ('nl', 'Dutch'), //
  ('sv', 'Swedish'), ('no', 'Norwegian'), ('da', 'Danish'), ('fi', 'Finnish'), ('pl', 'Polish'), ('cs', 'Czech'), ('tr', 'Turkish'), ('vi', 'Vietnamese'), //
  ('id', 'Indonesian'), ('ms', 'Malay'), ('hu', 'Hungarian'), ('ro', 'Romanian'), ('ga', 'Irish'), ('cy', 'Welsh'), ('is', 'Icelandic'), ('ca', 'Catalan'), //
  ('eu', 'Basque'), ('hr', 'Croatian'), ('sr', 'Serbian'), ('bg', 'Bulgarian'), ('sk', 'Slovak'), ('sl', 'Slovenian'), ('et', 'Estonian'), ('lv', 'Latvian'), //
  ('lt', 'Lithuanian'), ('tl', 'Filipino'), ('sw', 'Swahili'), ('fa', 'Persian'), ('ur', 'Urdu'), ('bn', 'Bangla'), ('ta', 'Tamil'), ('la', 'Latin'),
];

/// Every language by its English name, lower-cased.
final Map<String, Language> _languages = {
  for (final (code, name) in _codes) name.toLowerCase(): Language(name: name, script: _scripts[code]),
  'mandarin': Language(name: 'Chinese', script: _scripts['zh']),
  'farsi': const Language(name: 'Persian', script: null),
};

final RegExp _languageWords = RegExp(r'^(?:in\s+)?([a-z]+(?:\s+[a-z]+)?)[?.!]*$', caseSensitive: false);

/// The language a question asks for: `in Japanese`, `Japanese`, `in which year` names none.
Language? languageAsked(String words) {
  final found = _languageWords.firstMatch(jsTrim(words));
  return found == null ? null : _languages[found.group(1)!.toLowerCase()];
}

// ---- where the blank sits -------------------------------------------------------------------------------------------

/// Where the line holding [at] starts: JavaScript's `text.lastIndexOf('\n', at - 1) + 1`, which Dart refuses at 0.
int _lineStart(String text, int at) => at <= 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;

/// The line a blank sits on, where it starts, and which line of the note it is.
({String line, int start, int index}) _lineOf(String text, Blank blank) {
  final start = _lineStart(text, blank.from);
  final end = text.indexOf('\n', blank.to);
  return (line: text.substring(start, end == -1 ? text.length : end), start: start, index: '\n'.allMatches(text.substring(0, start)).length);
}

final RegExp _picture = RegExp(r'^!\[[^\]]*\]\([^)]*\)\s*$');

/// The index of the note's first line of words, as its title reads it: after the front matter, not a picture.
int titleLineIndex(String text) {
  final lines = text.split('\n');
  for (var at = frontMatterEnd(lines); at < lines.length; at += 1) {
    final line = lines[at];
    if (jsTrim(line).isNotEmpty && !_picture.hasMatch(line)) return at;
  }
  return -1;
}

final RegExp _firstPipe = RegExp(r'^\|');
final RegExp _lastPipe = RegExp(r'(?<!\\)\|$');
final RegExp _pipe = RegExp(r'(?<!\\)\|');
final RegExp _tableLine = RegExp(r'^\s*\|');
final RegExp _delimiterRow = RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');

/// The cells of a table line, pipes as the reader splits them.
List<String> tableCells(String line) => [for (final cell in jsTrim(line).replaceFirst(_firstPipe, '').replaceFirst(_lastPipe, '').split(_pipe)) jsTrim(cell)];

/// For a blank that is a table body cell's whole words: its column's header and its row's first cell.
({String header, String row})? _cellOf(String text, Blank blank) {
  final (:line, :start, :index) = _lineOf(text, blank);
  if (!_tableLine.hasMatch(line)) return null;
  final pipes = _pipe.allMatches(line.substring(0, blank.from - start)).length;
  final column = (pipes == 0 ? 1 : pipes) - 1;
  final cells = tableCells(line);
  if ((column < cells.length ? cells[column] : '') != text.substring(blank.from, blank.to)) return null;
  final lines = text.split('\n');
  var top = index;
  while (top > 0 && _tableLine.hasMatch(lines[top - 1])) {
    top -= 1;
  }
  // A body row: the header, then the delimiter, then this row somewhere below.
  if (index < top + 2 || !_delimiterRow.hasMatch(top + 1 < lines.length ? lines[top + 1] : '')) return null;
  final headers = tableCells(lines[top]);
  return (header: column < headers.length ? headers[column] : '', row: cells.isEmpty ? '' : cells[0]);
}

final RegExp _summary = RegExp(r'^(?:a |the )?(?:summary|in one line|sum up|sum it up|gist|the gist|tl;?dr|the point|one line)$', caseSensitive: false);

/// A unit straight after the blank makes it a number: never the one-letter names or "in", which are words too.
final RegExp _unitAfter = RegExp(
  r'^(?:grams?|kg|kilos?|kilograms?|mg|ml|litres?|liters?|minutes?|mins?|hours?|seconds?|secs?|days?|weeks?|months?|years?|km|kilometres?|kilometers?|miles?|metres?|meters?|cm|mm|feet|foot|ft|inches|°c|°f|degrees?|calories|kcal|percent|pounds?|lbs?|oz|ounces?|cups?|tsp|tbsp|people|times|steps|pages)\b|^%',
  caseSensitive: false,
);
final RegExp _numberQuestion = RegExp(r'^(?:how many|how much|how long|how far|how old|how tall|how big|how heavy)\b', caseSensitive: false);
const Map<String, int> _countWords = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'a few': 3, 'a couple of': 2, 'a couple': 2};
final RegExp _countDigit = RegExp(r'\b([1-5])\b');
final RegExp _countWord = RegExp(r'\b(one|two|three|four|five|a few|a couple of|a couple)\b', caseSensitive: false);

/// The number of items a question asks for, one to five, or null where it names none.
int? _itemsAsked(String question) {
  final digits = _countDigit.firstMatch(question);
  if (digits != null) return int.parse(digits.group(1)!);
  final words = _countWord.firstMatch(question);
  return words == null ? null : _countWords[words.group(1)!.toLowerCase()];
}

final RegExp _headingLead = RegExp(r'^\s*#{1,6}\s+');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _closingMarks = RegExp(r'[?.!:]+$');

/// The shape of a blank, the first that applies (docs/DESIGN.md §145, 2.6).
ShapeInfo shapeOf(Blank blank, String text) {
  final (:line, start: _, :index) = _lineOf(text, blank);
  final own = text.substring(blank.from, blank.to);
  final titleLine = index == titleLineIndex(text);
  final bare = jsTrim(line.replaceFirst(_headingLead, ''));
  final lead = listLead(line);
  final wholeItem = lead != null && jsTrim(line.substring(lead.wordsAt)) == own;
  final wholeLine = bare == own || wholeItem;
  final base = ShapeInfo(shape: Shape.phrase, count: 1, language: null, cell: null, titleLine: titleLine, wholeLine: wholeLine, tooShort: false);
  final question = blank.question;

  if (titleLine && bare == own && asksForTitle(question)) {
    final below = withoutBlanks(text.split('\n').skip(index + 1).join('\n'));
    final words = below.split(_spaces).where(_letterOrDigit.hasMatch).length;
    return base.copyWith(shape: Shape.title, tooShort: words < 20);
  }
  final cell = _cellOf(text, blank);
  final language = languageAsked(question) ?? (cell != null && question.isEmpty ? languageAsked(cell.header) : null);
  if (language != null) return base.copyWith(shape: Shape.language, language: language, cell: cell);
  if (wholeItem) {
    final todo = lead.done != null;
    return base.copyWith(shape: Shape.items, count: _itemsAsked(question) ?? (todo ? 1 : 3));
  }
  if (cell != null) return base.copyWith(shape: Shape.cell, cell: cell);
  if (_summary.hasMatch(jsTrim(question.replaceFirst(_closingMarks, '')))) return base.copyWith(shape: Shape.summary);
  // A whole line is a line, whatever its question starts with: `{?how long to boil an egg}` as a first line wants
  // its answer said, not a bare number.
  if (wholeLine) return base.copyWith(shape: Shape.line);
  final asking = askingWords(blank, text);
  if (_unitAfter.hasMatch(asking.after) || _numberQuestion.hasMatch(question)) return base.copyWith(shape: Shape.number);
  return base;
}

/// The hint line a message gives a blank, numbered: none for a phrase, which needs none.
String? hintFor(int n, ShapeInfo info) {
  switch (info.shape) {
    case Shape.title:
      return "Blank $n is the note's title.";
    case Shape.language:
      // A language with a script of its own is asked for in that script by name: measured, the 4B dropped the script
      // for three cells of a table ("arigatō gozaimasu"), which the check then refused.
      final language = info.language!;
      final script = language.script != null ? ', in ${language.name} script' : '';
      return info.cell != null ? 'Blank $n is ${info.cell!.row} in ${language.name}$script.' : 'Blank $n asks for ${language.name}$script.';
    case Shape.items:
      return info.count > 1 ? 'Blanks $n to ${n + info.count - 1} are whole items of the list they are in, each one new.' : 'Blank $n is a whole item of the list it is in.';
    case Shape.cell:
      return 'Blank $n is the ${info.cell!.header} of ${info.cell!.row}.';
    case Shape.summary:
      return 'Blank $n is one sentence saying what the lines above it say.';
    case Shape.number:
      return 'Blank $n is a number.';
    case Shape.line:
      return 'Blank $n is a whole line.';
    case Shape.phrase:
      return null;
  }
}

// ---- the check ------------------------------------------------------------------------------------------------------

/// Why an answer was not written: the page's `'unknown' | 'none' | 'didnt-fit'`, each as its [id].
enum CheckWhy {
  unknown('unknown'),
  none('none'),
  didntFit('didnt-fit');

  const CheckWhy(this.id);

  /// The page's word for it.
  final String id;
}

/// An answer checked against its blank (`Checked`): what to write, or why nothing is.
class Checked {
  /// An answer that passed: its words, and every item for an items blank (the words alone otherwise).
  const Checked.ok(String this.text, this.items) : ok = true, why = null;

  /// An answer that did not, and why.
  const Checked.not(CheckWhy this.why) : ok = false, text = null, items = const [];

  final bool ok;

  /// The words to write; null when not [ok].
  final String? text;

  /// The items to write; empty when not [ok].
  final List<String> items;

  /// Why nothing is written; null when [ok].
  final CheckWhy? why;

  /// The object the page holds, key for key.
  Map<String, Object?> toJson() => ok ? {'ok': true, 'text': text, 'items': items} : {'ok': false, 'why': why!.id};

  @override
  bool operator ==(Object other) {
    if (other is! Checked || other.ok != ok || other.text != text || other.why != why || other.items.length != items.length) return false;
    for (var i = 0; i < items.length; i += 1) {
      if (other.items[i] != items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(ok, text, why, Object.hashAll(items));

  @override
  String toString() => ok ? 'Checked.ok($text, $items)' : 'Checked.not(${why!.id})';
}

/// Each shape's caps: words and characters.
const Map<Shape, ({int words, int chars})> _caps = {
  Shape.phrase: (words: 20, chars: 160),
  Shape.number: (words: 8, chars: 40),
  Shape.cell: (words: 10, chars: 80),
  Shape.title: (words: 8, chars: 60),
  Shape.summary: (words: 30, chars: 240),
  Shape.line: (words: 40, chars: 320),
  Shape.items: (words: 12, chars: 120),
  Shape.language: (words: 30, chars: 200),
};

final RegExp _unknown = RegExp(r"^(?:unknown\b|not sure\b|i don['’]t know\b|i do not know\b|n\/a\b)", caseSensitive: false);
final RegExp _monthOrDay = RegExp(
  r'^(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|monday|tuesday|wednesday|thursday|friday|saturday|sunday)$',
  caseSensitive: false,
);

final RegExp _answerLead = RegExp(r'^answer\s*:\s*', caseSensitive: false);
final RegExp _listMark = RegExp(r'^(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)');
final RegExp _braceOpen = RegExp(r'^\{\?\d*\s*');
final RegExp _braceClose = RegExp(r'\}$');
final RegExp _bold = RegExp(r'^\*\*(.*)\*\*$');
final RegExp _ticks = RegExp(r'^`+([^`]*)`+$');
final RegExp _quotes = RegExp(r'''^["“”'‘’](.*)["“”'‘’]$''');

/// An answer's first line tidied: quotes, backticks, bold, `Answer:`, a list mark and a blank's braces off.
String _tidied(String line) {
  var out = jsTrim(line);
  for (var pass = 0; pass < 3; pass += 1) {
    out = jsTrim(
      out
          .replaceFirst(_answerLead, '')
          .replaceFirst(_listMark, '')
          .replaceFirst(_braceOpen, '')
          .replaceFirst(_braceClose, '')
          .replaceFirstMapped(_bold, (m) => m.group(1)!)
          .replaceFirstMapped(_ticks, (m) => m.group(1)!)
          .replaceFirstMapped(_quotes, (m) => m.group(1)!),
    );
  }
  return out.replaceAll(_spaces, ' ');
}

int _wordCount(String text) => text.split(_spaces).where((word) => word.isNotEmpty).length;

final RegExp _lettersAndDigits = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// A text's words in lower case with their accents off: letters and digits, nothing else.
List<String> _lowerWords(String text) => [for (final match in _lettersAndDigits.allMatches(unaccented(text.toLowerCase()))) match.group(0)!];

final RegExp _digitRun = RegExp(r'\d+');
final RegExp _edges = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);
final RegExp _startsUpper = RegExp(r'^\p{Lu}', unicode: true);

/// Whether an answer holds a number, a date or a capitalised name the note does not (5.7): a title or a summary is
/// made of the note's own words, so one naming something else is refused. The note is read without its blanks and
/// fills.
bool _namesWhatNoteLacks(String answer, String note) {
  final plain = withoutBlanks(note);
  final known = _lowerWords(plain).toSet();
  final digits = {for (final match in _digitRun.allMatches(plain)) match.group(0)!};
  for (final run in _digitRun.allMatches(answer)) {
    if (!digits.contains(run.group(0))) return true;
  }
  final words = answer.split(_spaces);
  for (var i = 0; i < words.length; i += 1) {
    final word = words[i].replaceAll(_edges, '');
    if (word.isEmpty) continue;
    final lowered = _lowerWords(word);
    final lower = lowered.isEmpty ? '' : lowered[0];
    if (_monthOrDay.hasMatch(word) && !known.contains(lower)) return true;
    if (i == 0 || word == 'I' || !_startsUpper.hasMatch(word)) continue;
    if (!known.contains(lower)) return true;
  }
  return false;
}

/// The words just before a blank, for taking an echo of them off an answer.
List<String> _wordsBefore(String text, Blank blank) => _lowerWords(text.substring(_lineStart(text, blank.from), blank.from).replaceAll(blankPattern, ' '));

String _firstLower(String word) {
  final lowered = _lowerWords(word);
  return lowered.isEmpty ? '' : lowered[0];
}

/// An answer that begins by saying three or more of the words just before the blank has them taken off.
String _withoutEcho(String answer, List<String> before) {
  final words = answer.split(_spaces);
  final lower = [for (final word in words) _firstLower(word)];
  bool leads(List<String> tail) {
    for (var i = 0; i < tail.length; i += 1) {
      // Past the answer's last word JavaScript compares with nothing, which no word equals.
      if (i >= lower.length || tail[i] != lower[i]) return false;
    }
    return true;
  }

  for (var size = before.length < lower.length - 1 ? before.length : lower.length - 1; size >= 3; size -= 1) {
    if (leads(before.sublist(before.length - size))) return words.sublist(size).join(' ');
  }
  // The echo may start mid-sentence: "the newest Pixel is the Pixel 10" after "The newest Pixel is the".
  for (var start = 0; start < before.length - 2; start += 1) {
    final tail = before.sublist(start);
    if (tail.length >= 3 && tail.length < lower.length && leads(tail)) return words.sublist(tail.length).join(' ');
  }
  return answer;
}

final RegExp _cellEdge = RegExp(r'^\s*[|]');

/// The character after a blank, and whether the blank ends its sentence.
({String next, bool ends}) _endsSentence(String text, Blank blank) {
  final next = blank.to < text.length ? text[blank.to] : '';
  final rest = text.substring(blank.to).split('\n').first;
  return (next: next, ends: jsTrim(rest).isEmpty || _cellEdge.hasMatch(rest));
}

final RegExp _endsInStop = RegExp(r'\.$');
final RegExp _endsInTwoStops = RegExp(r'\.\.$');
final RegExp _startsWithStop = RegExp(r'^[.,:?!]');
final RegExp _trailingSpace = RegExp(r'\s+$');
final RegExp _hashes = RegExp(r'^#+\s*');
final RegExp _wordAfter = RegExp(r'^\s*([\p{L}°%]+)', unicode: true);
final RegExp _regExpSyntax = RegExp(r'[.*+?^${}()|[\]\\]');
final RegExp _closingBrackets = RegExp(r'\s*\([^)]*\)$');
final RegExp _aDigit = RegExp(r'\d');

/// The answer checked against its blank's shape (5.7). [lines] are the answer lines for this blank as the reader
/// found them (several for an items blank), [truncated] whether the budget cut the last of them, [note] the note's
/// text.
Checked checkShape(List<String> lines, Blank blank, ShapeInfo info, String note, [bool truncated = false]) {
  final table = _tableLine.hasMatch(note.substring(_lineStart(note, blank.from), blank.from));
  if (info.shape == Shape.items) return _checkItems(lines, blank, info, note, truncated);
  final worded = lines.where((l) => jsTrim(l).isNotEmpty);
  var text = _tidied(worded.isEmpty ? '' : worded.first);
  if (_unknown.hasMatch(text)) return const Checked.not(CheckWhy.unknown);
  text = _withoutEcho(text, _wordsBefore(note, blank));
  final (:next, :ends) = _endsSentence(note, blank);
  if (_endsInStop.hasMatch(text) && !_endsInTwoStops.hasMatch(text) && (!ends || _startsWithStop.hasMatch(next))) {
    text = text.substring(0, text.length - 1).replaceFirst(_trailingSpace, '');
  }
  if (info.shape == Shape.title) text = text.replaceFirst(_hashes, '').replaceFirst(_endsInStop, '');
  if (info.shape == Shape.number) {
    final after = _wordAfter.firstMatch(note.substring(blank.to))?.group(1);
    if (after != null && after.isNotEmpty) {
      text = text.replaceFirst(RegExp('\\s*${after.replaceAllMapped(_regExpSyntax, (m) => '\\${m.group(0)}')}\$', caseSensitive: false), '');
    }
  }
  if (info.shape == Shape.language && info.language?.script == null) text = text.replaceFirst(_closingBrackets, '');
  if (table) text = text.replaceAll('|', '/');
  if (text.isEmpty || text.toLowerCase() == blank.question.toLowerCase()) return const Checked.not(CheckWhy.none);
  if (_unknown.hasMatch(text)) return const Checked.not(CheckWhy.unknown);
  final caps = _caps[info.shape]!;
  final cut = truncated && worded.length <= 1;
  if (cut || _wordCount(text) > caps.words || text.length > caps.chars) return const Checked.not(CheckWhy.didntFit);
  if (info.shape == Shape.number && !_aDigit.hasMatch(text)) return const Checked.not(CheckWhy.didntFit);
  if ((info.shape == Shape.title || info.shape == Shape.summary) && _namesWhatNoteLacks(text, note)) return const Checked.not(CheckWhy.didntFit);
  final script = info.shape == Shape.language ? info.language?.script : null;
  if (script != null && !script.hasMatch(text)) return const Checked.not(CheckWhy.didntFit);
  return Checked.ok(text, [text]);
}

/// An items blank's lines: each tidied, those the list already has dropped, at most its count.
Checked _checkItems(List<String> lines, Blank blank, ShapeInfo info, String note, bool truncated) {
  final nonEmpty = lines.where((l) => jsTrim(l).isNotEmpty).toList();
  // A half line cut by the budget goes.
  final whole = truncated ? nonEmpty.sublist(0, nonEmpty.isEmpty ? 0 : nonEmpty.length - 1) : nonEmpty;
  final listed = <String>{};
  for (final l in note.split('\n')) {
    final lead = listLead(l);
    final key = lead != null ? _lowerWords(l.substring(lead.wordsAt)).join(' ') : '';
    if (key.isNotEmpty) listed.add(key);
  }
  final items = <String>[];
  var unknown = 0;
  for (final raw in whole) {
    final text = _tidied(raw).replaceFirst(_endsInStop, '');
    if (text.isEmpty) continue;
    if (_unknown.hasMatch(text)) {
      unknown += 1;
      continue;
    }
    final key = _lowerWords(text).join(' ');
    if (listed.contains(key) || items.any((i) => _lowerWords(i).join(' ') == key)) continue;
    if (_wordCount(text) > _caps[Shape.items]!.words || text.length > _caps[Shape.items]!.chars) continue;
    if (text.toLowerCase() == blank.question.toLowerCase()) continue;
    items.add(text);
    if (items.length == info.count) break;
  }
  if (items.isEmpty) return Checked.not(unknown > 0 ? CheckWhy.unknown : (nonEmpty.isNotEmpty ? CheckWhy.didntFit : CheckWhy.none));
  return Checked.ok(items[0], items);
}

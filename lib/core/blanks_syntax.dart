/// Blanks the AI fills: a question in curly brackets where its answer belongs (docs/DESIGN.md §145). A port of the
/// half of `src/app/core/blanks.ts` that reads text, which is all of that file: it calls no model and touches no
/// page.
///
/// Matt: "Add an option as well for the users to be able to put special syntax in a note that allows the AI to fill
/// context make a few different scenarios like "flights are cheapest to Tokyo on [[what day / time?]]" Then the AI
/// fills in the squares with the factual response using the phones local AI model". He chose `{?question}` over his
/// own `[[…]]`, which is a note link today and a tap on it makes a note.
///
///     Flights are cheapest to Tokyo on {?what day / time?}
///     The capital of Australia is {?}.          an empty blank reads the sentence it sits in
///     \{?not a blank}                           written about, not asked: a backslash before the bracket
///
/// The characters are plain text everywhere else: Obsidian, GitHub and Pandoc show them as typed. The editor draws
/// one as a square, and this module is the part with no editor: the pattern, the reader for places that have no
/// parser (the title, the gist, home's to-dos, the item text sent to Notion and GitHub, search), the words a blank
/// asks with, and the form an answer takes in the file.
///
/// An answer from the model is an Unsure mark whose bracket says where it came from, which the app hides and a tap
/// shows:
///
///     ??midweek??(Qwen3.5 4B from memory, 2026-09-28. Asked: what day / time?)
///
/// Imports only the front matter rule, maths and JavaScript's trim.
///
/// What differs: the names and the shapes. The web's `BLANK`, `BLANK_SAMPLE`, `WIKI_LINK` and `FILLED` are
/// [blankPattern] (its source [blankSource], since the title's rule builds on it), [blankSample], [wikiLinkPattern]
/// and [filledPattern]; `Blank`, `Asking`, `Filled` and `FillSource` are classes with value equality; a span is a
/// `({from, to})` record and a place a `({n, of})` one. A Dart `RegExp` carries no `lastIndex`, so nothing is reset
/// after a loop.
library;

import 'front_matter.dart';
import 'item_syntax.dart' show jsTrim;
import 'maths.dart';

/// `{?what day}`: not `{{?…}}` (the journal's and the templates' family), not after a backslash, not after a `$`
/// (`${?HOME}`, a config file's optional value), not `{??…` (an Unsure mark someone put in braces), no `|` in the
/// question (a table's cell edge), at most 160 characters, one line. The source of `BLANK`.
const String blankSource = r'(?<![{\\$])\{\?(?!\?)([^{}|\n]{0,160})\}(?!\})';

/// [blankSource] as a pattern (`BLANK`).
final RegExp blankPattern = RegExp(blankSource);

/// What the setup and the Guide show a blank as, so a change of syntax reaches them (`BLANK_SAMPLE`).
const String blankSample = '{?a question}';

/// One blank in a note's text (`Blank`).
class Blank {
  const Blank({required this.from, required this.to, required this.question});

  /// The opening `{`.
  final int from;

  /// Just after the closing `}`.
  final int to;

  /// The question inside, spaces either side taken off; empty for `{?}`.
  final String question;

  @override
  bool operator ==(Object other) => other is Blank && other.from == from && other.to == to && other.question == question;

  @override
  int get hashCode => Object.hash(from, to, question);

  @override
  String toString() => 'Blank($from, $to, $question)';
}

/// Every match of the pattern in [text], with no regard to where it sits: the editor filters these by its own parse.
List<Blank> blankMatches(String text, [int offset = 0]) => [
  for (final match in blankPattern.allMatches(text))
    Blank(from: offset + match.start, to: offset + match.end, question: jsTrim(match.group(1) ?? '')),
];

// ---- the pure reader ----------------------------------------------------------------------------------------------

/// A code fence's opening or closing line, three backticks or tildes, as the editor reads one.
final RegExp _codeFence = RegExp(r'^\s*(```|~~~)');

/// An HTML comment, over any number of lines.
final RegExp _comment = RegExp(r'<!--[\s\S]*?-->');

/// An HTML tag's own text: `<span title="…">`, `</div>`.
final RegExp _tag = RegExp(r'<\/?[A-Za-z][^<>\n]*>');

/// A link's or a picture's address, and an autolink.
final RegExp _address = RegExp(r'\]\([^)\n]*\)|<(?:https?:|mailto:|geo:)[^<>\s]*>');

/// A note link's title: a blank there would be filled into the link's target (`[[Trip to {?capital}]]`), so it is
/// text (`WIKI_LINK`).
final RegExp wikiLinkPattern = RegExp(r'\[\[[^\]\n]*\]\]');

/// Where the words are quiet for a blank, away from the editor: front matter, fenced code, code spans, comments,
/// HTML tags, maths and link addresses. The editor asks its parser instead, and the two differ only where the cost
/// is a word in a title or a gist (an indented code block, an HTML block over several lines), since a fill is only
/// ever started from the editor's list.
List<({int from, int to})> quietRanges(String text) {
  final quiet = <({int from, int to})>[];
  final lines = text.split('\n');
  var at = 0;
  final front = frontMatterEnd(lines);
  String? fence;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final start = at;
    at += line.length + 1;
    if (index < front) {
      quiet.add((from: start, to: start + line.length));
      continue;
    }
    final marker = _codeFence.firstMatch(line)?.group(1);
    if (marker != null) {
      fence = fence == null ? marker : (fence == marker ? null : fence);
      quiet.add((from: start, to: start + line.length));
      continue;
    }
    if (fence != null) {
      quiet.add((from: start, to: start + line.length));
      continue;
    }
    quiet.addAll(_codeSpans(line, start));
    for (final pattern in [_tag, _address, wikiLinkPattern]) {
      for (final match in pattern.allMatches(line)) {
        quiet.add((from: start + match.start, to: start + match.end));
      }
    }
    quiet.addAll(mathsIn(line, start));
  }
  for (final match in _comment.allMatches(text)) {
    quiet.add((from: match.start, to: match.end));
  }
  return quiet;
}

final RegExp _ticks = RegExp(r'`+');

/// A line's code spans: a run of backticks, then the next run of exactly as many, as CommonMark pairs them.
List<({int from, int to})> _codeSpans(String line, int offset) {
  final spans = <({int from, int to})>[];
  final runs = [for (final m in _ticks.allMatches(line)) (at: m.start, size: m.end - m.start)];
  for (var i = 0; i < runs.length; i += 1) {
    final open = runs[i];
    var close = -1;
    for (var j = i + 1; j < runs.length; j += 1) {
      if (runs[j].size == open.size) {
        close = j;
        break;
      }
    }
    if (close < 0) continue;
    spans.add((from: offset + open.at, to: offset + runs[close].at + open.size));
    i = close;
  }
  return spans;
}

/// The blanks in a note's text, as the places with no editor read them: every match of the pattern that does not
/// start in quiet words ([quietRanges]). The front matter's own lines are quiet, so its keys never hold a blank.
List<Blank> blanksIn(String text, [int offset = 0]) {
  final quiet = quietRanges(text);
  return [
    for (final blank in blankMatches(text))
      if (!quiet.any((q) => blank.from >= q.from && blank.from < q.to))
        Blank(from: blank.from + offset, to: blank.to + offset, question: blank.question),
  ];
}

/// Whether [text] has a blank anywhere a reader would find one. Cheap when it has no `{?` at all.
bool hasBlank(String text) => text.contains('{?') && blanksIn(text).isNotEmpty;

/// A blank's identity across the note being closed and opened: its question and its order among the blanks with
/// that same question, counted in the note's order (docs/DESIGN.md §145, 1.6).
int orderOf(List<Blank> blanks, Blank blank) => blanks.where((b) => b.question == blank.question && b.from < blank.from).length;

/// The blank with this question and order, as [orderOf] counts them, or null.
Blank? findBlank(List<Blank> blanks, String question, int order) {
  final same = blanks.where((b) => b.question == question).toList();
  return order >= 0 && order < same.length ? same[order] : null;
}

// ---- the words a blank asks with ----------------------------------------------------------------------------------

/// What a blank asks, as the solvers, the live screen and the shapes read it (`Asking`).
class Asking {
  const Asking({
    required this.question,
    required this.sentence,
    required this.label,
    required this.before,
    required this.after,
    required this.prior,
    required this.text,
  });

  /// The question in the braces.
  final String question;

  /// The blank's own sentence with the blank taken out, on its line only.
  final String sentence;

  /// The words of that sentence straight before the blank: at most five words.
  final String label;

  /// Every word of that sentence before the blank.
  final String before;

  /// The words of that sentence straight after it.
  final String after;

  /// The sentence before, read only when the blank's own sentence is the blank alone or a label (`A: {?}`): before
  /// it on its line, else the last sentence of the line above, one empty line between passed over. Empty otherwise.
  final String prior;

  /// All of the above that count, as one run of words: what the word screens read.
  final String text;
}

/// A sentence ends at `.`, `?` or `!` before a space or the line's end.
final RegExp _sentenceEnd = RegExp(r'[.?!]+(?=\s|$)');

/// The sentences of a line, as spans; blanks must already be masked so their question marks end nothing.
List<({int from, int to})> _sentences(String line) {
  final spans = <({int from, int to})>[];
  var start = 0;
  for (final match in _sentenceEnd.allMatches(line)) {
    spans.add((from: start, to: match.end));
    start = match.end;
  }
  if (start < line.length) spans.add((from: start, to: line.length));
  return spans;
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Words that are letters or digits: a label's `→` or a list's dash is not a word.
List<String> _wordsOf(String text) => text.split(_spaces).where(_letterOrDigit.hasMatch).toList();

final RegExp _endsInColon = RegExp(r':$');

/// A sentence that is only a label: at most two words, the last ending in a colon (`A:`, `Answer:`).
bool _isLabel(String text) {
  final words = _wordsOf(text);
  if (words.isEmpty) return true;
  return words.length <= 2 && _endsInColon.hasMatch(jsTrim(text));
}

/// The line with every blank in it masked, so a question's `?` ends no sentence. Offsets are kept.
String _masked(String line) => line.replaceAllMapped(blankPattern, (m) => '' * m.group(0)!.length);

final RegExp _masks = RegExp('+');
final RegExp _listLead = RegExp(r'^\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?');
final RegExp _headingLead = RegExp(r'^\s*#{1,6}\s+');
final RegExp _spaceBeforeStop = RegExp(r'\s+([.,;:!?])');

/// Words for reading: masks gone, list leads and quote marks off, spaces closed.
String _tidyWords(String text) => jsTrim(
  text
      .replaceAll(_masks, ' ')
      .replaceFirst(_listLead, '')
      .replaceFirst(_headingLead, '')
      .replaceAll(_spaces, ' ')
      .replaceAllMapped(_spaceBeforeStop, (m) => m.group(1)!),
);

/// The words a blank asks with (docs/DESIGN.md §145, 2.1): its question, its own sentence, and, when that sentence
/// is the blank alone or a label, the sentence before it. So `How many days until Christmas? {?}` is read as that
/// question, and the note idiom `Q: Who won the 2026 World Cup?` then `A: {?}` is read as its Q.
Asking askingWords(Blank blank, String text) {
  final lineStart = blank.from <= 0 ? 0 : text.lastIndexOf('\n', blank.from - 1) + 1;
  final lineEndAt = blank.to >= text.length ? -1 : text.indexOf('\n', blank.to);
  final line = text.substring(lineStart, lineEndAt == -1 ? text.length : lineEndAt);
  final mask = _masked(line);
  final at = blank.from - lineStart;
  final spans = _sentences(mask);
  var own = (from: 0, to: mask.length);
  for (final s in spans) {
    if (at >= s.from && at < s.to) {
      own = s;
      break;
    }
  }
  final beforeBlank = mask.substring(own.from, at);
  final afterFrom = at + (blank.to - blank.from);
  final afterBlank = afterFrom < own.to ? mask.substring(afterFrom, own.to) : '';
  final sentence = _tidyWords('$beforeBlank $afterBlank');
  final labelWords = _wordsOf(_tidyWords(beforeBlank));
  final label = labelWords.sublist(labelWords.length > 5 ? labelWords.length - 5 : 0).join(' ');
  final after = _tidyWords(afterBlank);
  var prior = '';
  if (_isLabel(_tidyWords(beforeBlank)) && _wordsOf(after).isEmpty) {
    final earlier = spans.where((s) => s.to <= own.from && _wordsOf(_tidyWords(mask.substring(s.from, s.to))).isNotEmpty).toList();
    if (earlier.isNotEmpty) {
      prior = _tidyWords(mask.substring(earlier.last.from, earlier.last.to));
    } else {
      prior = _lastSentenceAbove(text, lineStart);
    }
  }
  final words = [blank.question, sentence, prior].where((each) => each.isNotEmpty).join(' ');
  return Asking(question: blank.question, sentence: sentence, label: label, before: _tidyWords(beforeBlank), after: after, prior: prior, text: words);
}

/// The last sentence of the line above [lineStart], one empty line between passed over.
String _lastSentenceAbove(String text, int lineStart) {
  if (lineStart == 0) return '';
  final lines = text.substring(0, lineStart - 1).split('\n');
  var above = lines.last;
  if (jsTrim(above).isEmpty && lines.length > 1) above = lines[lines.length - 2];
  if (jsTrim(above).isEmpty) return '';
  final mask = _masked(above);
  final spans = _sentences(mask).where((s) => _wordsOf(_tidyWords(mask.substring(s.from, s.to))).isNotEmpty).toList();
  return spans.isEmpty ? '' : _tidyWords(mask.substring(spans.last.from, spans.last.to));
}

// ---- the answer in the file ---------------------------------------------------------------------------------------

/// A filled blank's bracket: whose answer, from where, when, what was asked, and an item's place. "From the web"
/// names its source: `Qwen3.5 4B from Open-Meteo, 2026-09-28`, the page having asked that source (`FILLED`).
final RegExp filledPattern = RegExp(r'^(.+?) from (memory|this note|[A-Z][\w.-]*(?: and [A-Z][\w.-]*)?), (\d{4}-\d{2}-\d{2})(?:\. Asked: (.+?))?(?:\. (\d) of (\d))?$');

/// The kinds of place an answer comes from.
enum FillSourceKind { memory, note, web }

/// Where an answer came from (`FillSource`): the model's memory, this note, or a source on the web by its [name].
class FillSource {
  /// From the model's memory.
  const FillSource.memory() : kind = FillSourceKind.memory, name = null;

  /// From this note's own words.
  const FillSource.note() : kind = FillSourceKind.note, name = null;

  /// From the web, by the name of the source asked.
  const FillSource.web(String this.name) : kind = FillSourceKind.web;

  final FillSourceKind kind;

  /// The web source's name; null for the other kinds.
  final String? name;

  @override
  bool operator ==(Object other) => other is FillSource && other.kind == kind && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => name == null ? 'FillSource.${kind.name}' : 'FillSource.web($name)';
}

/// A fill's bracket, read (`Filled`).
class Filled {
  const Filled({required this.model, required this.source, required this.date, required this.question, required this.place});

  /// The model's name as the app shows it, or Claude's.
  final String model;
  final FillSource source;

  /// ISO, `2026-09-28`.
  final String date;

  /// What was asked, or null for an empty blank.
  final String? question;

  /// An item's place among the items of one fill: `2 of 3`.
  final ({int n, int of})? place;

  @override
  bool operator ==(Object other) =>
      other is Filled && other.model == model && other.source == source && other.date == date && other.question == question && other.place == place;

  @override
  int get hashCode => Object.hash(model, source, date, question, place);

  @override
  String toString() => 'Filled($model, $source, $date, $question, $place)';
}

/// A bracket read as a fill's, or null for a person's own note on an Unsure mark.
Filled? readFilled(String bracket) {
  final found = filledPattern.firstMatch(jsTrim(bracket));
  if (found == null) return null;
  final from = found.group(2) ?? '';
  final source = from == 'memory' ? const FillSource.memory() : (from == 'this note' ? const FillSource.note() : FillSource.web(from));
  final n = found.group(5);
  final of = found.group(6);
  return Filled(
    model: found.group(1) ?? '',
    source: source,
    date: found.group(3) ?? '',
    question: found.group(4),
    place: n != null && of != null ? (n: int.parse(n), of: int.parse(of)) : null,
  );
}

/// The words a source is written as in the bracket.
String _sourceWords(FillSource source) => switch (source.kind) {
  FillSourceKind.memory => 'from memory',
  FillSourceKind.note => 'from this note',
  FillSourceKind.web => 'from ${source.name}',
};

final RegExp _questionMarks = RegExp(r'\?{2,}');
final RegExp _placeEnding = RegExp(r'\.(\s*\d of \d)$');

/// A question as a bracket may hold it: no brackets of its own, no `??`, and no ending the place pattern would read.
String _bracketQuestion(String question) => jsTrim(
  question
      .replaceAll('(', '[')
      .replaceAll(')', ']')
      .replaceAll(_questionMarks, '?')
      .replaceAll('\n', ' ')
      .replaceFirstMapped(_placeEnding, (m) => ',${m.group(1)}'),
);

final RegExp _leadingQuestionMarks = RegExp(r'^\?+\s*');
final RegExp _trailingQuestionMarks = RegExp(r'\?+$');
final RegExp _trailingSpace = RegExp(r'\s+$');

/// An answer written as the mark the parser really reads (docs/DESIGN.md §145, 6.1). The parser refuses a delimiter
/// with another piece of itself either side, and a mark's note ends at its first `)`. So a trailing `?` goes after
/// the bracket, a `??` inside becomes `?`, a question's brackets are square, and a `?` straight before the blank
/// ([before]) gets a space after it.
String filledMark(
  String answer,
  ({String model, FillSource source, String date}) meta,
  String question, [
  String before = '',
  ({int n, int of})? place,
]) {
  var words = jsTrim(answer.replaceAll(_spaces, ' ')).replaceAll(_questionMarks, '?').replaceFirst(_leadingQuestionMarks, '');
  var trail = '';
  final ending = _trailingQuestionMarks.firstMatch(words);
  if (ending != null) {
    trail = '?';
    words = words.substring(0, ending.start).replaceFirst(_trailingSpace, '');
  }
  final asked = _bracketQuestion(question);
  final bracket =
      '${meta.model} ${_sourceWords(meta.source)}, ${meta.date}${asked.isNotEmpty ? '. Asked: $asked' : ''}${place != null && place.of > 1 ? '. ${place.n} of ${place.of}' : ''}';
  final lead = before.endsWith('?') ? ' ' : '';
  return '$lead??$words??($bracket)$trail';
}

/// An Unsure mark with a note: `??words??(note)`. The words need a word against each `??`, as the parser's rule
/// does.
final RegExp _noted = RegExp(r'\?\?(?=\S)((?:(?!\?\?).)*?\S)\?\?\(([^)\n]+)\)');

/// Every filled answer in [text]: the mark's span, its words, and its bracket read.
List<({int from, int to, String words, Filled filled, String bracket})> fillsIn(String text, [int offset = 0]) {
  if (!text.contains('??(')) return [];
  final found = <({int from, int to, String words, Filled filled, String bracket})>[];
  for (final match in _noted.allMatches(text)) {
    final filled = readFilled(match.group(2) ?? '');
    if (filled != null) {
      found.add((from: offset + match.start, to: offset + match.end, words: match.group(1) ?? '', filled: filled, bracket: match.group(2) ?? ''));
    }
  }
  return found;
}

/// The text with every filled answer read as its words alone: what every reader but the editor sees (the title,
/// home's to-dos, the item text sent to Notion and GitHub, search, the gist). A person's own note on an Unsure mark
/// is left as it is. Costs nothing on text with no `??(` in it.
String plainFills(String text) {
  if (!text.contains('??(')) return text;
  return text.replaceAllMapped(_noted, (m) => readFilled(m.group(2) ?? '') != null ? (m.group(1) ?? '') : m.group(0)!);
}

// ---- titles -------------------------------------------------------------------------------------------------------

/// A question that asks for a title: `title`, `a name`, `name this`, `what to call this`.
final RegExp _asksTitle = RegExp(
  r'^(?:a |the )?(?:title|name|heading)(?: (?:this|it|for this|for it))?$|^(?:title|name) (?:this|it)$|^what to call (?:this|it)$',
  caseSensitive: false,
);
final RegExp _closingStops = RegExp(r'[?.!]+$');

/// Whether a blank's question asks for a title: empty, or one of the few ways people ask for one.
bool asksForTitle(String question) {
  final words = jsTrim(jsTrim(question).replaceFirst(_closingStops, ''));
  return words == '' || _asksTitle.hasMatch(words);
}

final RegExp _titleLead = RegExp(r'^\s*(?:#{1,6}\s+)?');
final RegExp _wholeBlank = RegExp('^$blankSource\\s*\$');
final RegExp _hashes = RegExp(r'#{1,6}\s+$');
final RegExp _runOfSpaces = RegExp(r'[ \t]{2,}');

/// A note's first line as its title reads it (docs/DESIGN.md §145, 8): a filled answer as its words, a blank that
/// is the whole line as nothing when it asks for a title (the note is untitled until it fills) or as its question's
/// words otherwise, and a blank among other words left out with the spaces closed up. The heading's `#` stays for
/// the title rule to take off (note_text.dart `noteTitle`).
String titleWords(String line) {
  var text = plainFills(line);
  if (!text.contains('{?')) return text;
  final lead = _titleLead.firstMatch(text)?.group(0) ?? '';
  final rest = text.substring(lead.length);
  final whole = _wholeBlank.firstMatch(jsTrim(rest));
  if (whole != null) {
    final question = jsTrim(whole.group(1) ?? '');
    return asksForTitle(question) ? lead.replaceFirst(_hashes, '').replaceFirst(_trailingSpace, '') : '$lead$question';
  }
  text = text.replaceAll(blankPattern, '');
  return text.replaceAll(_runOfSpaces, ' ').replaceFirst(_trailingSpace, '');
}

/// The text with its blanks taken out and its fills read as words: what the gist gives the smallest model, which is
/// never handed a blank to answer, and whose one line never shows braces or a bracket.
String withoutBlanks(String text) {
  final plain = plainFills(text);
  if (!plain.contains('{?')) return plain;
  return plain.replaceAll(blankPattern, '').replaceAll(_runOfSpaces, ' ');
}

final RegExp _twoSpaces = RegExp(r'\s{2,}');

/// An item's or a card's words as a reader shows them: filled answers as their words, and a blank as its question's
/// words, since a to-do holding a blank is a question and is shown as one (home's To do).
String readableWords(String text) {
  final plain = plainFills(text);
  if (!plain.contains('{?')) return plain;
  return plain.replaceAllMapped(blankPattern, (m) => jsTrim(m.group(1) ?? '')).replaceAll(_twoSpaces, ' ');
}

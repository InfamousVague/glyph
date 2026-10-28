/// Ghost Academy's lessons (academy_screen.dart): what each mark is, what to type, and how the Academy knows it
/// worked. A port of `src/app/academy/lessons.ts`.
///
/// Matt: "we need a Glyph Academy section that teaches you markdown then teaches you the extra stuff we have. Build
/// the academy section start with just the markdown basics set it up as a live code type thing where it teaches you
/// then you type it and see it format below."
///
/// So a lesson is one mark: a line or two on what it does, an example to copy, something to write of your own, and a
/// check run on what was really typed, not on it matching the example. Any title passes the title lesson. The checks
/// are forgiving on purpose: extra lines, other marks and different words are all fine, since a person learning is
/// usually trying things.
///
/// Markdown basics came first; the chapters after it are the extra stuff, and together they teach every row of the
/// cheat sheet, each row by exactly one lesson ([Lesson.rows]), which the tests hold them to. A check reads what was
/// typed the way the note does wherever the note has a reader of its own: the parser for a mark it parses, and the
/// editor's own finders for the marks drawn by what a line says (a tag, a counter, a sum, a choice). A lesson for a
/// plugin's mark ([Lesson.needs]) is offered only while that mark is switched on, as the cheat sheet shows its row
/// only then.
///
/// What differs:
/// - The words (every lesson's title, teaching, example, task, praise and hint, the chapters and what each is about)
///   are lessons.g.dart, read off the web app's own running page and not retyped; the checks are here, one for each
///   lesson by its id ([_checks]), each the web's line for line over the Dart ports of the same finders.
///   test/academy/fixtures/web_lessons.json holds what the page's checks answered for 182 texts, and the tests hold
///   these to it.
/// - A chapter is its name, a `String`, where the page had a union of the seven names.
/// - `LESSONS`, `CHAPTERS` and `CHAPTER_ABOUT` are [lessons], [chapters] and [chapterAbout].
/// - Progress is read from and written to `stored` (lib/core/stored.dart), the app's `localStorage`, under the web's
///   own keys.
library;

import '../comments/format.dart' show readComments;
import '../core/blanks_syntax.dart' show blanksIn;
import '../core/boards/fence.dart' show boardsIn;
import '../core/boards/items.dart' show itemsIn, refsIn;
import '../core/emoji.dart' show shortcodesIn;
import '../core/item_syntax.dart';
import '../core/place_refs.dart' show placeLines;
import '../core/properties.dart' show ticketOf;
import '../core/query/fence.dart' show queryFencesIn;
import '../core/query/read.dart';
import '../core/stored.dart';
import '../core/sums.dart' show sumOnLine;
import '../core/tags.dart' show tagsIn;
import '../core/task_fields.dart' show FieldKind, fieldsIn;
import '../core/video_refs.dart' show videoOfLine;
import '../editor/items/bookmark_line.dart' show bookmarkLineIn;
import '../editor/items/choices.dart' show choiceOn;
import '../editor/items/counters.dart' show countersIn;
import '../editor/items/footnotes.dart' show footnotesIn;
import '../editor/items/heading_progress.dart' show headingCounts;
import '../editor/items/wiki_links.dart' show wikiLinksIn;
import '../editor/marks/mark_notes.dart' show isTint, notePattern, notesIn;
import '../editor/state/text.dart' show Doc;
import '../editor/syntax/language.dart' show glyphMarkdown;
import '../editor/syntax/markdown.dart' show MarkdownParser;
import '../editor/view/extended.dart' show calloutKind;
import '../plugins/registry.dart' show plugins;
import '../core/iphone_app.dart' show recordsVoice;

part 'lessons.g.dart';

/// One lesson: one mark (`Lesson`).
class Lesson {
  const Lesson._({
    required this.id,
    required this.chapter,
    required this.symbol,
    required this.rows,
    required this.title,
    required this.teach,
    required this.example,
    required this.task,
    required this.praise,
    required this.hint,
    this.standard = false,
    this.needs,
  });

  final String id;

  /// One of [chapters].
  final String chapter;

  /// What the lesson is called: the mark, in words.
  final String title;

  /// The mark itself, as the cheat sheet writes it: `**`, `- [ ]`.
  final String symbol;

  /// The cheat sheet's rows this lesson teaches, by name; the first is its own. Empty for a lesson that goes further
  /// with a mark another lesson owns: a board's height, a query's where:.
  final List<String> rows;

  /// Markdown any app reads the same way, left out for a person who says they know it already (Matt: "the option to
  /// skip default markdown if the user doesn't want to learn that"). Ghost.md's own marks are always taught.
  final bool standard;

  /// The plugin mark it needs switched on, by name (lib/plugins/marks.dart); without it, the lesson is not offered.
  final String? needs;

  /// What it does, in a line or two.
  final String teach;

  /// The example to look at, and what **Show me** writes into the field.
  final String example;

  /// What to write of your own.
  final String task;

  /// Said when it passes.
  final String praise;

  /// Offered when it is asked for.
  final String hint;

  /// Reads what is typed: true the moment this lesson's mark is in it.
  bool passes(String text) => _checks[id]!(text);

  @override
  String toString() => 'Lesson($id)';
}

typedef _Check = bool Function(String text);

/// A line of its own, anywhere in what was typed (`line`; `m` says the pattern was written with the `m` flag).
_Check _line(String pattern, {bool m = false}) {
  final found = RegExp(pattern, multiLine: m);
  return found.hasMatch;
}

/// The lines of what was typed as the editor holds them, for the finders that read a document (`docOf`).
Doc _docOf(String text) => Doc.of(text.split('\n'));

/// The parser, for the plugin marks switched on now, kept while they stay the same.
({String key, MarkdownParser parser})? _language;

/// The node names in the last text read, so a check run on every keystroke parses each text once.
({String text, String key, Set<String> names})? _last;

/// Every node the note's own parser finds in `text` (lib/editor/syntax/language.dart), the switched-on plugins'
/// marks included (`nodesIn`).
Set<String> _nodesIn(String text) {
  final formats = plugins.formats();
  final key = formats.map((format) => format.delimiter).join(' ');
  final last = _last;
  if (last != null && last.text == text && last.key == key) return last.names;
  var language = _language;
  if (language == null || language.key != key) _language = language = (key: key, parser: glyphMarkdown(formats));
  final names = <String>{};
  language.parser.parse(text).iterate(enter: (node) => names.add(node.name));
  _last = (text: text, key: key, names: names);
  return names;
}

/// True when the note's parser finds a `name` node in what was typed: the mark, read the way the note reads it
/// (`parsed`).
_Check _parsed(String name) => (text) => _nodesIn(text).contains(name);

/// A mark written with a note in brackets after it: a color for a highlight (`tint`), or else a note on the mark
/// (`noted`).
bool _noted(String text, bool tint) {
  final formats = plugins.formats();
  final pattern = notePattern(formats);
  return pattern != null && notesIn(text, pattern).any((note) => isTint(note, formats) == tint);
}

final RegExp _footnoteMark = RegExp(r'\[\^([^\]\s]+)\](?!:)');

/// A footnote: a definition line, and its mark in the words (`footnoted`).
bool _footnoted(String text) {
  final marks = <String>{for (final mark in _footnoteMark.allMatches(text)) mark.group(1)!};
  return footnotesIn(text).any((note) => marks.contains(note.name));
}

/// Every query fence in what was typed that reads, as its query (`queriesIn`).
Iterable<Query> _queriesIn(String text) => queryFencesIn(text).map((fence) => readQuery(fence.body).query).whereType<Query>();

final RegExp _front = RegExp(r'^---\n([\s\S]*?)\n---(?:\n|$)');
final RegExp _isBook = RegExp(r'^book:\s*true\s*$', multiLine: true);
final RegExp _hasKey = RegExp(r'^key:\s*[A-Za-z][A-Za-z0-9]{0,9}\s*$', multiLine: true);

/// A notebook with a ticket key: `book: true` and `key:` in its front matter (`ticketNotebook`).
bool _ticketNotebook(String text) {
  final front = _front.firstMatch(text)?.group(1);
  return front != null && front.isNotEmpty && _isBook.hasMatch(front) && _hasKey.hasMatch(front);
}

final RegExp _italicUnder = RegExp(r'(?:^|[^\w_])_\S(?:[^_\n]*\S)?_(?![\w_])', multiLine: true);
final RegExp _italicStar = RegExp(r'(?<![*\w])\*[^*\n]+\*(?!\*)');
final RegExp _fenceLine = RegExp(r'^[ \t]*(?:```|~~~)', multiLine: true);

/// Each lesson's check, by its id: `passes` of the lesson of that id in lessons.ts, in the order they are taught.
final Map<String, _Check> _checks = <String, _Check>{
  // ---- Markdown basics: what every Markdown app reads the same way -------------------------------------------------
  'title': _line(r'^[ \t]*#[ \t]+\S', m: true),
  // Any heading below a title, since the lesson itself offers ### as well as ## (Matt, of three hashes: "the lesson
  // isn't passed").
  'heading': _line(r'^[ \t]*#{2,6}[ \t]+\S', m: true),
  'bold': _line(r'\*\*\S(?:[^*]*\S)?\*\*'),
  'italic': (text) => _italicUnder.hasMatch(text) || _italicStar.hasMatch(text),
  'both': _line(r'(\*\*\*|___)\S(?:[^*_\n]*\S)?\1'),
  'struck': _line(r'~~\S(?:[^~\n]*\S)?~~'),
  'code': _line(r'`[^`\n]+`'),
  'link': _line(r'\[[^\]\n]+\]\([^)\s]+\)'),
  'list': _line('^[ \\t]*$bulletPattern[ \\t]+\\S', m: true),
  'number': _line('^[ \\t]*$numberPattern[ \\t]+\\S', m: true),
  'todo': _line('^[ \\t]*$markerPattern[ \\t]+$boxPattern[ \\t]*\\S', m: true),
  'quote': _line(r'^[ \t]*>[ \t]*\S', m: true),
  'rule': _line(r'^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$', m: true),
  'fence': (text) => _fenceLine.allMatches(text).length >= 2,
  // ---- More Markdown -----------------------------------------------------------------------------------------------
  'table': _parsed('Table'),
  'picture': _parsed('Image'),
  'video': (text) => text.split('\n').any((one) => videoOfLine(jsTrim(one)) != null),
  'raised': _parsed('Superscript'),
  'lowered': _parsed('Subscript'),
  'footnote': _footnoted,
  'definition': _line(r'^[ \t]*[^\s:].*\n[ \t]{0,3}:[ \t]+\S', m: true),
  'maths': _line(r'\$\$[^$]+\$\$|\$[^$\n]+\$'),
  'emoji': (text) => shortcodesIn(text).isNotEmpty,
  'callout': (text) => text.split('\n').any((each) => calloutKind(each) != null),
  'diagram': _line(r'^[ \t]*```mermaid[ \t]*\n[\s\S]*?\n[ \t]*```', m: true),
  // ---- Lines that do more ------------------------------------------------------------------------------------------
  'tag': (text) => tagsIn(text).isNotEmpty,
  'choice': (text) {
    final doc = _docOf(text);
    for (var n = 1; n <= doc.lines; n += 1) {
      if (choiceOn(doc, n) != null) return true;
    }
    return false;
  },
  'counter': (text) => countersIn(text).isNotEmpty,
  'sum': (text) => text.split('\n').any((each) => sumOnLine(each) != null),
  'blank': (text) => blanksIn(text).isNotEmpty,
  'hiddenLine': _line(r'^[ \t]*>\|[ \t]*\S', m: true),
  'progress': (text) => headingCounts(_docOf(text)).isNotEmpty,
  'comment': (text) => readComments(text).anchors.isNotEmpty,
  // ---- Links and places --------------------------------------------------------------------------------------------
  'wiki': (text) => wikiLinksIn(text).isNotEmpty,
  'bookmark': (text) => bookmarkLineIn(text) != null,
  'place': (text) => placeLines(text).isNotEmpty,
  // ---- Boards and to-dos -------------------------------------------------------------------------------------------
  'fields': (text) => fieldsIn(text).any((field) => field.kind == FieldKind.date || field.kind == FieldKind.priority || field.kind == FieldKind.person || field.kind == FieldKind.inline),
  'anchor': (text) => itemsIn(text).isNotEmpty,
  'itemRef': (text) => refsIn(text).isNotEmpty,
  'board': (text) => boardsIn(text).isNotEmpty,
  'boardHeight': (text) => boardsIn(text).any((board) => board.height != null),
  // ---- Tickets and queries -----------------------------------------------------------------------------------------
  'ticket': (text) => (ticketOf(text)?.status ?? '').isNotEmpty,
  'notebookKey': _ticketNotebook,
  'query': (text) => queryFencesIn(text).any((fence) => readQuery(fence.body).query?.kind == QueryKind.tasks),
  'queryWhere': (text) => _queriesIn(text).any((query) => query.where != null),
  'queryShow': (text) => _queriesIn(text).any((query) => query.show != null && query.show != ShowAs.list),
  'queryGroup': (text) => _queriesIn(text).any((query) => query.group != null || query.total.isNotEmpty),
  // ---- Marks and effects -------------------------------------------------------------------------------------------
  'spoiler': _parsed('Spoiler'),
  'highlight': _parsed('Highlight'),
  'tint': (text) => _noted(text, true),
  'aside': _parsed('Aside'),
  'unsure': _parsed('Unsure'),
  'markNote': (text) => _noted(text, false),
  'redact': _parsed('Redact'),
  'shout': _parsed('Shout'),
  'added': _parsed('Added'),
  'heat': _parsed('Heat'),
  'frost': _parsed('Frost'),
  'wave': _parsed('Wave'),
  'shimmer': _parsed('Shimmer'),
  'haunt': _parsed('Haunt'),
};

/// What a lesson teaches, as this device words it. The words are the web app's (lessons.g.dart), and one of them
/// names another platform and a + an iPhone does not have ("on Android, the + beside an empty line writes it when
/// you choose A video"): where nothing is recorded or filmed ([recordsVoice] false, the iPhone app; Matt,
/// 2026-10-13) the video lesson says what the line is and leaves out how another phone makes it.
String teachOf(Lesson lesson, {bool? voice}) => lesson.id == 'video' && !(voice ?? recordsVoice)
    ? 'A picture of the film’s first frame, linked to the film itself. The film stays on the device it was added on; everywhere else the still shows.'
    : lesson.teach;

/// What a lesson asks for, as this device words it ([teachOf]).
String taskOf(Lesson lesson, {bool? voice}) => lesson.id == 'video' && !(voice ?? recordsVoice) ? 'Write a video’s line.' : lesson.task;

/// The lessons on offer now: every one whose plugin mark, where it needs one, is switched on; and without standard
/// Markdown, for a person who knows it already ([readSkipStandard]).
List<Lesson> lessonsNow([bool skipStandard = false]) {
  final on = <String>{for (final format in plugins.formats()) format.name};
  return <Lesson>[
    for (final lesson in lessons)
      if ((lesson.needs == null || on.contains(lesson.needs)) && !(skipStandard && lesson.standard)) lesson,
  ];
}

/// The lessons of a chapter, in the order they are taught, from `from` (every lesson, unless told).
List<Lesson> lessonsIn(String chapter, [List<Lesson>? from]) => <Lesson>[
  for (final lesson in from ?? lessons)
    if (lesson.chapter == chapter) lesson,
];

/// Where a person has got to, kept between visits, so the Academy opens at the first lesson not passed.
const String academyProgressKey = 'glyph-academy';

Set<String> readProgress() => stored.read<List<String>>(academyProgressKey, const <String>[], (ids) => ids is List ? ids.whereType<String>().toList() : const <String>[]).toSet();

/// Not kept, progress still counts for this visit.
void writeProgress(Set<String> done) => stored.write(academyProgressKey, done.toList());

/// Whether a person has said they know Markdown already, kept between visits.
const String academySkipStandardKey = 'glyph-academy-skip-standard';

bool readSkipStandard() => stored.read<bool>(academySkipStandardKey, false, (value) => value == true);

void writeSkipStandard(bool skip) => stored.write(academySkipStandardKey, skip);

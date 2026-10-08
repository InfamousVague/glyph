/// The templates a new note can start from (docs/DESIGN.md §144). A port of `src/app/notes/noteTemplates.ts`, and
/// with it the parts of the web's core it stands on that have not been ported yet: `core/template.ts`
/// ([fillTemplate], [formatStamp], [firstOpenAt]), `core/look.ts` ([Look], [lookOf], [withLook]),
/// `core/frontMatter.ts` `withFrontMatterValue`, `book/journal.ts` `uniqueTitle` and `core/stamp.ts` `longDay` and
/// `clockTime`.
///
/// Matt: "When making a new note also offer a few templates to chose from with cards showing how they look (map
/// header, typography focus, etc)", and then where: "cards on the blank page". So a new note's blank page draws a
/// card for each under its names (lib/notes/template_cards.dart), and a card's tap turns the blank note into that
/// template.
///
/// Eight, in code: A day, A meeting, A checklist, Notes on a book, A map at the top (`look: map`), A page to read
/// (`look: reading`), and two that make a ticket, a Bug report and a Feature, whose words open with the ticket's own
/// front matter. A name that is taken gets " (2)", as a journal's entry does. And the one rule for the caret: fill,
/// settle the name, and only then measure. Pure.
///
/// What differs:
/// - **The names of days and months are English, in the order en-GB writes them** ("Monday 28 September", "Sept"),
///   where the page asks the device's language through `Intl`. The app has no `intl` yet; the web's own tests pin
///   en-GB, and these are theirs.
/// - `firstOpenAt` reads a line's words without taking a landing bookmark off them (`core/itemSyntax.ts`
///   `withoutBookmark`), which no template writes.
/// - The pieces of core listed above live here until core has them; each keeps the web's name.
library;

import 'package:flutter/foundation.dart';

import '../core/front_matter.dart';
import '../core/note_text.dart';

// ---- core/look.ts -------------------------------------------------------------------------------------------------

/// How a note looks (`Look`): one flat key in its front matter, `look:`, with two values.
enum Look { map, reading }

/// The note's look, or null for the usual one: `look:` read in any case, and anything but the two taken as none
/// (`lookOf`).
Look? lookOf(String body) {
  if (!body.startsWith('---') && !body.startsWith('+++')) return null;
  return switch (frontMatterValue(body, 'look')?.trim().toLowerCase()) { 'map' => Look.map, 'reading' => Look.reading, _ => null };
}

/// The body with its look set, or (null) taken off, and a block that held nothing else with it (`withLook`).
String withLook(String body, Look? look) => withFrontMatterValue(body, 'look', look?.name);

/// The body with front matter [key] set to [value] as it is written (no quoting added): replaced where the key is,
/// added last where it isn't, and front matter made where there was none. A null value takes the key off, and front
/// matter that held nothing else with it. The words are untouched (`core/frontMatter.ts` `withFrontMatterValue`).
String withFrontMatterValue(String body, String key, String? value) {
  final lines = body.split('\n');
  final pattern = RegExp('^\\s*${RegExp.escape(key)}\\s*:', caseSensitive: false);
  final line = value == null ? null : '$key: ${value.replaceAll('\n', ' ').trim()}';
  final end = frontMatterEnd(lines);
  if (end == 0) return line != null ? '---\n$line\n---\n$body' : body;
  final keys = lines.sublist(1, end - 1);
  final at = keys.indexWhere(pattern.hasMatch);
  if (at >= 0) {
    if (line != null) {
      keys[at] = line;
    } else {
      keys.removeAt(at);
    }
  } else if (line != null) {
    keys.add(line);
  }
  final rest = lines.sublist(end);
  if (keys.isEmpty) return rest.join('\n');
  return [lines[0], ...keys, lines[end - 1], ...rest].join('\n');
}

// ---- book/journal.ts ----------------------------------------------------------------------------------------------

/// [title], or with ` (2)`, ` (3)` after it until no key in [keys] is its (`uniqueTitle`).
String uniqueTitle(String title, Set<String> keys) {
  if (!keys.contains(titleKey(title))) return title;
  for (var n = 2;; n += 1) {
    final next = '$title ($n)';
    if (!keys.contains(titleKey(next))) return next;
  }
}

// ---- core/stamp.ts, core/template.ts ------------------------------------------------------------------------------

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// en-GB's short months, as `Intl` writes them: "Sept", and no stop.
const List<String> _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Monday 28 September": the weekday, the day and the month, no year (`longDay`).
String longDay(DateTime at) => '${_weekdays[at.weekday - 1]} ${at.day} ${_months[at.month - 1]}';

/// "14:05": the time on a 24-hour clock (`clockTime`).
String clockTime(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

/// "1st", "22nd", "11th".
String _ordinal(int n) {
  final tens = n % 100;
  final suffix = tens >= 11 && tens <= 13 ? 'th' : (const {1: 'st', 2: 'nd', 3: 'rd'}[n % 10] ?? 'th');
  return '$n$suffix';
}

/// The ISO week [at] falls in: its year and its number. A week is Monday to Sunday and belongs to the year its
/// Thursday is in.
({int year, int week}) _isoWeek(DateTime at) {
  final thursday = DateTime(at.year, at.month, at.day + 3 - ((at.weekday + 6) % 7));
  final first = DateTime(thursday.year, 1, 4);
  final firstThursday = DateTime(first.year, 1, 4 + 3 - ((first.weekday + 6) % 7));
  // Whole days apart, by the calendar and not the clock, so a change to summer time in between counts for nothing.
  final days = DateTime.utc(thursday.year, thursday.month, thursday.day).difference(DateTime.utc(firstThursday.year, firstThursday.month, firstThursday.day)).inDays;
  return (year: thursday.year, week: 1 + days ~/ 7);
}

String _token(String token, DateTime at) => switch (token) {
      'GGGG' => _isoWeek(at).year.toString().padLeft(4, '0'),
      'WW' => _two(_isoWeek(at).week),
      'W' => '${_isoWeek(at).week}',
      'YYYY' => at.year.toString().padLeft(4, '0'),
      'YY' => _two(at.year % 100),
      'MMMM' => _months[at.month - 1],
      'MMM' => _shortMonths[at.month - 1],
      'MM' => _two(at.month),
      'M' => '${at.month}',
      'Do' => _ordinal(at.day),
      'DD' => _two(at.day),
      'D' => '${at.day}',
      'dddd' => _weekdays[at.weekday - 1],
      'ddd' => _weekdays[at.weekday - 1].substring(0, 3),
      'HH' => _two(at.hour),
      'H' => '${at.hour}',
      'hh' => _two(at.hour % 12 == 0 ? 12 : at.hour % 12),
      'h' => '${at.hour % 12 == 0 ? 12 : at.hour % 12}',
      'mm' => _two(at.minute),
      'A' => at.hour < 12 ? 'AM' : 'PM',
      'a' => at.hour < 12 ? 'am' : 'pm',
      _ => token,
    };

/// Words in square brackets, or a token: the longest first at each place, as Moment reads them (`TOKEN`).
final RegExp _stampToken = RegExp(r'\[([^\]]*)\]|GGGG|WW|W|YYYY|YY|MMMM|MMM|MM|M|Do|DD|D|dddd|ddd|HH|H|hh|h|mm|A|a');

/// [at] written in Moment's tokens (`YYYY-MM-DD`, `dddd [at] HH:mm`), words in square brackets kept as they are
/// (`formatStamp`).
String formatStamp(DateTime at, String format) => format.replaceAllMapped(_stampToken, (m) => m.group(1) ?? _token(m.group(0)!, at));

/// A placeholder: its name, and a format after a colon for the two that take one (`PLACEHOLDER`).
final RegExp _placeholder = RegExp(r'\{\{\s*([A-Za-z_$][\w$]*|next-id)(?::([^{}]*))?\s*\}\}');

/// A front matter line that holds only the next id, quoted or not: `id: "{{next-id}}"` (`NEXT_ID_LINE`).
final RegExp _nextIdLine = RegExp(r'''^([ \t]*[\w.-]+[ \t]*:[ \t]*)(["']?)\{\{\s*next-id\s*\}\}\2[ \t]*$''');

/// The template with its front matter's next-id lines settled: filled bare, or left out where there is no id.
String _withNextIdLines(String text, String next) {
  final lines = text.split('\n');
  final end = frontMatterEnd(lines);
  if (end == 0) return text;
  final keys = <String>[];
  for (final line in lines.sublist(1, end - 1)) {
    final found = _nextIdLine.firstMatch(line);
    if (found == null) {
      keys.add(line);
    } else if (next.isNotEmpty) {
      keys.add('${found.group(1)}$next');
    }
  }
  return [lines[0], ...keys, ...lines.sublist(end - 1)].join('\n');
}

/// The template with its placeholders filled for one note (`fillTemplate`): `{{date}}`, `{{time}}`, `{{weekday}}`,
/// `{{title}}`, `{{journal}}`, `{{next-id}}`, and `{{date:FORMAT}}` and `{{time:FORMAT}}` in Moment's tokens.
/// Anything else is left as it was typed.
String fillTemplate(String text, {required DateTime at, String title = '', String journal = '', String? nextId}) {
  final next = nextId ?? '';
  final values = <String, String>{'date': longDay(at), 'time': clockTime(at), 'weekday': _weekdays[at.weekday - 1], 'title': title, 'journal': journal, 'next-id': next};
  // The id's own line first, its quotes with it, or the line gone where there is no id to give.
  return _withNextIdLines(text, next).replaceAllMapped(_placeholder, (m) {
    final name = m.group(1)!, format = m.group(2);
    if (format != null && format.trim().isNotEmpty) return name == 'date' || name == 'time' ? formatStamp(at, format.trim()) : m.group(0)!;
    return values[name] ?? m.group(0)!;
  });
}

final RegExp _quoteMarks = RegExp(r'^\s*(?:>[ \t]*)+');
final RegExp _openHeading = RegExp(r'^ {0,3}#{1,6} +$');
final RegExp _endsOpen = RegExp(r'\s$');

/// What a line says, its quote's markers and its list lead taken off (`core/itemSyntax.ts` `lineWords`).
String _lineWords(String text) {
  final unquoted = text.replaceFirst(_quoteMarks, '');
  final lead = listLead(unquoted);
  return withoutAnchor(lead != null ? unquoted.substring(lead.wordsAt) : unquoted).trim();
}

/// Where a new note's caret goes in its filled words: the end of the first line left open, or the end of the words
/// (`firstOpenAt`). A line is open when it is a heading with no words (`# `), a list's, a to-do's or a quote's lead
/// with no words (`- `, `- [ ] `, `1. `, `> `), or words ending in a space (`With `). A blank line is not open.
int firstOpenAt(String words) {
  var at = 0;
  for (final line in words.split('\n')) {
    final heading = _openHeading.hasMatch(line);
    final lead = line.trim().isNotEmpty && _lineWords(line).isEmpty;
    final leftOpen = line.trim().isNotEmpty && _endsOpen.hasMatch(line);
    if (heading || lead || leftOpen) return at + line.length;
    at += line.length + 1;
  }
  return words.length;
}

// ---- notes/noteTemplates.ts ---------------------------------------------------------------------------------------

/// Which built-in a template is (`TemplateId`).
enum TemplateId { day, meeting, checklist, book, map, reading, bug, feature }

/// A template a new note can start from (`NoteTemplate`).
@immutable
class NoteTemplate {
  const NoteTemplate({required this.id, this.kind, required this.name, required this.sentence, required this.words, this.look});

  /// A built-in's name for itself, or your own template's page's note id (lib/notes/own_templates.dart).
  final String id;

  /// Which built-in it is, or is still word for word, whose rules it keeps: A day's taken name, a map's place.
  final TemplateId? kind;

  /// The card's name.
  final String name;

  /// What it makes, in one fixed sentence, under the name.
  final String sentence;

  /// Its words, with the placeholders a journal's template takes.
  final String words;

  /// How a note made from it looks, written into its front matter; null for the usual look.
  final Look? look;

  @override
  bool operator ==(Object other) => other is NoteTemplate && other.id == id && other.kind == kind && other.name == name && other.sentence == sentence && other.words == words && other.look == look;

  @override
  int get hashCode => Object.hash(id, kind, name, sentence, words, look);
}

/// A ticket's front matter as its template writes it (`TICKET_KEYS`).
const String _ticketKeys = '---\ntype: ticket\nid: "{{next-id}}"\nstatus: To do\n---\n';

/// The eight built in, in the order the cards are drawn (`BUILT_INS`).
const List<NoteTemplate> builtIns = [
  NoteTemplate(id: 'day', kind: TemplateId.day, name: 'A day', sentence: 'Named for today, with a to-do to start.', words: '# {{date:YYYY-MM-DD}}\n\n{{date}}\n\n- [ ] '),
  NoteTemplate(
    id: 'meeting',
    kind: TemplateId.meeting,
    name: 'A meeting',
    sentence: 'Named for this minute, with who was there, notes and to-dos.',
    // "Meeting" outside the braces, so its M is not read as a month.
    words: '# Meeting {{date:YYYY-MM-DD HH.mm}}\n\nWith \n\n## Notes\n\n- \n\n## To do\n\n- [ ] ',
  ),
  NoteTemplate(id: 'checklist', kind: TemplateId.checklist, name: 'A checklist', sentence: 'A name to type, then a to-do.', words: '# {{title}}\n\n- [ ] '),
  NoteTemplate(id: 'book', kind: TemplateId.book, name: 'Notes on a book', sentence: 'Its title, who wrote it, notes and quotes.', words: '# {{title}}\n\nBy \n\n## Notes\n\n- \n\n## Quotes\n\n> '),
  NoteTemplate(id: 'map', kind: TemplateId.map, name: 'A map at the top', sentence: 'Where you are, drawn large above the words.', words: '# {{title}}\n\n{{date}}, {{time}}.\n', look: Look.map),
  NoteTemplate(id: 'reading', kind: TemplateId.reading, name: 'A page to read', sentence: 'A large title, a lead line and a column set for reading.', words: '# {{title}}\n', look: Look.reading),
  NoteTemplate(
    id: 'bug',
    kind: TemplateId.bug,
    name: 'Bug report',
    sentence: 'A ticket: how to make it happen, what should, and what did.',
    words: '$_ticketKeys# {{title}}\n\n## Steps to reproduce\n\n1. \n\n## Expected\n\n## Actual\n',
  ),
  NoteTemplate(
    id: 'feature',
    kind: TemplateId.feature,
    name: 'Feature',
    sentence: 'A ticket: the problem, the proposal, and when it is done.',
    words: '$_ticketKeys# {{title}}\n\n## Problem\n\n## Proposal\n\n## Done when\n\n- [ ] ',
  ),
];

/// A day's sentence on a day that already has a note by its name (`DAY_TAKEN_SENTENCE`).
const String dayTakenSentence = 'Today has a note by this name. This makes a second.';

/// A template filled for a note made now (`FilledTemplate`).
@immutable
class FilledTemplate {
  const FilledTemplate({required this.words, required this.body, required this.title, required this.caret, required this.renamed});

  /// The words after the front matter, the name settled: what the note's untouched record keeps.
  final String words;

  /// The whole note, its look in a front matter block of its own where it has one.
  final String body;

  /// Its name: its heading's words, or empty for an open heading.
  final String title;

  /// Where the caret goes in [body]: the first line left open.
  final int caret;

  /// Its name was taken, and it was given " (2)" or the next number free.
  final bool renamed;
}

/// The heading a note's words start with, and its words (`FIRST_HEADING`).
final RegExp _firstHeading = RegExp(r'^(#{1,6} +)(.*)$');

/// [template] filled for a note made at [at], among notes whose title keys are [taken]: filled, then its name
/// settled, then measured, so the caret and the record are both the final words' (`fillNoteTemplate`). [nextId] is
/// the next ticket key where the note is made, and [title] the name it is made with, where it has one already. A
/// template's own front matter is kept in front of the words, never counted among them.
FilledTemplate fillNoteTemplate(NoteTemplate template, DateTime at, Set<String> taken, {String? nextId, String title = ''}) {
  final filled = fillTemplate(template.words, at: at, nextId: nextId, title: title);
  final start = frontMatterOffset(filled);
  final front = filled.substring(0, start);
  var words = filled.substring(start);
  final newline = words.indexOf('\n');
  final first = newline < 0 ? words : words.substring(0, newline);
  final heading = _firstHeading.firstMatch(first);
  final named = heading?.group(2)?.trim() ?? '';
  var name = named;
  if (heading != null && named.isNotEmpty) {
    name = uniqueTitle(named, taken);
    if (name != named) words = '${heading.group(1)}$name${newline < 0 ? '' : words.substring(newline)}';
  }
  final look = template.look;
  final body = look != null ? withLook(front + words, look) : front + words;
  return FilledTemplate(words: words, body: body, title: name, caret: frontMatterOffset(body) + firstOpenAt(words), renamed: name != named);
}

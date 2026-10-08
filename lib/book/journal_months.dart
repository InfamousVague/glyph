/// A journal's entries as its view draws them (../glyph docs/DESIGN.md §142): newest first, in runs by the month each
/// was written in, every row what a person scans for - the day, the time, where, and how it starts. A port of
/// `src/app/book/journalMonths.ts`.
///
/// Ordered by when each entry was written (journal.dart `stampOf`: its `date:`, else when the note was made), never
/// by the index's order, so a notebook kept as a journal, an index edited by hand and one two devices merged (the
/// lines in either order) all draw each month once, newest first. Two written in the same minute are told apart by
/// the index: the later line is the newer.
///
/// A line with no note is one of two things. An entry's name with no note is not drawn: an entry taken back that a
/// sync brought the line of back, or one in the Trash, which comes back with its note. Any other name is a page
/// planned before the notebook was kept as a journal, still to be written, listed apart.
///
/// What differs:
/// - **Days and months are written in English, as en-GB orders them** ("Monday 28 September", "September 2026",
///   "27 Sept"), where the page asks the device's language (lib/core/template.dart says why). The web's own tests
///   pin en-GB, and those are the cases ported.
/// - **A journal's card says its newest as the page said it on Matt's phone, "Mon, Sep 28, 13:05"**, which is en-US:
///   [journalCards] was ported first, for the home page, and held to the page itself there
///   (test/core/note_text_test.dart, test/home). It was in lib/core/book.dart, which hands it on.
/// - `noteOf` answers null where the page's answers `undefined`.
library;

import '../core/book.dart' show BookPlace, Chapter, chaptersOf, isJournalBody;
import '../core/front_matter.dart' show frontMatterEnd;
import '../core/geotag.dart' show geoTagOf, tagLabel;
import '../core/item_syntax.dart' show jsTrim, lineWords;
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/place_refs.dart' show placeOfLine;
import '../core/template.dart';
import '../core/title_key.dart' show titleKey;
import '../core/video_refs.dart' show videoOfLine;
import 'journal.dart' show isEntryTitle, stampOf, templateOf;

/// A line of the journal's index, and the note it names, if there is one.
class JournalPage {
  const JournalPage({required this.title, required this.line, required this.note});
  final String title;

  /// The line it is on in the index.
  final int line;
  final Note? note;
}

class EntryRow {
  const EntryRow({required this.title, required this.id, required this.wall, required this.day, required this.weekday, required this.time, required this.place, required this.first, required this.label});
  final String title;
  final String id;

  /// When it was written, as its wall clock (journal.dart `stampOf`).
  final int wall;

  /// "28" and "Mon".
  final String day;
  final String weekday;

  /// "14:05".
  final String time;

  /// Where it was written, by name or by coordinates; null when it says nowhere.
  final String? place;

  /// The first line of its own words, plain; empty when it has none yet.
  final String first;

  /// The row said whole: "Monday 28 September, 14:05, Trafalgar Square. Walked along the river."
  final String label;
}

class JournalMonth {
  JournalMonth({required this.key, required this.label, required this.entries});

  /// "2026-09".
  final String key;

  /// "September 2026".
  final String label;
  final List<EntryRow> entries;
}

/// A wall clock (journal.dart `stampOf`) as a time whose own fields are that clock.
DateTime _clock(int wall) => DateTime.fromMillisecondsSinceEpoch(wall, isUtc: true);

/// A wall clock as the moment here that reads the same (`localOf`).
DateTime _localOf(int wall) {
  final at = _clock(wall);
  return DateTime(at.year, at.month, at.day, at.hour, at.minute);
}

/// A written entry, and when it was written.
typedef _Written = ({String title, int line, Note note, int wall});

/// The template as it was filled for an entry: its words, which are not the entry's own.
String Function(_Written page) _templateFor(String template, String journal) {
  if (!template.contains('{{')) return (_) => template;
  return (page) {
    final at = _clock(page.wall);
    return fillTemplate(template, at: _localOf(page.wall), title: page.title, journal: journal, said: (date: longDay(at), time: clockTime(at), weekday: weekdayName(at)));
  };
}

/// A time the template put at the start of a line, bold or not: "**14:05** ".
final RegExp _leadingTime = RegExp(r'^(?:\*\*|__)?\d{1,2}[:.]\d{2}(?:\*\*|__)?\s*');

/// A heading, `## ` with no words yet as well.
final RegExp _heading = RegExp(r'^#{1,6}(?:\s|$)');

/// What opens or closes fenced code: its run of backticks or tildes.
final RegExp _fence = RegExp(r'^(`{3,}|~{3,})');

/// A picture alone, or a canvas or a note drawn in a frame: `![](image/a.jpg)`, `![[Plan]]`.
final RegExp _picture = RegExp(r'^!(?:\[[^\]]*\]\([^)]*\)|\[\[[^\]]*\]\])$');

/// A table's row, in a quote or not.
final RegExp _tableRow = RegExp(r'^\s*(?:>\s*)*\|');

/// A rule: three or more dashes, stars or underscores, spaced or not.
final RegExp _rule = RegExp(r'^(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$');

/// A callout's kind, `[!NOTE]`, and its fold sign, before its title.
final RegExp _callout = RegExp(r'^\[![A-Za-z][\w-]*\][+-]?\s*');

/// A sum's lead, `= `.
final RegExp _sum = RegExp(r'^=(?:\s+|$)');

/// A footnote's line, `[^1]: `, and its marker in words.
final RegExp _footnoteLine = RegExp(r'^\[\^[^\]\s]+\]:\s*');
final RegExp _footnoteRef = RegExp(r'\[\^[^\]\s]+\]');

/// A link to a note, `[[Title]]` or `[[Title|words]]`: its words.
final RegExp _noteLink = RegExp(r'\[\[([^\]|]*)(?:\|([^\]]*))?\]\]');

/// A link inside the words, a place's among them: its words, and not where it goes.
final RegExp _link = RegExp(r'(?<!!)\[((?:[^\[\]]|\[[^\]]*\])*)\]\([^)]*\)');

/// A picture inside the words, a film's poster among them: not words.
final RegExp _inlinePicture = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final RegExp _bold = RegExp(r'\*\*|__');
final RegExp _leadingSpace = RegExp(r'^\s+');
final RegExp _trailingSpace = RegExp(r'\s+$');
final RegExp _endsOpen = RegExp(r'\s$');

/// A line the + beside the line draws as something other than words (docs/DESIGN.md §141): a picture, a film, a
/// place, a canvas's frame, a table's row, a rule. Its Markdown is not how an entry starts: the row read
/// `[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)` when a place was the first thing written. The row says where the
/// entry was written on its own, from its tag.
bool _drawnLine(String raw) {
  final said = lineWords(raw);
  return _picture.hasMatch(said) || _tableRow.hasMatch(raw) || _rule.hasMatch(jsTrim(raw)) || placeOfLine(raw) != null || videoOfLine(raw) != null;
}

/// The first line of an entry's own words, as plain text: past its front matter, its headings, what draws as
/// something other than words (a picture, a film, a place, a canvas's frame, a table, a rule, and fenced code, a
/// chart or a board, whole), and [filled], the template as it was filled for this entry: a line that is only the
/// template's (its question, its empty to-do) is skipped, and a line the template left open for the words to go on
/// ("**14:05** ") comes off the front of the line that goes on from it. Its own lines as they were filled, never a
/// pattern of them. A time that leads a line comes off too, for an entry made before its journal's template changed.
/// A list's or a quote's lead, a callout's kind, a sum's `=`, a footnote's marker, a card's anchor and bold come
/// off, and a link is its words: whatever the + beside the line writes first, the row reads as words or not at all.
String firstWords(String body, [String filled = '']) {
  final template = filled.split('\n').where((line) => jsTrim(line).isNotEmpty).toList();
  final only = {for (final line in template) jsTrim(line)};
  final open = [
    for (final line in template)
      if (_endsOpen.hasMatch(line)) line.replaceFirst(_leadingSpace, ''),
  ];
  final lines = body.split('\n');
  String? fence;
  for (final raw in lines.sublist(frontMatterEnd(lines))) {
    final line = jsTrim(raw);
    final mark = _fence.firstMatch(line)?.group(1);
    if (fence != null) {
      if (mark != null && mark[0] == fence[0] && mark.length >= fence.length && jsTrim(line.substring(mark.length)).isEmpty) fence = null;
      continue;
    }
    if (mark != null) {
      fence = mark;
      continue;
    }
    if (line.isEmpty || _heading.hasMatch(line) || only.contains(line) || _drawnLine(raw)) continue;
    final from = raw.replaceFirst(_leadingSpace, '');
    String? lead;
    for (final each in open) {
      if (from.startsWith(each)) {
        lead = each;
        break;
      }
    }
    // A space kept at the end, so an item's lead with nothing after it, `- `, is still a lead.
    final words = jsTrim(
      lineWords('${(lead != null ? from.substring(lead.length) : from).replaceFirst(_trailingSpace, '')} ')
          .replaceFirst(_callout, '')
          .replaceFirst(_sum, '')
          .replaceFirst(_footnoteLine, '')
          .replaceFirst(_leadingTime, '')
          .replaceAll(_footnoteRef, '')
          .replaceAllMapped(_noteLink, (m) => m.group(2) ?? m.group(1)!)
          .replaceAllMapped(_link, (m) => m.group(1)!)
          .replaceAll(_inlinePicture, '')
          .replaceAll(_bold, ''),
    );
    if (words.isNotEmpty) return words;
  }
  return '';
}

/// One entry's row.
EntryRow _rowOf(_Written page, String filled) {
  final at = _clock(page.wall);
  final tag = geoTagOf(page.note.body);
  final place = tag != null ? tagLabel(tag) : null;
  final first = firstWords(page.note.body, filled);
  final time = clockTime(at);
  final label = '${[longDay(at), time, if (place != null && place.isNotEmpty) place].join(', ')}.${first.isNotEmpty ? ' $first' : ''}';
  return EntryRow(title: page.title, id: page.note.id, wall: page.wall, day: '${at.day}', weekday: shortWeekday(at), time: time, place: place, first: first, label: label);
}

/// The written entries, newest first, and the names planned with no note yet, in the index's order: only the order,
/// with nothing written out, for the bar and the cards, which draw no rows.
({List<_Written> rows, List<String> unwritten}) _written(List<JournalPage> pages) {
  final rows = <_Written>[];
  final unwritten = <String>[];
  for (final page in pages) {
    final note = page.note;
    if (note != null) {
      rows.add((title: page.title, line: page.line, note: note, wall: stampOf(note.body, note.createdAt)));
    } else if (!isEntryTitle(page.title)) {
      unwritten.add(page.title);
    }
  }
  // Two lines of one index never share a line, so the order is whole and no tie is left to chance.
  rows.sort((a, b) => b.wall != a.wall ? b.wall.compareTo(a.wall) : b.line.compareTo(a.line));
  return (rows: rows, unwritten: unwritten);
}

/// A journal's lines with their notes, found by title as a link finds one.
List<JournalPage> pagesOf(String body, Note? Function(String title) noteOf) =>
    [for (final chapter in chaptersOf(body)) JournalPage(title: chapter.title, line: chapter.line, note: noteOf(chapter.title))];

/// The journal's written entries in months, newest first, and the names planned in it with no note yet, in the
/// index's order. [template] and [journal] are the journal's, so a row's first line is the entry's own words and not
/// the template's as it was filled for that entry.
({List<JournalMonth> months, List<String> unwritten}) monthsOf(List<JournalPage> pages, [String template = '', String journal = '']) {
  final (:rows, :unwritten) = _written(pages);
  final fill = _templateFor(template, journal);
  final months = <JournalMonth>[];
  for (final page in rows) {
    final row = _rowOf(page, fill(page));
    final at = _clock(row.wall);
    final key = '${at.year}-${at.month.toString().padLeft(2, '0')}';
    if (months.isNotEmpty && months.last.key == key) {
      months.last.entries.add(row);
    } else {
      months.add(JournalMonth(key: key, label: '${longMonth(at)} ${at.year}', entries: [row]));
    }
  }
  return (months: months, unwritten: unwritten);
}

/// A page's place in its journal as the bar and the foot walk it: the written entries oldest first, so Previous is
/// the entry written before this one and the newest is "212 of 212". A page planned and not yet written is not an
/// entry: in a notebook kept as a journal the first entry read "2 of 3", with Next a page nobody had written. A
/// notebook's place is answered as it is.
BookPlace inTimeOrder(BookPlace place, Note? Function(String title) noteOf) {
  if (!place.journal) return place;
  final rows = _written(pagesOf(place.book.body, noteOf)).rows;
  final chapters = <Chapter>[
    for (final row in rows.reversed)
      ?place.chapters.where((chapter) => chapter.title == row.title).firstOrNull,
  ];
  final current = place.at >= 0 && place.at < place.chapters.length ? place.chapters[place.at].title : null;
  final at = current == null ? -1 : chapters.indexWhere((chapter) => chapter.title == current);
  // Not among the written (a note by that name the index finds no line for): walked as the index has it.
  return at < 0 ? place : BookPlace(book: place.book, title: place.title, chapters: chapters, at: at, journal: place.journal);
}

/// Every note by its title's key, the first of two that share one, as a link finds it.
Note? Function(String title) _byTitle(Iterable<Note> notes) {
  final map = <String, Note>{};
  for (final note in notes) {
    final key = titleKey(noteTitle(note.body));
    if (key.isNotEmpty) map.putIfAbsent(key, () => note);
  }
  return (title) => map[titleKey(title)];
}

/// What a journal's card says: how many entries are written, and the newest few by when each was written, each said
/// as its day and time rather than its file's name. A page planned and not yet written is not an entry, and is not
/// counted (`JournalCard`).
class JournalCard {
  const JournalCard({required this.count, required this.newest});
  final int count;
  final List<({String title, String when})> newest;
}

const List<String> _usMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Every journal's card among [notes], by the journal's id: none where there is no journal.
Map<String, JournalCard> journalCards(List<Note> notes, [int newest = 4]) {
  final cards = <String, JournalCard>{};
  final journals = notes.where((note) => isJournalBody(note.body)).toList();
  if (journals.isEmpty) return cards;
  final noteOf = _byTitle(notes);
  for (final journal in journals) {
    final rows = _written(pagesOf(journal.body, noteOf)).rows;
    cards[journal.id] = JournalCard(
      count: rows.length,
      newest: [
        for (final row in rows.take(newest))
          (
            title: row.title,
            when: () {
              final at = _clock(row.wall);
              return '${shortWeekday(at)}, ${_usMonths[at.month - 1]} ${at.day}, ${clockTime(at)}';
            }(),
          ),
      ],
    );
  }
  return cards;
}

final RegExp _nameClock = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2})\.(\d{2})');

/// An entry's name read back as the wall clock it names (journal.dart `entryTitle`), or null for a name that is not
/// one.
int? _wallOfName(String title) {
  if (!isEntryTitle(title)) return null;
  final found = _nameClock.firstMatch(jsTrim(title))!;
  return DateTime.utc(int.parse(found.group(1)!), int.parse(found.group(2)!), int.parse(found.group(3)!), int.parse(found.group(4)!), int.parse(found.group(5)!)).millisecondsSinceEpoch;
}

const int _dayMs = 24 * 60 * 60000;

/// What an entry's bar calls the entry either side of [open]: its time when it was written the day the open one was,
/// else its day, "27 Sept". At a phone's width a side has room for about nine letters, and a name cut there,
/// "2026-09-2…", kept only what every entry shares. A name that is not an entry's is said as it is.
String sideName(String title, String open) {
  final wall = _wallOfName(title);
  if (wall == null) return title;
  final here = _wallOfName(open);
  final at = _clock(wall);
  return here != null && (here / _dayMs).floor() == (wall / _dayMs).floor() ? clockTime(at) : '${at.day} ${shortMonth(at)}';
}

/// The one month the aside lists for a journal or one of its entries: the entry's own month, newest first, or the
/// journal's newest month. Null for a journal with nothing written.
JournalMonth? asideMonth(Note journal, Iterable<Note> notes, String? openTitle) {
  final months = monthsOf(pagesOf(journal.body, _byTitle(notes)), templateOf(journal.body), noteTitle(journal.body)).months;
  if (months.isEmpty) return null;
  final key = openTitle == null ? null : titleKey(openTitle);
  for (final month in months) {
    if (month.entries.any((entry) => titleKey(entry.title) == key)) return month;
  }
  return months.first;
}

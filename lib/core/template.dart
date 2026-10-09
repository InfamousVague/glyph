/// A template filled for one note: a journal's for one entry (lib/book/journal.dart; ../glyph docs/DESIGN.md §142),
/// and a new note's from one of those it can start from (lib/notes/note_templates.dart; §144). A port of
/// `src/app/core/template.ts`, with `core/stamp.ts`'s `longDay` and `clockTime`, which it writes `{{date}}` and
/// `{{time}}` with. The double-brace placeholders are the ones Obsidian's core Templates plugin writes:
///
///     {{date}}      Monday 28 September         the home page's day, no year ([longDay])
///     {{time}}      14:05                       a 24-hour clock ([clockTime])
///     {{weekday}}   Monday
///     {{title}}     2026-09-28 14.05            the entry's name; empty for a new note, which has none yet
///     {{journal}}   Diary                       the journal's name
///     {{next-id}}   GHO-13                      the next ticket's key where the note is made (below)
///     {{date:FORMAT}} and {{time:FORMAT}}       Moment's tokens, as Obsidian takes them, and the ISO week (below)
///
/// Anything else is left as it was typed.
///
/// `{{next-id}}` is ours, for a ticket's template (docs/DESIGN.md §157): the key a notebook with `key: GHO` gives
/// its next ticket (lib/book/tickets.dart), so a Bug report made there is `id: GHO-13`. A note made where there is
/// no key has no id to give, and a front matter line that held only the placeholder, `id: "{{next-id}}"`, is left
/// out rather than written empty; anywhere else it is filled with nothing. Its quotes are YAML's, so the template's
/// own file reads in Obsidian, where a bare `{{` opens a map; an issue key needs none, so they go with it.
///
/// Words inside a format go in square brackets, as Moment and Obsidian both want them: every token letter outside
/// brackets is read, so `{{date:D MMMM at HH:mm}}` turns "at" into a meridiem and a letter ("pmt").
///
/// The week is ISO's, `GGGG` its year and `WW` its number (`{{date:GGGG-[W]WW}}` is `2026-W40`), the same
/// everywhere. Moment's own week, `gggg` and `ww`, is not read: it stays as it was typed.
///
/// And where a spoken entry's words go ([openEnd]), which is the template's last line: a line left open goes on, an
/// empty to-do starts the to-do list. And where a new note's caret goes ([firstOpenAt]), the first line left open.
/// Pure.
///
/// What differs:
/// - **The names of days and months are English, in the order en-GB writes them** ("Monday 28 September", "Sept",
///   "1st"), where the page asks the device's language through `Intl`. The app has no `intl` yet; the web's own
///   tests pin en-GB, and those are the cases ported (test/book_core/template_test.dart).
/// - The web's `FillFor` object is [fillTemplate]'s named parameters; `said` is a record of the three words.
/// - [Placing] is `capture/place.ts`'s type, written here since the recorder is a later stage of the port (8G); its
///   own file should hand this one on when it lands. What a take does with a placing (`placeTake`) is the recorder's.
/// - This was in lib/notes/note_templates.dart until the cores were ported; that file hands these on.
library;

import 'front_matter.dart' show frontMatterEnd;
import 'item_syntax.dart' show jsTrim, lineWords, listLead;
import 'day_order.dart';

// ---- core/stamp.ts ------------------------------------------------------------------------------------------------

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// en-GB's short months, as `Intl` writes them: "Sept", and no stop.
const List<String> _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Monday 28 September": the weekday, the day and the month, no year (`longDay`).
String longDay(DateTime at) => longDayWords(_weekdays[at.weekday - 1], at.day, _months[at.month - 1]);

/// "14:05": the time on a 24-hour clock (`clockTime`).
String clockTime(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

/// "Monday": the day of the week, whole.
String weekdayName(DateTime at) => _weekdays[at.weekday - 1];

/// "Mon": the day of the week, short.
String shortWeekday(DateTime at) => _weekdays[at.weekday - 1].substring(0, 3);

/// "September": the month, whole.
String longMonth(DateTime at) => _months[at.month - 1];

/// "Sept": the month, short, as en-GB writes it.
String shortMonth(DateTime at) => _shortMonths[at.month - 1];

// ---- core/template.ts ---------------------------------------------------------------------------------------------

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
/// Anything else is left as it was typed. [said] is `{{date}}`, `{{time}}` and `{{weekday}}` already written for
/// [at], by a caller that fills a year of entries (lib/book/journal_months.dart); absent, written here.
String fillTemplate(String text, {required DateTime at, String title = '', String journal = '', String? nextId, ({String date, String time, String weekday})? said}) {
  final next = nextId ?? '';
  final values = <String, String>{
    'date': said?.date ?? longDay(at),
    'time': said?.time ?? clockTime(at),
    'weekday': said?.weekday ?? weekdayName(at),
    'title': title,
    'journal': journal,
    'next-id': next,
  };
  // The id's own line first, its quotes with it, or the line gone where there is no id to give.
  return _withNextIdLines(text, next).replaceAllMapped(_placeholder, (m) {
    final name = m.group(1)!, format = m.group(2);
    if (format != null && jsTrim(format).isNotEmpty) return name == 'date' || name == 'time' ? formatStamp(at, jsTrim(format)) : m.group(0)!;
    return values[name] ?? m.group(0)!;
  });
}

/// "1st", "22nd", "11th".
String _ordinal(int n) {
  final tens = n % 100;
  final suffix = tens >= 11 && tens <= 13 ? 'th' : (const {1: 'st', 2: 'nd', 3: 'rd'}[n % 10] ?? 'th');
  return '$n$suffix';
}

/// The ISO week [at] falls in: its year and its number. A week is Monday to Sunday and belongs to the year its
/// Thursday is in, so 1 January 2021, a Friday, is in 2020's week 53, and 30 December 2024 is in 2025's week 1.
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

/// The list a note with none yet is started with (`Placing`'s `fresh`).
enum FreshList { task, bullet, number }

/// Where a take's words go in a note: its end, its lists, or a lane of its board (`capture/place.ts` `Placing`).
sealed class Placing {
  const Placing();

  /// The object the web has for it, key for key.
  Map<String, Object?> toJson();

  @override
  bool operator ==(Object other) => other is Placing && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;

  @override
  String toString() => 'Placing(${toJson()})';
}

class PlacingEnd extends Placing {
  const PlacingEnd({this.lead});

  /// The note's last line as it was left open, taken off the note and written again before the take: on the same
  /// line when the take starts with a paragraph, on a line of its own above anything else. Absent, the end as it
  /// always was.
  final String? lead;

  @override
  Map<String, Object?> toJson() => {'kind': 'end', if (lead != null) 'lead': lead};
}

class PlacingLists extends Placing {
  const PlacingLists({required this.task, required this.heading, required this.fresh});

  /// A to-do was said, or the title says to-dos: only the to-do lists count, and a new list is one.
  final bool task;

  /// A heading said for it ("under Electrical"): the list under that heading.
  final String? heading;

  /// The note has no list yet: the one to start, or null for none (the words go at the end). Numbered for a journal
  /// whose template ends in an empty numbered item, "1. " ([openEnd]).
  final FreshList? fresh;

  @override
  Map<String, Object?> toJson() => {'kind': 'lists', 'task': task, 'heading': heading, 'fresh': fresh?.name};
}

/// A lane of a board, by name, for "add … to Doing" said on the board's own Speak (boards.dart).
class PlacingLane extends Placing {
  const PlacingLane(this.lane);
  final String lane;

  @override
  Map<String, Object?> toJson() => {'kind': 'lane', 'lane': lane};
}

final RegExp _digit = RegExp(r'\d');
final RegExp _endsOpen = RegExp(r'\s$');

/// Where a spoken entry's words go, and the entry as it is written before they come, from the filled template's
/// last line (`openEnd`):
///
/// - an empty list item (`- [ ] `, `- `, `1. `): the entry without it, and the words as that list's items, so a
///   day's to-dos said aloud are to-dos;
/// - words left open with a space (`**14:05** `): the entry without the line, and the words going on from it, so a
///   spoken entry still starts with its time;
/// - anything else: the entry as it is, and the words at its end.
({String base, Placing placing}) openEnd(String words) {
  final lines = words.split('\n');
  final last = lines.last;
  final rest = lines.sublist(0, lines.length - 1).join('\n');
  final lead = listLead(last);
  if (lead != null && jsTrim(last.substring(lead.wordsAt)).isEmpty) {
    final task = lead.done != null;
    final fresh = task ? FreshList.task : (_digit.hasMatch(lead.marker) ? FreshList.number : FreshList.bullet);
    return (base: rest, placing: PlacingLists(task: task, heading: null, fresh: fresh));
  }
  if (jsTrim(last).isNotEmpty && _endsOpen.hasMatch(last)) return (base: rest, placing: PlacingEnd(lead: last));
  return (base: words, placing: const PlacingEnd());
}

final RegExp _openHeading = RegExp(r'^ {0,3}#{1,6} +$');

/// Where a new note's caret goes in its filled words: the end of the first line left open, or the end of the words
/// (`firstOpenAt`). A line is open when it is a heading with no words (`# `), a list's, a to-do's or a quote's lead
/// with no words (`- `, `- [ ] `, `1. `, `> `), or words ending in a space (`With `), which is [openEnd]'s own rule
/// for a line left open. A blank line is not open. So A day's caret is in its to-do, A meeting's after "With ", and
/// the rest in their heading.
int firstOpenAt(String words) {
  var at = 0;
  for (final line in words.split('\n')) {
    final heading = _openHeading.hasMatch(line);
    // A lead with nothing after it: `- `, `- [ ] `, `1. `, `> `.
    final lead = jsTrim(line).isNotEmpty && lineWords(line).isEmpty;
    final leftOpen = jsTrim(line).isNotEmpty && _endsOpen.hasMatch(line);
    if (heading || lead || leftOpen) return at + line.length;
    at += line.length + 1;
  }
  return words.length;
}

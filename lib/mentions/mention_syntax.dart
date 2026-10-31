/// Mentions as a note writes them (Matt, 2026-10-30: "add all 12", the plain-Markdown list's @mentions of people and
/// dates): an at sign before a person's handle, `@sam`, or before a day, `@2026-11-06`. Plain words in any other app,
/// and the same at sign every chat and tracker already writes before a name.
///
///     Ask @sam to look at the login loop by @2026-11-06
///
/// - **A person** is `@` after the line's start, a space or an opening bracket, then a letter, then letters, digits,
///   `_`, `.` or `-`, as a list item's assignee is (lib/core/task_fields.dart): the same grammar, so `@sam` on a to-do
///   is its assignee and a mention at once. A trailing `.` or `-` is the sentence's ("Ask @sam."), `sam@example.com` is
///   an address, and `@sam@mastodon.social` is too.
/// - **A day** is `@` and a day as a note writes one, `@2026-11-06`, one the calendar has. What is typed as words -
///   `@today`, `@tomorrow`, `@next friday`, `@in 3 days`, `@nov 6` - is written as the day once the space after it is
///   typed ([dayOfWords], lib/editor/items/mentions.dart), so the note says the day it meant on every later day.
///   `@today`, `@tomorrow` and `@yesterday` left as words (written in another app) read as days, never as people.
/// - **Nowhere quiet**: not in code, an address, a note link's title, maths, HTML (lib/core/blanks_syntax.dart
///   `quietRanges`), a redaction's `@@…@@`, the front matter or a fenced block.
///
/// Pure, so every shape of line is a test (test/mentions/mention_syntax_test.dart).
library;

import '../core/blanks_syntax.dart' show quietRanges;
import '../core/days.dart' show isIsoDay, isoDay, isoDayAfter;
import '../core/front_matter.dart' show frontMatterEnd;

/// A person or a day.
enum MentionKind { person, day }

/// One mention in a text: where its at sign is, where it ends, and what it names.
class Mention {
  const Mention({required this.kind, required this.from, required this.to, required this.value});

  final MentionKind kind;

  /// The at sign, counted from the offset given.
  final int from;
  final int to;

  /// A person's handle as written, without the at sign; a day as `2026-11-06` (a word like `today` is kept as the
  /// word, and [dayOn] says which day it is).
  final String value;

  bool get person => kind == MentionKind.person;

  /// The day a day's mention names, read on [today]: its own day, or a word's, by the clock.
  String? dayOn(DateTime today) => kind == MentionKind.day ? (isIsoDay(value) ? value : dayOfWords(value, today)) : null;

  @override
  bool operator ==(Object other) => other is Mention && other.kind == kind && other.from == from && other.to == to && other.value == value;

  @override
  int get hashCode => Object.hash(kind, from, to, value);

  @override
  String toString() => 'Mention(${kind.name} $value, $from, $to)';
}

/// An at sign where a mention may open, and the run of handle characters after it.
final RegExp _at = RegExp(r'(^|[\s([{])@([\p{L}\p{N}][\p{L}\p{N}_.-]*)', unicode: true);
final RegExp _letter = RegExp(r'^\p{L}', unicode: true);
final RegExp _trailingStops = RegExp(r'[.-]+$');
final RegExp _isoRun = RegExp(r'^\d{4}-\d{2}-\d{2}');

/// A redaction, `@@…@@`, whose words are hidden and are no one's to mention (task_fields.dart's own rule).
final RegExp _redaction = RegExp(r'@@[^\s@](?:[^\n@]|@(?!@))*?@@');

/// The words a day may be left as and still read as a day, never a person.
const Set<String> dayWords = {'today', 'tomorrow', 'yesterday'};

/// The mentions in one line of words, counted from [offset], in the order they are written. Quiet places are passed
/// over; so are the at signs inside a redaction.
List<Mention> mentionsIn(String text, [int offset = 0]) {
  if (!text.contains('@')) return const [];
  final quiet = <({int from, int to})>[...quietRanges(text), for (final found in _redaction.allMatches(text)) (from: found.start, to: found.end)];
  bool hushed(int at) => quiet.any((range) => at >= range.from && at < range.to);
  final out = <Mention>[];
  for (final found in _at.allMatches(text)) {
    final at = found.start + found.group(1)!.length;
    if (hushed(at)) continue;
    final run = found.group(2)!;
    final iso = _isoRun.firstMatch(run)?.group(0);
    if (iso != null) {
      // A day: the ten characters, and only where nothing of a handle runs on from them.
      if (!isIsoDay(iso)) continue;
      final end = at + 1 + iso.length;
      if (end < text.length && RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(text[end])) continue;
      out.add(Mention(kind: MentionKind.day, from: offset + at, to: offset + end, value: iso));
      continue;
    }
    if (!_letter.hasMatch(run)) continue;
    final handle = run.replaceFirst(_trailingStops, '');
    final end = at + 1 + handle.length;
    // A name run on into an at sign (`@sam@mastodon.social`) is an address, not a person.
    if (end < text.length && text[end] == '@') continue;
    if (handle.isEmpty) continue;
    final word = handle.toLowerCase();
    out.add(Mention(kind: dayWords.contains(word) ? MentionKind.day : MentionKind.person, from: offset + at, to: offset + end, value: handle));
  }
  return out;
}

/// A fenced block's opening and closing line.
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// One mention in a note, with its line.
class NoteMention {
  const NoteMention({required this.line, required this.text, required this.mention});

  /// Its line in the body, counting from 1.
  final int line;

  /// The line's words, as written.
  final String text;
  final Mention mention;

  @override
  String toString() => 'NoteMention($line, $mention)';
}

/// The mentions of a whole note, line by line: not in the front matter, nor in a fenced block.
List<NoteMention> mentionsInBody(String body) {
  if (!body.contains('@')) return const [];
  final lines = body.split('\n');
  final out = <NoteMention>[];
  var fenced = false;
  for (var index = frontMatterEnd(lines); index < lines.length; index += 1) {
    final text = lines[index];
    if (_fence.hasMatch(text)) {
      fenced = !fenced;
      continue;
    }
    if (fenced || !text.contains('@')) continue;
    for (final mention in mentionsIn(text)) {
      out.add(NoteMention(line: index + 1, text: text, mention: mention));
    }
  }
  return out;
}

/// A handle as two mentions of one person are compared: lower case.
String handleKey(String handle) => handle.toLowerCase();

/// The person a day's mention is for, where one is written right beside it - `@sam @2026-11-06` or `@2026-11-06
/// @sam`, nothing but spaces between - else null: the day is then the writer's own.
Mention? personBeside(String text, List<Mention> mentions, Mention day, [int offset = 0]) {
  final index = mentions.indexOf(day);
  if (index < 0) return null;
  bool blankBetween(int from, int to) => text.substring(from - offset, to - offset).trim().isEmpty;
  if (index > 0) {
    final before = mentions[index - 1];
    if (before.person && blankBetween(before.to, day.from)) return before;
  }
  if (index + 1 < mentions.length) {
    final after = mentions[index + 1];
    if (after.person && blankBetween(day.to, after.from)) return after;
  }
  return null;
}

/// Whether [before] ends with a person's mention, nothing but spaces after it: `Ask @sam ` - so a day written next
/// is theirs, and needs no other name beside it.
bool personEnds(String before) {
  final found = mentionsIn(before);
  if (found.isEmpty) return false;
  final last = found.last;
  return last.person && before.substring(last.to).trim().isEmpty;
}

/// A day as the editor writes it when it is typed or picked: `@2026-11-06`, or `@matt @2026-11-06` in a team's note
/// (docs/MARKDOWN_FIRST.md §11, decision 18; Matt, 2026-10-31), so whose day it is stands in the words themselves
/// rather than in who happened to type it. [owner] is the writer's handle in a team's note, null in a note of their
/// own; a person already named right before the day ([personEnds] of [before], the line up to the at sign) is the
/// one it is for, and no name is added.
String signedDay(String day, {String? owner, String before = ''}) {
  if (owner == null || owner.isEmpty || personEnds(before)) return '@$day';
  return '@$owner @$day';
}

// ---- days typed as words ------------------------------------------------------------------------------------------

const List<String> _weekdays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
const List<String> _months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];

/// A weekday from its name or its first three letters (`fri`), Monday 1; null for anything else.
int? _weekday(String word) {
  for (final (index, name) in _weekdays.indexed) {
    if (word == name || (word.length >= 3 && name.startsWith(word))) return index + 1;
  }
  return null;
}

/// A month from its name or its first three letters (`nov`), January 1; null for anything else.
int? _month(String word) {
  for (final (index, name) in _months.indexed) {
    if (word == name || (word.length >= 3 && name.startsWith(word))) return index + 1;
  }
  return null;
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _count = RegExp(r'^(\d{1,3})$');
final RegExp _ordinal = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?$');

/// The day [words] name, read on [today]: `today`, `tomorrow`, `yesterday`; a weekday (`friday`, `fri`: the next
/// one after today), `this friday` (this week's, today counting), `next friday` (next week's, the week from Monday);
/// `next week` (its Monday), `next month` (its first); `in 3 days`, `in 2 weeks`; `nov 6`, `6 november`, `november
/// 6th` (this year's, or next year's once it has passed); and a day as written, `2026-11-06`. Null for anything
/// else, so a person's name is never taken for a day.
String? dayOfWords(String words, DateTime today) {
  final said = words.trim().toLowerCase().split(_spaces).where((word) => word.isNotEmpty).toList();
  if (said.isEmpty || said.length > 3) return null;
  final day = isoDay(today);
  String after(int days) => isoDayAfter(day, days)!;
  final weekdayNow = today.weekday;
  if (said.length == 1) {
    final word = said.single;
    if (isIsoDay(word)) return word;
    switch (word) {
      case 'today' || 'tod':
        return day;
      case 'tomorrow' || 'tmr' || 'tmrw':
        return after(1);
      case 'yesterday':
        return after(-1);
    }
    final weekday = _weekday(word);
    if (weekday != null) {
      final ahead = (weekday - weekdayNow) % 7;
      return after(ahead == 0 ? 7 : ahead);
    }
    return null;
  }
  final first = said.first;
  if (said.length == 2 && (first == 'this' || first == 'next')) {
    final second = said[1];
    if (second == 'week') return first == 'next' ? after(8 - weekdayNow) : null;
    if (second == 'month') {
      if (first != 'next') return null;
      final next = DateTime(today.year, today.month + 1, 1);
      return isoDay(next);
    }
    final weekday = _weekday(second);
    if (weekday == null) return null;
    // This week's, Monday to Sunday, today counting; next week's, from the Monday after.
    return first == 'this' ? (weekday >= weekdayNow ? after(weekday - weekdayNow) : null) : after(8 - weekdayNow + weekday - 1);
  }
  if (said.length == 3 && first == 'in') {
    final count = _count.firstMatch(said[1]);
    if (count == null) return null;
    final n = int.parse(count.group(1)!);
    final unit = said[2];
    if (unit == 'day' || unit == 'days') return after(n);
    if (unit == 'week' || unit == 'weeks') return after(7 * n);
    return null;
  }
  if (said.length == 2) {
    // `nov 6` or `6 nov`.
    var month = _month(first);
    var number = _ordinal.firstMatch(said[1]);
    if (month == null) {
      month = _month(said[1]);
      number = _ordinal.firstMatch(first);
    }
    if (month == null || number == null) return null;
    final date = int.parse(number.group(1)!);
    String? on(int year) {
      final at = DateTime(year, month!, date);
      return at.month == month && at.day == date ? isoDay(at) : null;
    }

    final thisYear = on(today.year);
    if (thisYear == null) return null;
    return thisYear.compareTo(day) < 0 ? on(today.year + 1) : thisYear;
  }
  return null;
}

/// The words after an at sign that end just before [at] in [line], and where their at sign is, where they could be a
/// day typed as words: one to three words, nothing but letters, digits and spaces, the at sign opening a mention.
/// Null where there are none.
({int from, String words})? dayWordsBefore(String line, int at) {
  final before = line.substring(0, at);
  final sign = before.lastIndexOf('@');
  if (sign < 0) return null;
  if (sign > 0 && !RegExp(r'[\s([{]').hasMatch(before[sign - 1])) return null;
  final words = before.substring(sign + 1);
  if (words.isEmpty || words.startsWith(' ') || !RegExp(r'^[\p{L}\p{N} -]+$', unicode: true).hasMatch(words)) return null;
  if (words.split(' ').length > 3) return null;
  return (from: sign, words: words);
}

/// A day's mention as it is shown: "Today", "Tomorrow", "Yesterday", the weekday within the week either side
/// ("Friday", "Last Monday"), else "Nov 6", and with its year where it is not this one ("Nov 6, 2027").
String dayShown(String iso, DateTime today) {
  final day = isoDay(today);
  final apart = _daysFrom(day, iso);
  if (apart == 0) return 'Today';
  if (apart == 1) return 'Tomorrow';
  if (apart == -1) return 'Yesterday';
  final parts = iso.split('-');
  final year = int.parse(parts[0]), month = int.parse(parts[1]), date = int.parse(parts[2]);
  final weekday = _weekdays[DateTime(year, month, date).weekday - 1];
  final named = '${weekday[0].toUpperCase()}${weekday.substring(1)}';
  if (apart != null && apart > 1 && apart < 7) return named;
  if (apart != null && apart < -1 && apart > -7) return 'Last $named';
  const short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final shown = '${short[month - 1]} $date';
  return year == today.year ? shown : '$shown, $year';
}

int? _daysFrom(String from, String to) {
  final a = DateTime.tryParse(from), b = DateTime.tryParse(to);
  if (a == null || b == null) return null;
  return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}

/// Whether a day has passed, on [today]: before today's day, not today itself.
bool dayPast(String iso, DateTime today) => iso.compareTo(isoDay(today)) < 0;

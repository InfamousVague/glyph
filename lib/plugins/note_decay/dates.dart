/// Dates in a note's sentences, and whether a sentence speaks of one as still ahead (docs/NOTE_DECAY.md §1.1, the
/// `date` signal; Matt, 2026-11-02: "an old date" among the things that make a page "may be out of date"). No model:
/// a list of words that look ahead and a list that look back, so "Billing ships on Nov 1" is marked once Nov 1 has
/// passed and "Billing shipped on Nov 1" never is. Pure, and each word is a test (test/plugins/note_decay/).
library;

import 'package:flutter/foundation.dart';

/// One date found in a line: where it is, what it says, and the day it names.
@immutable
class FoundDate {
  const FoundDate({required this.start, required this.end, required this.text, required this.day});

  /// The date's span in the line, from 0.
  final int start;
  final int end;

  /// The date as the line writes it: "Nov 1", "2026-11-01".
  final String text;

  /// The day it names (midnight, local).
  final DateTime day;
}

const Map<String, int> _months = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, 'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7, //
  'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
};

const String _monthWords = r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

/// 2026-11-01.
final RegExp _iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');

/// Nov 1, November 1st, Nov 1, 2026.
final RegExp _monthDay = RegExp('\\b$_monthWords\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s+(\\d{4})\\b)?', caseSensitive: false);

/// 1 Nov, 1st November 2026.
final RegExp _dayMonth = RegExp('\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?$_monthWords\\b\\.?(?:,?\\s+(\\d{4})\\b)?', caseSensitive: false);

/// The year a date without one is read in: the year of [edited], or the next where that would put it more than two
/// months before the edit (a note written in December about "Jan 4").
int _yearFor(int month, int day, DateTime edited) {
  final same = DateTime(edited.year, month, day);
  return same.isBefore(DateTime(edited.year, edited.month, edited.day).subtract(const Duration(days: 61))) ? edited.year + 1 : edited.year;
}

DateTime? _day(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final made = DateTime(year, month, day);
  return made.month == month && made.day == day ? made : null;
}

/// Every date in [line], in order, overlaps left out. A date without a year is read by [edited] (see [_yearFor]).
List<FoundDate> datesIn(String line, {required DateTime edited}) {
  final found = <FoundDate>[];
  bool free(int start, int end) => found.every((f) => end <= f.start || start >= f.end);
  for (final match in _iso.allMatches(line)) {
    final day = _day(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
    if (day != null) found.add(FoundDate(start: match.start, end: match.end, text: match[0]!, day: day));
  }
  for (final match in _monthDay.allMatches(line)) {
    if (!free(match.start, match.end)) continue;
    final month = _months[match[1]!.toLowerCase()]!, dayOf = int.parse(match[2]!);
    final year = match[3] == null ? _yearFor(month, dayOf, edited) : int.parse(match[3]!);
    final day = _day(year, month, dayOf);
    if (day != null) found.add(FoundDate(start: match.start, end: match.end, text: match[0]!, day: day));
  }
  for (final match in _dayMonth.allMatches(line)) {
    if (!free(match.start, match.end)) continue;
    final month = _months[match[2]!.toLowerCase()]!, dayOf = int.parse(match[1]!);
    final year = match[3] == null ? _yearFor(month, dayOf, edited) : int.parse(match[3]!);
    final day = _day(year, month, dayOf);
    if (day != null) found.add(FoundDate(start: match.start, end: match.end, text: match[0]!, day: day));
  }
  found.sort((a, b) => a.start - b.start);
  return found;
}

/// The words that look ahead: a sentence with one speaks of its date as still to come.
const List<String> aheadWords = [
  'will', 'shall', 'going to', 'is due', 'are due', 'due', 'ships', 'ship', 'launches', 'launch', 'lands', 'releases', 'starts', 'opens', 'goes live', //
  'go live', 'planned', 'scheduled', 'expected', 'upcoming', 'targeting', 'target', 'aim to', 'aims to', 'by', 'until', 'next', 'begins', 'kicks off', 'deadline',
];

/// The words that look back: a sentence with one is about what happened, and is never marked.
const List<String> behindWords = [
  'shipped', 'launched', 'released', 'landed', 'was', 'were', 'did', 'happened', 'ago', 'done', 'finished', 'completed', 'went live', 'started', 'began', 'kicked off',
  'had', 'closed', 'merged', 'delivered',
];

RegExp _wordsPattern(List<String> words) => RegExp('(?<![\\w])(?:${words.map((w) => RegExp.escape(w).replaceAll(' ', r'\s+')).join('|')})(?![\\w])', caseSensitive: false);

final RegExp _ahead = _wordsPattern(aheadWords);
final RegExp _behind = _wordsPattern(behindWords);

/// "we'll", "it'll": a word's own ending, which [aheadWords]' edges cannot hold.
final RegExp _willSaid = RegExp(r"\w'll\b", caseSensitive: false);

/// Whether [sentence] speaks of what it says as ahead: a word of [aheadWords], and none of [behindWords].
bool looksAhead(String sentence) {
  final plain = sentence.replaceAll('’', "'");
  return (_ahead.hasMatch(plain) || _willSaid.hasMatch(plain)) && !_behind.hasMatch(plain);
}

/// The sentence of [line] round [at]: from the last `.`, `!`, `?` or `;` before it to the next after.
String sentenceAt(String line, int at) {
  var start = 0, end = line.length;
  for (var i = at - 1; i >= 0; i--) {
    final c = line[i];
    // A full stop between digits or right after a month's short name is not a sentence's end.
    if ((c == '!' || c == '?' || c == ';') || (c == '.' && i + 1 < line.length && line[i + 1] == ' ' && !_abbrevBefore(line, i))) {
      start = i + 1;
      break;
    }
  }
  for (var i = at; i < line.length; i++) {
    final c = line[i];
    if (c == '!' || c == '?' || c == ';' || (c == '.' && (i + 1 == line.length || line[i + 1] == ' ') && !_abbrevBefore(line, i))) {
      end = i + 1;
      break;
    }
  }
  return line.substring(start, end).trim();
}

final RegExp _shortMonth = RegExp(r'(?:jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)$', caseSensitive: false);

bool _abbrevBefore(String line, int dot) => _shortMonth.hasMatch(line.substring(0, dot));

/// "Nov 1", or "Nov 1, 2025" for a day in another year than [now]'s: how a mark names a day.
String dayWords(DateTime day, {DateTime? now}) {
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final words = '${names[day.month - 1]} ${day.day}';
  return day.year == (now ?? DateTime.now()).year ? words : '$words, ${day.year}';
}

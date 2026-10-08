/// A to-do's fields, said (docs/DESIGN.md §158): "call the plumber due Friday", "fix the login loop, high priority",
/// "book the venue for Sam". A port of `src/app/capture/spoken/fields.ts`.
///
/// While a list item is being spoken, the words that give it a due day, a priority or a person are taken off its
/// words and written as the field, through the one writer (core/task_fields.dart, §156), so the item reads
/// `- [ ] Call the plumber 📅 2026-10-02` and Obsidian Tasks has its due date:
///
///     due Friday, due tomorrow, due next week, due the third of October   📅 and the day (core/day_words.dart)
///     high priority, highest priority, top priority, low priority, urgent ⏫ 🔺 🔺 🔽 ⏫
///     for Sam, assigned to Sam, assign it to Sam Ortiz                     @Sam, @Sam-Ortiz
///
/// High precision, as every spoken rule is (capture/markdown.dart): a missed field is still words, and a false one
/// takes words away. So a cue is read only at the end of the item, where a field is said last, and any of them in any
/// order ("due Friday, high priority, for Sam"); in the middle of an item they are its words. "Due" needs a day it
/// can read after it, so "the rent is due" stays words. A person needs a capital - Whisper writes a name with one - so
/// "for now" and "for dinner" are words, and not a weekday, a month or a day ("for Friday" is words, since it is
/// when, not who), and "for" after a thing given ("a present for Sam", "flights for Lisbon") is who it is for or
/// where, not who does it. A person is never read from a sentence on its own, only from the end of an item.
///
/// Pure. `today` is the person's day (core/days.dart), which the caller reads from the clock.
///
/// What differs: a priority's name is a plain `String`, as core/task_fields.dart holds the web's `PriorityName`.
library;

import '../../core/day_words.dart';
import '../../core/item_syntax.dart';
import '../../core/task_fields.dart';

/// What an item's words say of its fields (`SpokenFields`).
class SpokenFields {
  const SpokenFields({required this.words, required this.due, required this.priority, required this.people});

  /// The item's words with the cues taken off; '' when it was nothing but cues.
  final String words;
  final String? due;

  /// `highest`, `high`, `medium`, `low` or `lowest` (the web's `PriorityName`).
  final String? priority;

  /// The people, as said: "Sam", "Sam Ortiz".
  final List<String> people;

  @override
  bool operator ==(Object other) =>
      other is SpokenFields && other.words == words && other.due == due && other.priority == priority && _same(other.people, people);

  @override
  int get hashCode => Object.hash(words, due, priority, Object.hashAll(people));

  @override
  String toString() => 'SpokenFields(words: $words, due: $due, priority: $priority, people: $people)';
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What may come between the item's words and a cue: a comma, an "and", an "it's".
const String _join =
    r"(?:^|[\s,;]+)(?:and\s+)?(?:(?:it['’]?s|it\s+is|is|that['’]?s|which\s+is|make\s+it|mark\s+it(?:\s+as)?)\s+)?(?:a\s+)?";

/// A priority said at the end: "high priority", "priority high", "top priority", "urgent".
const Map<String, String> _priorityWords = {'highest': 'highest', 'top': 'highest', 'high': 'high', 'medium': 'medium', 'low': 'low', 'lowest': 'lowest'};
final RegExp _priorityAfter = RegExp('$_join(highest|top|high|medium|lowest|low)(?:[\\s-]+)priority\$', caseSensitive: false);
final RegExp _priorityBefore = RegExp('${_join}priority[\\s,:]+(highest|top|high|medium|lowest|low)\$', caseSensitive: false);
final RegExp _urgent = RegExp('${_join}urgent\$', caseSensitive: false);

/// "For Sam", "assigned to Sam Ortiz", "assign it to Sam": a name of one or two capitalised words at the end. The
/// words before it in either case, as Whisper starts a sentence with a capital; the name only with one.
final RegExp _person = RegExp(
  r"(?:^|[\s,;]+)(?:([Ff]or)|[Aa]ssigned\s+to|[Aa]ssign(?:\s+(?:it|this))?\s+to)\s+(\p{Lu}[\p{L}'’-]+(?:\s+\p{Lu}[\p{L}'’-]+)?)$",
  unicode: true,
);

/// Capitalised words that are not people: days and months, and what a "for" says about when.
final Set<String> _notPeople = [
  'monday tuesday wednesday thursday friday saturday sunday',
  'january february march april may june july august september october november december',
  'today tomorrow tonight now later next this that the then me us them everyone everybody all',
  'christmas easter halloween thanksgiving',
].join(' ').split(' ').toSet();

/// Things given or booked: "a present for Sam" is Sam's present, not Sam's to do.
final Set<String> _given =
    'gift gifts present presents card cards cake flowers something anything birthday party dinner lunch breakfast ticket tickets flight flights train trains trip hotel room table visa'
        .split(' ')
        .toSet();

final RegExp _due = RegExp('${_join}due\\s+', caseSensitive: false);

/// The day after "due", at the end: the last "due" whose words after it are all a day.
({int at, String day})? _dueAtEnd(String text, String today) {
  final all = _due.allMatches(text).toList();
  for (final found in all.reversed) {
    final day = dayOfWords(text.substring(found.end), today);
    if (day != null && day.isNotEmpty) return (at: found.start, day: day);
  }
  return null;
}

/// A priority said at the end, and where its words start.
({int at, String priority})? _priorityAtEnd(String text) {
  final named = _priorityAfter.firstMatch(text) ?? _priorityBefore.firstMatch(text);
  if (named != null) return (at: named.start, priority: _priorityWords[(named.group(1) ?? '').toLowerCase()] ?? 'high');
  final urgent = _urgent.firstMatch(text);
  return urgent != null ? (at: urgent.start, priority: 'high') : null;
}

final RegExp _space = RegExp(r'\s+');
final RegExp _wordBefore = RegExp(r'(\p{L}+)[\s,;]*$', unicode: true);

/// A person said at the end, and where the words that give them start.
({int at, String name})? _personAtEnd(String text) {
  final found = _person.firstMatch(text);
  if (found == null) return null;
  final name = found.group(2) ?? '';
  if (name.split(_space).any((word) => _notPeople.contains(word.toLowerCase()))) return null;
  if ((found.group(1) ?? '').isNotEmpty) {
    final before = _wordBefore.firstMatch(text.substring(0, found.start))?.group(1)?.toLowerCase() ?? '';
    if (_given.contains(before)) return null;
  }
  return (at: found.start, name: name);
}

final RegExp _stopsAtEnd = RegExp(r'[\s.!?]+$');
final RegExp _betweenCues = RegExp(r'[\s,;:.]+$');
final RegExp _joinsAtEnd = RegExp(r'[\s,;:]+$');

/// The cues at the end of [said] read off it, last first, in whatever order they were said, each kind once: the
/// item's words before them, and what they set. Words with no cue at their end come back as they are.
SpokenFields spokenFields(String said, String today) {
  var words = said.replaceFirst(_stopsAtEnd, '');
  String? outDue;
  String? outPriority;
  final people = <String>[];
  for (;;) {
    words = words.replaceFirst(_betweenCues, '');
    final due = outDue == null ? _dueAtEnd(words, today) : null;
    if (due != null) {
      outDue = due.day;
      words = words.substring(0, due.at);
      continue;
    }
    final priority = outPriority == null ? _priorityAtEnd(words) : null;
    if (priority != null) {
      outPriority = priority.priority;
      words = words.substring(0, priority.at);
      continue;
    }
    final person = people.isEmpty ? _personAtEnd(words) : null;
    if (person != null) {
      people.add(person.name);
      words = words.substring(0, person.at);
      continue;
    }
    break;
  }
  return SpokenFields(words: words.replaceFirst(_joinsAtEnd, '').trim(), due: outDue, priority: outPriority, people: people);
}

/// Whether a sentence said on its own is nothing but a due day or a priority - "Due Friday.", "High priority." - and
/// so belongs to the item said a breath before it. A person on their own is not: "For Sam." after an item may be who
/// it is for, or the start of something else.
bool onlyFields(String sentence, String today) {
  final read = spokenFields(sentence, today);
  return read.words == '' && read.people.isEmpty && (read.due != null || read.priority != null);
}

/// An item - its words, or its whole line - with the cues at the end of its words written as its fields. An item
/// that is nothing but cues keeps its words: "Urgent." on its own is a thing said, not an empty to-do.
String withSpokenFields(String item, String today) {
  final lead = listLead(item);
  final head = lead != null ? item.substring(0, lead.wordsAt) : '';
  final read = spokenFields(item.substring(head.length), today);
  if (read.words.isEmpty || (read.due == null && read.priority == null && read.people.isEmpty)) return item;
  var line = '$head${read.words}';
  for (final person in read.people) {
    line = withAssignee(line, person);
  }
  if (read.priority != null) line = withField(line, 'priority', read.priority);
  if (read.due != null) line = withField(line, 'due', read.due);
  return line;
}

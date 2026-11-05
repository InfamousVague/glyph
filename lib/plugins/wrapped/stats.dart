/// Wrapped's counts, made from the notes alone with no AI (docs/WRAPPED.md, "The counts"): how many notes were written
/// in the period and how many words, the busiest month, day and hour, the longest run of days with a note, the notes
/// most linked to, the top tags and folders, to-dos done and still open, meetings and recordings, and how many plugins
/// are on. Pure and quick: made again whenever the story is opened, never kept.
///
/// A note counts for the period it was written in (its `createdAt`); a day counts for a streak when a note was written
/// or last edited on it, the two times the library keeps. Notes in the Trash are left out; archived ones count, since
/// they were written.
library;

import 'package:flutter/foundation.dart';

import '../../core/front_matter.dart' show frontMatterValue;
import '../../core/link_index.dart' show linksIn;
import '../../core/note.dart';
import '../../core/note_text.dart' show noteTitle;
import '../../core/properties.dart' show propertyList;
import '../../core/tags.dart' show tagsIn;
import '../../core/title_key.dart' show titleKey;
import '../cleanup/text.dart' show wordsOf;
import 'todos.dart';

/// The span a Wrapped is made for.
enum WrappedPeriod {
  year('year', 'This year'),
  last12('last12', 'Last 12 months'),
  all('all', 'All time');

  const WrappedPeriod(this.wire, this.label);

  /// Its word in the state file and the analytics.
  final String wire;
  final String label;

  static WrappedPeriod of(Object? wire) => values.where((p) => p.wire == wire).firstOrNull ?? year;

  /// Where it starts, for [now]: null for all time.
  DateTime? startFor(DateTime now) => switch (this) {
        year => DateTime(now.year),
        last12 => DateTime(now.year - 1, now.month, now.day),
        all => null,
      };

  /// What the story calls it: "2026", "the last 12 months", "all time".
  String wordsFor(DateTime now) => switch (this) {
        year => '${now.year}',
        last12 => 'the last 12 months',
        all => 'all time',
      };
}

const List<String> monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const List<String> dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "9 am", "12 pm", "11 pm".
String hourWords(int hour) => '${hour % 12 == 0 ? 12 : hour % 12} ${hour < 12 ? 'am' : 'pm'}';

/// A name and how many, for the story's lists.
typedef Counted = ({String name, int count});

/// One note and how many notes link to it.
typedef Linked = ({String id, String title, int links});

/// The counts for one period.
@immutable
class WrappedStats {
  const WrappedStats({
    required this.period,
    required this.notes,
    required this.words,
    required this.edited,
    this.busiestMonth,
    this.busiestDay,
    this.busiestHour,
    this.longestStreak = 0,
    this.mostLinked = const [],
    this.topTags = const [],
    this.topFolders = const [],
    this.todosDone = 0,
    this.todosOpen = 0,
    this.meetings = 0,
    this.recordings = 0,
    this.plugins = 0,
  });

  final WrappedPeriod period;

  /// Notes written in the period, and their words.
  final int notes;
  final int words;

  /// Notes last edited in it, whenever they were written.
  final int edited;

  /// The month (1 to 12, with its year), weekday (1 Monday to 7) and hour (0 to 23) most notes were written in.
  final ({int year, int month, int count})? busiestMonth;
  final ({int day, int count})? busiestDay;
  final ({int hour, int count})? busiestHour;

  /// The most days in a row with a note written or edited.
  final int longestStreak;
  final List<Linked> mostLinked;
  final List<Counted> topTags;
  final List<Counted> topFolders;

  /// To-dos in the period's notes.
  final int todosDone;
  final int todosOpen;
  final int meetings;
  final int recordings;

  /// Plugins on now.
  final int plugins;

  bool get isEmpty => notes == 0 && edited == 0;

  String get busiestMonthWords => busiestMonth == null ? '' : monthNames[busiestMonth!.month - 1];
  String get busiestDayWords => busiestDay == null ? '' : '${dayNames[busiestDay!.day - 1]}s';
  String get busiestHourWords => busiestHour == null ? '' : hourWords(busiestHour!.hour);
}

/// The note's own words, not counting its front matter's: what "words written" counts.
int noteWords(String body) => wordsOf(body.replaceFirst(RegExp(r'^---\n[\s\S]*?\n---\n'), '')).length;

/// Whether [note] is a meeting's (`meeting:` in its front matter, as meeting_mark.dart writes it).
bool isMeetingNote(Note note) => (frontMatterValue(note.body, 'meeting')?.trim() ?? '').isNotEmpty;

/// Whether [note] was spoken: made by the recorder, or holding its tape.
bool isRecordingNote(Note note) => note.source == NoteSource.capture || note.recordingMs != null;

/// The counts of [all] for [period], as at [now]. [folderOf] names a note's folder (null for none); [plugins] is how
/// many are on.
WrappedStats wrappedStats(List<Note> all, WrappedPeriod period, {required DateTime now, String? Function(String noteId)? folderOf, int plugins = 0, int top = 5}) {
  final start = period.startFor(now)?.millisecondsSinceEpoch;
  bool inside(int ms) => (start == null || ms >= start) && ms <= now.millisecondsSinceEpoch;
  final live = [for (final note in all) if (!note.inTrash) note];
  final written = [for (final note in live) if (inside(note.createdAt)) note];

  final months = <(int, int), int>{};
  final days = <int, int>{};
  final hours = <int, int>{};
  final dates = <DateTime>{};
  final tags = <String, int>{};
  final folders = <String, int>{};
  var words = 0, done = 0, open = 0, meetings = 0, recordings = 0;
  DateTime dayOf(int ms) {
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(at.year, at.month, at.day);
  }

  for (final note in written) {
    final at = DateTime.fromMillisecondsSinceEpoch(note.createdAt);
    months.update((at.year, at.month), (n) => n + 1, ifAbsent: () => 1);
    days.update(at.weekday, (n) => n + 1, ifAbsent: () => 1);
    hours.update(at.hour, (n) => n + 1, ifAbsent: () => 1);
    words += noteWords(note.body);
    final todos = todoCounts(note.body);
    done += todos.done;
    open += todos.open;
    if (isMeetingNote(note)) meetings += 1;
    if (isRecordingNote(note)) recordings += 1;
    final named = <String>{
      for (final tag in tagsIn(note.body)) tag.name.replaceFirst('#', '').toLowerCase(),
      for (final tag in propertyList(frontMatterValue(note.body, 'tags'))) tag.replaceFirst('#', '').toLowerCase(),
    };
    for (final tag in named) {
      if (tag.isNotEmpty) tags.update(tag, (n) => n + 1, ifAbsent: () => 1);
    }
    final folder = folderOf?.call(note.id);
    if (folder != null && folder.isNotEmpty) folders.update(folder, (n) => n + 1, ifAbsent: () => 1);
  }
  for (final note in live) {
    if (inside(note.createdAt)) dates.add(dayOf(note.createdAt));
    if (inside(note.updatedAt)) dates.add(dayOf(note.updatedAt));
  }

  // The longest run of days in a row.
  final sorted = dates.toList()..sort();
  var longest = sorted.isEmpty ? 0 : 1, run = sorted.isEmpty ? 0 : 1;
  for (var i = 1; i < sorted.length; i += 1) {
    // A day after the last, by the calendar (a clock change makes a day 23 or 25 hours).
    final next = DateTime(sorted[i - 1].year, sorted[i - 1].month, sorted[i - 1].day + 1);
    run = sorted[i] == next ? run + 1 : 1;
    if (run > longest) longest = run;
  }

  // The notes most linked to, from any note of the library, by title.
  final byTitle = <String, Note>{};
  for (final note in live) {
    final title = noteTitle(note.body).trim();
    if (title.isNotEmpty) byTitle.putIfAbsent(titleKey(title), () => note);
  }
  final links = <String, int>{};
  for (final note in live) {
    final seen = <String>{};
    for (final link in linksIn(note.body)) {
      final target = byTitle[titleKey(link.key)];
      if (target == null || target.id == note.id || !seen.add(target.id)) continue;
      links.update(target.id, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  final linked = [
    for (final MapEntry(:key, :value) in links.entries) (id: key, title: noteTitle(live.firstWhere((n) => n.id == key).body), links: value),
  ]..sort((a, b) => b.links != a.links ? b.links - a.links : a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  List<Counted> topOf(Map<String, int> counts) => ([
        for (final MapEntry(:key, :value) in counts.entries) (name: key, count: value),
      ]..sort((a, b) => b.count != a.count ? b.count - a.count : a.name.compareTo(b.name)))
          .take(top)
          .toList();

  MapEntry<K, int>? most<K>(Map<K, int> counts) => counts.isEmpty ? null : counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  final month = most(months), day = most(days), hour = most(hours);
  return WrappedStats(
    period: period,
    notes: written.length,
    words: words,
    edited: live.where((n) => inside(n.updatedAt)).length,
    busiestMonth: month == null ? null : (year: month.key.$1, month: month.key.$2, count: month.value),
    busiestDay: day == null ? null : (day: day.key, count: day.value),
    busiestHour: hour == null ? null : (hour: hour.key, count: hour.value),
    longestStreak: longest,
    mostLinked: linked.take(top).toList(),
    topTags: topOf(tags),
    topFolders: topOf(folders),
    todosDone: done,
    todosOpen: open,
    meetings: meetings,
    recordings: recordings,
    plugins: plugins,
  );
}

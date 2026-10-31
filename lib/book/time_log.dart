/// A ticket's time, logged in its own words (Matt, 2026-10-31, of the ticket features: "time tracking"). Pure.
///
/// Each stretch of work is a plain line under a `## Time` heading at the foot of the ticket, and the total is one
/// front matter key, `spent:`, which is what a query or a rollup adds up (`sum(spent)`, lib/core/durations.dart):
///
///     ---
///     type: ticket
///     id: HT-12
///     spent: 2h 5m
///     ---
///     # Fix the login
///     …
///     ## Time
///
///     - 2026-10-30 · 1h 20m · Matt
///     - 2026-10-31 · 45m · Sam · fixed the flaky test
///
/// Why lines and not a front matter list of `{date, minutes, who}`: the front matter here is a key and a value a
/// line (lib/core/properties.dart), so a list of maps would be YAML's flow syntax, `{date: …, minutes: 80}`, which
/// reads as code in every other app and is easy to break by hand. A line under a heading reads as what it is in any
/// Markdown app, can be typed or fixed by hand, and the log of a long ticket never crowds its properties. The `·`
/// is what the app writes; a line typed with a dash, a comma or a bar between its parts reads the same.
///
/// `spent:` is the total, and each line the app logs is added to it: time someone wrote there by hand before anything
/// was logged is kept. A ticket with a log and no `spent:` (a log typed by hand) totals its lines.
library;

import '../core/durations.dart' show spentMinutes, spentWords;
import '../core/front_matter.dart' show frontMatterValue;
import '../core/properties.dart' show withProperty;

/// The heading the log is under.
const String timeHeading = '## Time';

/// The front matter key the total is kept in.
const String spentKey = 'spent';

/// One stretch of work on a ticket: the day, how long, who, and a few words of what, where given.
class TimeEntry {
  const TimeEntry({required this.day, required this.minutes, required this.who, this.note = ''});

  /// An ISO day, `2026-10-30`.
  final String day;
  final int minutes;
  final String who;
  final String note;

  /// The line the log writes for it: `- 2026-10-30 · 1h 20m · Matt`.
  String get line => ['- $day', spentWords(minutes), if (who.trim().isNotEmpty) who.trim(), if (note.trim().isNotEmpty) note.trim()].join(' · ');

  @override
  bool operator ==(Object other) => other is TimeEntry && other.day == day && other.minutes == minutes && other.who == who && other.note == note;

  @override
  int get hashCode => Object.hash(day, minutes, who, note);

  @override
  String toString() => 'TimeEntry($line)';
}

final RegExp _heading = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$');
final RegExp _entry = RegExp(r'^\s*[-*+]\s+(\d{4}-\d{2}-\d{2})\s*(?:[·|,]|\s-\s)?\s*(.*)$');
final RegExp _sep = RegExp(r'\s*(?:·|\||,|\s-\s)\s*');

/// Where the log's lines are: the index of its heading line and of the line after its last, in [lines]; null where
/// the ticket has none.
({int head, int end})? _section(List<String> lines) {
  var fence = false;
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```') || line.trimLeft().startsWith('~~~')) fence = !fence;
    if (fence) continue;
    final found = _heading.firstMatch(line);
    if (found == null || !line.startsWith('## ') || found.group(1)!.toLowerCase() != 'time') continue;
    var end = i + 1;
    while (end < lines.length && !lines[end].startsWith('#')) {
      end += 1;
    }
    return (head: i, end: end);
  }
  return null;
}

/// One log line read, or null for a line that is no entry.
TimeEntry? timeEntryOf(String line) {
  final found = _entry.firstMatch(line);
  if (found == null) return null;
  final parts = found.group(2)!.split(_sep).where((part) => part.trim().isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final minutes = spentMinutes(parts.first);
  if (minutes == null) return null;
  return TimeEntry(day: found.group(1)!, minutes: minutes, who: parts.length > 1 ? parts[1].trim() : '', note: parts.length > 2 ? parts.sublist(2).join(' · ').trim() : '');
}

/// The ticket's log, in the order written.
List<TimeEntry> timeLogOf(String body) {
  final lines = body.split('\n');
  final section = _section(lines);
  if (section == null) return const [];
  return [for (var i = section.head + 1; i < section.end; i += 1) ?timeEntryOf(lines[i])];
}

/// The minutes a ticket has spent: what its `spent:` says, or, with none, its log's total; 0 for neither.
int spentOf(String body) => spentMinutes(frontMatterValue(body, spentKey)) ?? timeLogOf(body).fold<int>(0, (sum, entry) => sum + entry.minutes);

/// [body] with [entry] logged: its line at the foot of the `## Time` section (the section made at the foot of the
/// note where there is none), and `spent:` written again as the total.
String withTimeLogged(String body, TimeEntry entry) {
  final total = spentOf(body) + entry.minutes;
  final lines = body.split('\n');
  final section = _section(lines);
  final String logged;
  if (section == null) {
    final text = body.trimRight();
    logged = '$text\n\n$timeHeading\n\n${entry.line}\n';
  } else {
    // After the section's last line with words, so a blank line before the next heading stays.
    var at = section.end;
    while (at > section.head + 1 && lines[at - 1].trim().isEmpty) {
      at -= 1;
    }
    final head = lines.sublist(0, at);
    if (at == section.head + 1) head.add('');
    logged = [...head, entry.line, ...lines.sublist(at)].join('\n');
  }
  return withProperty(logged, spentKey, spentWords(total));
}

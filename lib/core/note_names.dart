/// The names a new note is offered under its empty first line (docs/DESIGN.md §144). A port of
/// `src/app/core/noteNames.ts`. Matt: "Add suggestions for note names like the days date and other standard note
/// formats".
///
/// Four, always in this order: the day in words with its year, "Monday, 28 September 2026"; `2026-09-28`, Obsidian's
/// daily note's name; `2026-09-28 14.05`, the journal's name for an entry; `2026-W40`, the ISO week. A name another
/// note already has is left out, and the rest keep their places. `taken` is every note's title key, archived and in
/// the Trash too.
///
/// What differs: the page asks `Intl.DateTimeFormat` for the day in words in the device's language, and so has
/// `keysTheDay` for the languages whose words lose the month once reduced to a key. This app's strings are English
/// first (README, "What stage 1 left open"), so the day is written the way en-GB writes it, which always keys the
/// day, and [keysTheDay] is true for every date; it is kept so the rule has a name when other languages arrive.
library;

import '../notes/note_templates.dart' show formatStamp;
import 'title_key.dart';
import 'day_order.dart';

/// Which of the four a name is (`NameKind`).
enum NameKind { words, day, minute, week }

/// One name on offer (`NameOffer`).
class NameOffer {
  const NameOffer({required this.kind, required this.name, required this.label});
  final NameKind kind;

  /// What the chip shows, and what a tap writes as the note's heading.
  final String name;

  /// What a screen reader says for it.
  final String label;
}

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "Monday, 28 September 2026" (`longDate`, core/stamp.ts, as en-GB answers it).
String longDate(DateTime at) => longDateWords(_weekdays[at.weekday - 1], at.day, _months[at.month - 1], at.year);

/// "2026-09-28 14.05": the minute as a name, as a journal names an entry (`minuteName`).
String minuteName(DateTime at) => formatStamp(at, 'YYYY-MM-DD HH.mm');

/// Whether the day in words still tells one day from another once reduced to its key (`keysTheDay`).
bool keysTheDay(DateTime at) {
  final day = at.day < 28 ? at.day : 28;
  final key = titleKey(longDate(DateTime(at.year, at.month, day)));
  if (key.isEmpty) return false;
  return key != titleKey(longDate(DateTime(at.year, at.month + 1, day))) && key != titleKey(longDate(DateTime(at.year + 1, at.month, day)));
}

/// The names on offer at [at], in their fixed order, leaving out any whose key is in [taken] (`nameOffers`).
List<NameOffer> nameOffers(DateTime at, Set<String> taken) {
  final day = formatStamp(at, 'YYYY-MM-DD');
  final words = longDate(at);
  final minute = minuteName(at);
  final week = formatStamp(at, 'GGGG-[W]WW');
  final all = <(NameOffer, String)>[
    (NameOffer(kind: NameKind.words, name: words, label: 'Name it for today, in words.'), keysTheDay(at) ? titleKey(words) : titleKey(day)),
    (NameOffer(kind: NameKind.day, name: day, label: 'Name it for today, $day.'), titleKey(day)),
    (NameOffer(kind: NameKind.minute, name: minute, label: 'Name it for this minute, $minute.'), titleKey(minute)),
    (NameOffer(kind: NameKind.week, name: week, label: 'Name it for this week, $week.'), titleKey(week)),
  ];
  return [
    for (final (offer, key) in all)
      if (!taken.contains(key)) offer,
  ];
}

/// Time spent, as a person writes it: `3h 20m`, `45m`, `2h`, `1.5h`, `90 min` (Matt, 2026-10-31, of the ticket features:
/// "time tracking", a ticket's `spent: 3h 20m` added up by rollups and a query's `sum(spent)`). Pure.
///
/// A ticket's time is written in hours and minutes because that is how a person says it and reads it back; a sum of
/// `3h 20m` and `45m` is `4h 5m`, never `48` (what a sum's leading number would make of them, sums.dart). So a value
/// is a duration only where every part of it is a number with an hour or minute after it, and nothing else: `3 days`
/// and `$300` are not, and are added as numbers, as they always were.
library;

final RegExp _part = RegExp(r'(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)(?![a-z])', caseSensitive: false);
final RegExp _between = RegExp(r'^[\s,]*$');

/// The minutes [text] says, where it is a duration and nothing else (`3h 20m` is 200, `1.5h` 90, `45 min` 45); null
/// for anything else, a bare number among them: `3` could be hours or points.
int? spentMinutes(String? text) {
  final words = (text ?? '').trim();
  if (words.isEmpty) return null;
  var at = 0;
  var minutes = 0.0;
  var parts = 0;
  for (final found in _part.allMatches(words)) {
    if (!_between.hasMatch(words.substring(at, found.start))) return null;
    final n = double.parse(found.group(1)!);
    minutes += found.group(2)!.toLowerCase().startsWith('h') ? n * 60 : n;
    parts += 1;
    at = found.end;
  }
  if (parts == 0 || !_between.hasMatch(words.substring(at))) return null;
  return minutes.round();
}

/// Minutes as a ticket writes them: `3h 20m`, `45m`, `2h`, `0m` for none.
String spentWords(int minutes) {
  final m = minutes < 0 ? 0 : minutes;
  final h = m ~/ 60, rest = m % 60;
  if (h == 0) return '${rest}m';
  return rest == 0 ? '${h}h' : '${h}h ${rest}m';
}

/// The total of some values where every one with anything in it is a duration ([spentMinutes]), written as one
/// (`3h 20m` and `45m` total `4h 5m`); null where any is not, for a total to add them as numbers instead.
String? spentTotal(Iterable<String> values) {
  var minutes = 0;
  var any = false;
  for (final value in values) {
    if (value.trim().isEmpty) continue;
    final each = spentMinutes(value);
    if (each == null) return null;
    minutes += each;
    any = true;
  }
  return any ? spentWords(minutes) : null;
}

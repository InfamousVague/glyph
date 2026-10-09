/// A timestamp a person reads rather than parses: "2 hr ago", "Yesterday", "Tuesday", "March 4". A port of
/// `src/app/notes/when.ts`.
///
/// What differs: the web asks the device's language for a weekday and a date
/// (`toLocaleDateString(undefined, { weekday: 'long' })`); here they are written in English, the date in the phone's
/// own order once it has said which (core/locale_dates.dart: "4 March" on a British phone), and month before day, as
/// an American page writes them, until then.
library;

import '../core/locale_dates.dart';

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// [ms] and [now] are milliseconds since the epoch; [now] is this moment where it is left out.
String when(int ms, [int? now]) {
  final delta = (now ?? DateTime.now().millisecondsSinceEpoch) - ms;
  const minute = 60000;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (delta < minute) return 'Just now';
  if (delta < hour) return '${delta ~/ minute} min ago';
  if (delta < day) return '${delta ~/ hour} hr ago';
  if (delta < 2 * day) return 'Yesterday';
  final at = DateTime.fromMillisecondsSinceEpoch(ms);
  if (delta < 7 * day) return _weekdays[at.weekday - 1];
  return toldDate(at, DateForm.MMMMd) ?? '${_months[at.month - 1]} ${at.day}';
}

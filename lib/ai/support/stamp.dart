/// A moment written as words, one way wherever the app writes one. A port of `src/app/core/stamp.ts`: the time the +
/// puts at the line (docs/DESIGN.md §141), a journal entry's date and time (§142), the home page's day, the day in
/// words a new note can be named by (§144), and the date a worked-out blank is drawn with (§145, core/fill_facts.dart).
/// It belongs in lib/core once that stage lands.
///
/// Always on a 24-hour clock, as a meeting's title is written: "14:05" reads the same to everyone who reads the note
/// later. Pure, and it imports nothing.
///
/// What differs: the page asks `Intl.DateTimeFormat` with no locale, which is the device's language and order. This
/// app's strings are English first (README, "What stage 1 left open"), so every form here is English, in the
/// phone's own order, commas and short months once the phone has said which (lib/core/locale_dates.dart, the page's
/// own answers for en-US and en-GB), and until then the day first from two fixed lists of names, as it always was.
/// Earlier stages wrote the same forms where they needed them (lib/core/note_names.dart `longDate`,
/// lib/notes/note_templates.dart `longDay` and `clockTime`, lib/editor/plus/add_rows.dart `stamp`); they agree with
/// these, word for word.
library;

import '../../core/locale_dates.dart';

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const List<String> _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// A weekday's name in full: "Monday".
String weekdayName(DateTime date) => _weekdays[date.weekday - 1];

/// A month's name in full, by its number from 1: "September". A number outside 1 to 12 wraps round, as a JavaScript
/// `Date` made with it does.
String monthName(int month) => _months[(month - 1) % 12];

/// "28 Sept 2026, 14:05": the day and the short month in the phone's order ("Sep 28 2026, 14:05" on an American
/// one), the year, and the time.
String stamp(DateTime date) => '${toldDayMonth(date, DateForm.MMMd) ?? '${date.day} ${_shortMonths[date.month - 1]}'} ${date.year}, ${clockTime(date)}';

/// "14:05": the time on a 24-hour clock.
String clockTime(DateTime date) => '${_two(date.hour)}:${_two(date.minute)}';

/// "Monday 28 September", or "Monday, September 28" on an American phone: the weekday, the day and the month, no
/// year, as the home page greets the day.
String longDay(DateTime date) => toldDate(date, DateForm.MMMMEEEEd) ?? '${weekdayName(date)} ${date.day} ${monthName(date.month)}';

/// The weekday, the day, the month and the year, as a new note's name for the day and as a worked-out date is drawn
/// after a blank: "Monday, September 28, 2026" on an American phone, "Monday 28 September 2026" on a British one,
/// and "Monday, 28 September 2026" until the phone has said. The model is never shown it: its message has fixed
/// English (ai/fills/message.dart `modelDay`).
String longDate(DateTime date) => toldDate(date, DateForm.yMMMMEEEEd) ?? '${weekdayName(date)}, ${date.day} ${monthName(date.month)} ${date.year}';

/// "28 September", or "September 28" on an American phone: the day and the month, as the day the clocks change is
/// said.
String dayMonth(DateTime date) => toldDate(date, DateForm.MMMMd) ?? '${date.day} ${monthName(date.month)}';

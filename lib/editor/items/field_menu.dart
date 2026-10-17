/// What the press-and-hold menu does with a to-do's fields: the page it turns to when a chip is tapped or a field
/// is asked for, the days it offers, and the edits a press makes. Ports `src/app/editor/fieldMenu.ts`.
///
/// Every edit goes through the one writer, `lib/core/task_fields.dart` `withField` and `withAssignee`, so a date
/// set from the menu is where Obsidian Tasks reads it, and each is one ordinary edit of one line: one undo, saved
/// like typing.
///
/// What differs:
/// - A tapped chip tells the menu with a DOM event on the editor's element (`FIELD_TAP`); here it is told to
///   [fieldTapOf], a notifier kept for the view, which whoever draws the menu listens to (`field_items.dart`
///   [FieldMenuHost], and the band when it is ported), and to the [fieldTaps] facet's listeners.
/// - `pickDay` opens the phone's own date picker from a hidden `<input type="date">`. A Flutter app has no such
///   input: the picker is whatever [dayPicker] says, which the app fills with its own calendar.
/// - The port's own, with Settings › Contacts (lib/integrations/contacts, docs/INTEGRATIONS.md §2): a person who is
///   a contact opens their card on a tap ([personCard]) in place of their page, and Assign offers A person, a
///   contact picked from the phone's ([personPicker]). Neither is there where the app gives neither.
library;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../core/day_words.dart';
import '../../core/days.dart';
import '../../core/item_syntax.dart';
import '../../core/task_fields.dart';
import '../../reminders/place_host.dart' show placeRemindersOn;
import '../../reminders/place_syntax.dart' show PlaceMark, placeOn, withPlace;
import '../../reminders/reminder_syntax.dart' show ReminderTime, withReminder;
import '../editor.dart';

/// Which page of fields the band shows.
sealed class FieldPage {
  const FieldPage();
}

/// A day: Today, Tomorrow, Next week, a date picked, or none. `key` is `due`, `start` or `scheduled`.
class DatePage extends FieldPage {
  const DatePage(this.key);
  final String key;

  @override
  bool operator ==(Object other) => other is DatePage && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The five priorities, and none.
class PriorityPage extends FieldPage {
  const PriorityPage();

  @override
  bool operator ==(Object other) => other is PriorityPage;

  @override
  int get hashCode => 1;
}

/// One person on the line, to take off.
class PersonPage extends FieldPage {
  const PersonPage(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is PersonPage && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// The people this note names, to put on the line or take off, and someone new.
class AssignPage extends FieldPage {
  const AssignPage();

  @override
  bool operator ==(Object other) => other is AssignPage;

  @override
  int get hashCode => 2;
}

/// A reminder: In an hour, This evening, Tomorrow, Pick a time, and Remove when it has one (lib/reminders). Offered
/// only where the phone reminds ([reminderPicker] is given).
class RemindPage extends FieldPage {
  const RemindPage();

  @override
  bool operator ==(Object other) => other is RemindPage;

  @override
  int get hashCode => 3;
}

/// A place reminder's chip tapped: Change place, where the phone watches places ([placePicker] is given), and Remove
/// (lib/reminders/place_syntax.dart).
class PlacePage extends FieldPage {
  const PlacePage();

  @override
  bool operator ==(Object other) => other is PlacePage;

  @override
  int get hashCode => 4;
}

/// A chip tapped: which page, for which line (counting from 1), and where the chip is on the screen.
class FieldTap {
  const FieldTap({required this.page, required this.line, required this.x, required this.y});

  final FieldPage page;
  final int line;
  final double x;
  final double y;
}

/// Listeners told of every tapped chip, beside [fieldTapOf].
final Facet<void Function(FieldTap tap), List<void Function(FieldTap tap)>> fieldTaps = Facet.define();

final Expando<ValueNotifier<FieldTap?>> _tapped = Expando<ValueNotifier<FieldTap?>>('fieldTap');

/// The chip last tapped in `view`, for the menu to open at; set back to null when the menu closes.
ValueNotifier<FieldTap?> fieldTapOf(EditorViewLike view) => _tapped[view] ??= ValueNotifier<FieldTap?>(null);

/// Tells the menu a chip was tapped: a person who is a contact opens their card instead, where the app has one.
void tapField(EditorViewLike view, FieldTap tap) {
  for (final heard in view.state.facet(fieldTaps)) {
    heard(tap);
  }
  if (tap.page case PersonPage(:final name)) {
    final card = view.state.facet(personCard);
    if (card != null && card(view, tap, name)) return;
  }
  fieldTapOf(view).value = tap;
}

/// Opens the card of the person a tapped chip names, where they are a contact (lib/integrations/contacts); answers
/// whether it did, and false leaves the tap to the menu, which opens the person's page as before.
typedef PersonCardOpener = bool Function(EditorViewLike view, FieldTap tap, String name);

/// The app's person cards. None, and a person's chip opens their page.
final Facet<PersonCardOpener, PersonCardOpener?> personCard = Facet.define<PersonCardOpener, PersonCardOpener?>(combine: (values) => values.isEmpty ? null : values.first);

/// A contact picked from the phone's address book, for A person: whether it is offered now (Settings › Contacts on
/// and allowed), and the picking, from where the press was, which answers the name to write or null for none.
class PersonPicking {
  const PersonPicking({required this.offered, required this.pick});

  final bool Function() offered;
  final Future<String?> Function(Offset at) pick;
}

/// The app's contact picker. None, or not offered now, and Assign has no A person.
final Facet<PersonPicking, PersonPicking?> personPicker = Facet.define<PersonPicking, PersonPicking?>(combine: (values) => values.isEmpty ? null : values.first);

// ---- the days on offer -------------------------------------------------------------------------------------------

class DayChoice {
  const DayChoice(this.id, this.label, this.day);

  /// `today`, `tomorrow` or `next-week`.
  final String id;
  final String label;
  final String day;

  @override
  bool operator ==(Object other) => other is DayChoice && other.id == id && other.label == label && other.day == day;

  @override
  int get hashCode => Object.hash(id, label, day);

  @override
  String toString() => 'DayChoice($id, $label, $day)';
}

/// The days a date's page offers before Pick a date: today, tomorrow and next week, which is that week's Monday,
/// as a spoken "due next week" is.
List<DayChoice> dayChoices(String today) {
  final choices = <DayChoice>[DayChoice('today', 'Today', today), DayChoice('tomorrow', 'Tomorrow', isoDayAfter(today, 1) ?? today)];
  final monday = nextWeek(today);
  if (monday != null) choices.add(DayChoice('next-week', 'Next week', monday));
  return choices;
}

/// Today, as the menu counts from it: the device's own day.
String todayIs([DateTime? now]) => isoDay(now ?? DateTime.now());

// ---- reading a line ----------------------------------------------------------------------------------------------

/// Whether a line can take fields from the menu: a list item, a bullet, a step or a to-do.
bool takesFields(String text) => listLead(text) != null;

/// What the fields on line `number` say now, or null where there is no such line.
TaskFields? lineFields(EditorViewLike view, int number) {
  if (number < 1 || number > view.state.doc.lines) return null;
  return fieldsOf(view.state.doc.line(number).text);
}

/// The people a note names, each once, in the order it first names them: who the Assign page offers.
List<String> peopleIn(String doc) {
  final seen = <String>{};
  final people = <String>[];
  for (final span in fieldsIn(doc)) {
    if (span.kind != FieldKind.person) continue;
    if (!seen.add(personKey(span.value))) continue;
    people.add(span.value);
  }
  return people;
}

// ---- the edits ---------------------------------------------------------------------------------------------------

/// Line `number` rewritten by `change`, as one edit, or false where nothing changed or the line is gone.
bool _rewrite(EditorViewLike view, int number, String Function(String text) change) {
  if (view.state.readOnly || number < 1 || number > view.state.doc.lines) return false;
  final line = view.state.doc.line(number);
  final next = change(line.text);
  if (next == line.text) return false;
  // Only what differs is replaced, so the caret and the marks either side of the change stay where they were.
  var head = 0;
  while (head < next.length && head < line.text.length && next.codeUnitAt(head) == line.text.codeUnitAt(head)) {
    head += 1;
  }
  var tail = 0;
  while (tail < next.length - head && tail < line.text.length - head && next.codeUnitAt(next.length - 1 - tail) == line.text.codeUnitAt(line.text.length - 1 - tail)) {
    tail += 1;
  }
  view.dispatch(TransactionSpec(changes: ChangeSpec(from: line.from + head, to: line.to - tail, insert: next.substring(head, next.length - tail)), userEvent: 'input.field'));
  return true;
}

/// Sets, changes or (with null) takes off one field on line `number`, through the one writer.
bool setLineField(EditorViewLike view, int number, String key, String? value) => _rewrite(view, number, (text) => withField(text, key, value));

/// Puts a person on line `number`, or takes them off it.
bool setLinePerson(EditorViewLike view, int number, String name, bool on) => _rewrite(view, number, (text) => withAssignee(text, name, on));

/// Someone new on line `number`: an at sign where a person goes - before Tasks' run, after any person there -
/// with the caret after it, for the name to be typed. Written as a person would be, then the name taken back off,
/// so the at sign lands exactly where `withAssignee` would put one.
bool startPerson(EditorViewLike view, int number) {
  if (view.state.readOnly || number < 1 || number > view.state.doc.lines) return false;
  final line = view.state.doc.line(number);
  const stand = 'Zq';
  final written = withAssignee(line.text, stand);
  final at = written.lastIndexOf('@$stand');
  if (at < 0) return false;
  final next = '${written.substring(0, at + 1)}${written.substring(at + 1 + stand.length)}';
  view.dispatch(
    TransactionSpec(changes: ChangeSpec(from: line.from, to: line.to, insert: next), selection: EditorSelection.single(line.from + at + 1), userEvent: 'input.field', scrollIntoView: true),
  );
  view.focus();
  return true;
}

// ---- a day picked ------------------------------------------------------------------------------------------------

/// Opens a calendar where the press was, with `current` shown, and answers the day picked (`2026-10-03`) or null.
typedef DayPicker = Future<String?> Function(Offset at, String? current);

/// The app's date picker. None, and Pick a date is not offered.
final Facet<DayPicker, DayPicker?> dayPicker = Facet.define<DayPicker, DayPicker?>(combine: (values) => values.isEmpty ? null : values.first);

/// Picks a reminder's day and time, from where the press was, with the one the line has shown; null for none
/// (lib/reminders/remind_choices.dart `phoneReminderPicker`).
typedef ReminderPicker = Future<ReminderTime?> Function(Offset at, ReminderTime? current);

/// The phone's calendar and clock for a reminder. Given only where the phone reminds: absent, a line's menu offers no
/// Remind me and a reminder's chip opens nothing.
final Facet<ReminderPicker, ReminderPicker?> reminderPicker = Facet.define<ReminderPicker, ReminderPicker?>(combine: (values) => values.isEmpty ? null : values.first);

/// The moment Remind me counts its times from; the device's own where none is given (a test gives its own).
final Facet<DateTime Function(), DateTime Function()?> fieldsNow = Facet.define<DateTime Function(), DateTime Function()?>(combine: (values) => values.isEmpty ? null : values.first);

/// Sets line `number`'s reminder, or (with null) takes it off: `⏰ 2026-10-03 09:00` before Tasks' fields.
bool setLineReminder(EditorViewLike view, int number, ReminderTime? at) => _rewrite(view, number, (text) => withReminder(text, at));

/// Picks a place for line `line` of the note, with the one the line has shown; null where the sheet was put away
/// (lib/reminders/place_sheet.dart: a search, the places in the note, and here).
typedef PlacePicker = Future<PlaceMark?> Function(int line, PlaceMark? current);

/// The sheet a place reminder is picked on. Given only where the phone watches places: absent, a line's menu offers
/// no Remind me at a place, and a place's chip offers only Remove.
final Facet<PlacePicker, PlacePicker?> placePicker = Facet.define<PlacePicker, PlacePicker?>(combine: (values) => values.isEmpty ? null : values.first);

/// Whether Remind me at a place is offered in `view` now: the sheet was given, and the Place reminders plugin is on
/// (lib/plugins/places). Off, a `📍` already written is still read and drawn: it is the note's Markdown.
bool placesOffered(EditorViewLike view) => view.state.facet(placePicker) != null && placeRemindersOn.value;

/// Sets line `number`'s place, or (with null) takes it off: `📍 [Target](geo:…)` before Tasks' fields.
bool setLinePlace(EditorViewLike view, int number, PlaceMark? mark) => _rewrite(view, number, (text) => withPlace(text, mark));

/// Remind me at a place for line `number`: the sheet [placePicker] opens, and the place picked written on the line,
/// the line read again as it is then, since the note may have changed under the sheet. True where one was written.
Future<bool> pickLinePlace(EditorViewLike view, int number, {bool refocus = false}) async {
  final pick = view.state.facet(placePicker);
  if (pick == null || !placesOffered(view) || number < 1 || number > view.state.doc.lines) return false;
  final mark = await pick(number, placeOn(view.state.doc.line(number).text));
  if (mark == null) return false;
  final written = setLinePlace(view, number, mark);
  if (refocus) view.focus();
  return written;
}

/// A day picked from the calendar [dayPicker] opens, handed to `onPick` when it is one.
Future<void> pickDay(EditorViewLike view, Offset at, String? current, void Function(String day) onPick) async {
  final picker = view.state.facet(dayPicker);
  if (picker == null) return;
  final day = await picker(at, current != null && isIsoDay(current) ? current : null);
  if (day != null && isIsoDay(day)) onPick(day);
}

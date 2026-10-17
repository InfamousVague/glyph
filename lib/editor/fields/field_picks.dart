/// What a field picker offers and how its marks are chosen (field_picker.dart draws them; docs/DESIGN.md §169): which
/// sheet a record's field opens in a query, with what it holds now; a status's mark; a person's hue. Pure, so the
/// choices can be tested without drawing a sheet. A port of `src/app/editor/fieldPicks.ts`.
///
/// What differs:
/// - `FieldPick`, a union of five object shapes on the page, is a sealed class of five ([StatusPick], [BoxPick],
///   [PriorityPick], [PersonPick], [DayPick]), each with value equality, so a pick can be compared by what it says.
///   `StatusLook`, a union of five strings, is an enum whose names are those strings. `HUES` is [hues]; a hue is
///   its name as a string, the name its tokens are called by (`glacier-blue-11`).
/// - [pickOf] and [picksField] take the query core's own [QueryRow] and [Cell] (lib/core/query/run.dart), as the
///   page's take `Row` and `Cell`. They were written before that core was ported and read a `PickRow` and a
///   `PickCell` of their own for a while; those are gone. A cell of another kind than its field asks for is read as
///   holding nothing, as on the page.
/// - A name's letters are added up by UTF-16 unit, a letter outside the basic plane by its first unit, as the page's
///   `for … of` with `charCodeAt(0)` adds them, so a name has the hue here that it has there.
library;

import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../../core/properties.dart';
import '../../core/query/records.dart' show RecordKind;
import '../../core/query/run.dart' show Cell, DayCell, PeopleCell, PriorityCell, QueryRow, StatusCell;

/// What a sheet picks, with what the field holds now (`FieldPick`).
@immutable
sealed class FieldPick {
  const FieldPick();
}

/// A ticket's status, on its workflow.
class StatusPick extends FieldPick {
  const StatusPick({required this.value, required this.workflow});
  final String? value;
  final List<String> workflow;

  @override
  bool operator ==(Object other) => other is StatusPick && other.value == value && listEquals(other.workflow, workflow);

  @override
  int get hashCode => Object.hash(value, Object.hashAll(workflow));

  @override
  String toString() => 'StatusPick($value, $workflow)';
}

/// A to-do's status, which is its box: To do or Done.
class BoxPick extends FieldPick {
  const BoxPick({required this.done});
  final bool done;

  @override
  bool operator ==(Object other) => other is BoxPick && other.done == done;

  @override
  int get hashCode => done.hashCode;

  @override
  String toString() => 'BoxPick($done)';
}

/// A priority, by its name (lib/core/task_fields.dart `priorities`), or none.
class PriorityPick extends FieldPick {
  const PriorityPick({required this.value});
  final String? value;

  @override
  bool operator ==(Object other) => other is PriorityPick && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PriorityPick($value)';
}

/// A person, among the people the library names.
class PersonPick extends FieldPick {
  const PersonPick({required this.value, required this.people});
  final String? value;
  final List<String> people;

  @override
  bool operator ==(Object other) => other is PersonPick && other.value == value && listEquals(other.people, people);

  @override
  int get hashCode => Object.hash(value, Object.hashAll(people));

  @override
  String toString() => 'PersonPick($value, $people)';
}

/// A day (`2026-10-03`), counted from [today].
class DayPick extends FieldPick {
  const DayPick({required this.value, required this.today});
  final String? value;
  final String today;

  @override
  bool operator ==(Object other) => other is DayPick && other.value == value && other.today == today;

  @override
  int get hashCode => Object.hash(value, today);

  @override
  String toString() => 'DayPick($value, $today)';
}

/// How a status is marked: a backlog's dashed ring, a review's eye, else its category's ring, dot or tick.
enum StatusLook { backlog, todo, doing, review, done }

final RegExp _review = RegExp('review', caseSensitive: false);
final RegExp _backlog = RegExp('backlog|later|someday|icebox', caseSensitive: false);

StatusLook statusLook(String status, [List<String>? workflow]) {
  final category = statusCategory(status, workflow);
  if (category == StatusCategory.done) return StatusLook.done;
  if (category == StatusCategory.doing) return _review.hasMatch(status) ? StatusLook.review : StatusLook.doing;
  return _backlog.hasMatch(status) ? StatusLook.backlog : StatusLook.todo;
}

/// The six hues a person can wear (`HUES`).
const List<String> hues = <String>['blue', 'purple', 'green', 'amber', 'red', 'teal'];

final RegExp _ats = RegExp('^@+');

/// One of six hues for a name, the same every time: its letters added up, case and at signs aside.
String hueOf(String name) {
  var sum = 0;
  for (final letter in name.replaceFirst(_ats, '').toLowerCase().runes) {
    // `letter.charCodeAt(0)`: a letter outside the basic plane counts as the first half of its pair.
    final unit = letter > 0xFFFF ? 0xD800 + ((letter - 0x10000) >> 10) : letter;
    sum = (sum * 31 + unit) % 9973;
  }
  return hues[sum % hues.length];
}

/// The days a sheet picks: a due and a start day, and a to-do's scheduled day, which a ticket does not have.
const Set<String> _pickedDays = <String>{'due', 'start', 'scheduled'};

bool _picksDay(QueryRow row, String key) => _pickedDays.contains(key) && (row.kind == RecordKind.task || key != 'scheduled');

/// What sheet a record's field opens, from what it holds now; null for a field nothing picks (a title, a tag, a
/// note). [people] is asked only for a person, since answering it reads every note.
FieldPick? pickOf(QueryRow row, String field, Cell cell, String today, List<String> Function() people) {
  // An event is the calendar's to change, not a note's (docs/CALENDAR.md).
  if (row.kind == RecordKind.event) return null;
  final key = field.toLowerCase();
  if (key == 'status') {
    if (row.kind == RecordKind.task) return row.done == null ? null : BoxPick(done: row.done!);
    return StatusPick(value: cell is StatusCell ? cell.text : null, workflow: row.workflow);
  }
  if (key == 'priority') return PriorityPick(value: cell is PriorityCell ? cell.name : null);
  if (key == 'assignee') return PersonPick(value: cell is PeopleCell ? cell.names.firstOrNull : null, people: people());
  if (_picksDay(row, key)) return DayPick(value: cell is DayCell ? cell.day : null, today: today);
  return null;
}

/// Whether a field is one [pickOf] opens a sheet for, without reading the people.
bool picksField(QueryRow row, String field) {
  if (row.kind == RecordKind.event) return false;
  final key = field.toLowerCase();
  if (key == 'status') return row.kind != RecordKind.task || row.done != null;
  return key == 'priority' || key == 'assignee' || _picksDay(row, key);
}

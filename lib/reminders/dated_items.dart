/// The items of a note that a day or a time is written on: its to-dos and list items with a due day (`📅`, or
/// Dataview's `[due:: …]`) or a reminder (`⏰`), and a ticket's own `due:` and `remind:`. What reminders and the home
/// screen's Today widget are both made from (reminder_plan.dart, lib/home_screen/home_data.dart).
///
/// Read once for each note as the library holds it ([DatedItems.of], kept by the note object, which the library
/// keeps the same while the note is: lib/core/core_library.dart), so a change to the notes reads only the notes it
/// changed. A line is put to the field grammar only where one of the signs is in it; front matter and fenced code are
/// passed over, as they are no one's to-dos.
library;

import 'package:flutter/foundation.dart';

import '../core/front_matter.dart' show frontMatterEnd, frontMatterValue;
import '../core/item_syntax.dart' show lineWords, listLead;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/properties.dart' show StatusCategory;
import '../core/task_fields.dart' show fieldsOf, withoutFields;
import 'reminder_syntax.dart';

/// One item with a day or a time on it.
@immutable
class DatedItem {
  const DatedItem({required this.line, required this.words, required this.due, required this.at, required this.box, required this.done});

  /// Its line in the note's body, counting from 1; 0 for a ticket, which is the whole note.
  final int line;

  /// What it says, its lead and its fields taken off: "Call the plumber". A ticket's title.
  final String words;

  /// Its due day, `2026-10-03`, or null.
  final String? due;

  /// Its own reminder, or null.
  final ReminderTime? at;

  /// Whether it can be ticked: a to-do's box, or a ticket, whose status goes to its workflow's done.
  final bool box;

  /// Whether it is finished: ticked, or a done or cancelled day written on it; a ticket whose status is done.
  final bool done;

  @override
  bool operator ==(Object other) => other is DatedItem && other.line == line && other.words == words && other.due == due && other.at == at && other.box == box && other.done == done;

  @override
  int get hashCode => Object.hash(line, words, due, at, box, done);

  @override
  String toString() => 'DatedItem($line "$words" due $due at ${at?.written} ${box ? 'box' : ''}${done ? ' done' : ''})';
}

/// Fenced code's opening and closing line.
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// The signs a line must have one of to be read: a due day's three, Dataview's `due::`, and a reminder's.
bool _maySay(String line) => line.contains('📅') || line.contains('📆') || line.contains('🗓') || line.contains('due::') || line.contains(reminderSign);

/// The dated items of a body, in the order they are written. Pure; [DatedItems.of] keeps each note's.
List<DatedItem> datedItemsIn(String body, [NoteFacts? read]) {
  final facts = read ?? NoteFacts.read(body);
  if (facts.isCanvas || facts.isTemplatePage || facts.isTemplatesBook) return const [];
  final items = <DatedItem>[];
  final ticket = facts.isTicket ? facts.ticket : null;
  if (ticket != null) {
    final at = readReminderTime(frontMatterValue(body, ticketReminderKey));
    if (ticket.due != null || at != null) {
      items.add(DatedItem(line: 0, words: facts.title, due: ticket.due, at: at, box: true, done: ticket.category == StatusCategory.done));
    }
  }
  if (!_maySay(body)) return items;
  final lines = body.split('\n');
  var fenced = false;
  for (var index = frontMatterEnd(lines); index < lines.length; index += 1) {
    final text = lines[index];
    if (_fence.hasMatch(text)) {
      fenced = !fenced;
      continue;
    }
    if (fenced || !_maySay(text)) continue;
    final lead = listLead(text);
    if (lead == null) continue;
    final fields = fieldsOf(text);
    final at = reminderOn(text);
    if (fields.due == null && at == null) continue;
    items.add(
      DatedItem(
        line: index + 1,
        words: withoutFields(lineWords(text)),
        due: fields.due,
        at: at,
        box: lead.done != null,
        done: lead.done == true || fields.done != null || fields.cancelled != null,
      ),
    );
  }
  return items;
}

/// Each note's dated items, kept by the note object.
class DatedItems {
  DatedItems._();

  static final Expando<List<DatedItem>> _kept = Expando<List<DatedItem>>('datedItems');

  /// [note]'s dated items, read the first time it is asked for this object.
  static List<DatedItem> of(Note note) => _kept[note] ??= List<DatedItem>.unmodifiable(datedItemsIn(note.body, NoteFacts.of(note)));
}

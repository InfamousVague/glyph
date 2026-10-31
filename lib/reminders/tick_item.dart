/// Done, pressed on a reminder or ticked on the home screen's Today: the item's box ticked in its note, as a tap on
/// the box ticks it (lib/editor/commands/task_toggle.dart `toggleBox`: the `x`, and a card on a board moved to Done
/// with it), or a ticket's status set to its workflow's done. Pure, over a body: whoever holds the library writes the
/// answer through its one save (lib/root/phone_extras.dart, or reminders/background_tick.dart with the app closed).
///
/// The item is found by its line and its words: the line it was on when the phone was handed it, and where lines
/// have been written above it since, the first line further on or back whose words are its words.
library;

import '../core/boards.dart' show settleTicks;
import '../core/item_syntax.dart' show lineWords, taskBox;
import '../core/note_facts.dart';
import '../core/properties.dart' show StatusCategory, defaultStatuses, statusCategory, withStatus;
import '../core/task_fields.dart' show withoutFields;

/// The words a line says, as an item is matched by them.
String itemWords(String line) => withoutFields(lineWords(line));

/// The line, counting from 1, where the item said as [words] is now: [line] where its words still are, else the
/// nearest line whose words are; null where none is.
int? findItem(String body, int line, String words) {
  final lines = body.split('\n');
  if (line >= 1 && line <= lines.length && itemWords(lines[line - 1]) == words) return line;
  if (words.isEmpty) return null;
  int? best;
  for (var index = 0; index < lines.length; index += 1) {
    if (itemWords(lines[index]) != words) continue;
    if (best == null || (index + 1 - line).abs() < (best - line).abs()) best = index + 1;
  }
  return best;
}

/// The line, counting from 1, where the item whose words begin [find] is now (a link carries the first eighty
/// characters of them): [line] where they still begin there, else the nearest line where they do; [line] itself
/// where none does, since the note may simply say it some other way now.
int findItemNear(String body, int line, String find) {
  final lines = body.split('\n');
  bool says(int number) => number >= 1 && number <= lines.length && itemWords(lines[number - 1]).startsWith(find);
  if (find.isEmpty || says(line)) return line;
  int? best;
  for (var number = 1; number <= lines.length; number += 1) {
    if (says(number) && (best == null || (number - line).abs() < (best - line).abs())) best = number;
  }
  return best ?? line;
}

/// [body] with the to-do on [line] ticked, and the boards it is on settled as a tap on its box settles them; null
/// where that line has no box, or its box is ticked already.
String? tickedOn(String body, int line) {
  final lines = body.split('\n');
  if (line < 1 || line > lines.length) return null;
  final text = lines[line - 1];
  final box = taskBox(text);
  if (box == null || box.done) return null;
  final settled = settleTicks(body, {line: true});
  lines[line - 1] = '${text.substring(0, box.at + 1)}x${text.substring(box.at + 2)}';
  // The anchor at the end of its line, as the editor puts it there.
  for (final named in settled.lines) {
    if (named.number >= 1 && named.number <= lines.length) lines[named.number - 1] = '${lines[named.number - 1]} ^${named.anchor}';
  }
  // A fence's lines between its two fences, the last fence first so the line numbers above stay where they are.
  final fences = [...settled.fences]..sort((a, b) => b.from.compareTo(a.from));
  for (final fence in fences) {
    if (fence.from < 1 || fence.to > lines.length || fence.to <= fence.from + 1) continue;
    lines.replaceRange(fence.from, fence.to - 1, fence.body.split('\n'));
  }
  return lines.join('\n');
}

/// The status a workflow is done at: its first that stands as done, or Done.
String doneStatus(List<String>? statuses) {
  final workflow = statuses ?? defaultStatuses;
  for (final status in workflow) {
    if (statusCategory(status, workflow) == StatusCategory.done) return status;
  }
  return 'Done';
}

/// A ticket's body with its status set to its workflow's done; null where it is not a ticket or is done already.
String? ticketDone(String body, List<String>? statuses) {
  final facts = NoteFacts.read(body);
  final ticket = facts.isTicket ? facts.ticket : null;
  if (ticket == null || statusCategory(ticket.status, statuses ?? defaultStatuses) == StatusCategory.done) return null;
  return withStatus(body, doneStatus(statuses), workflow: statuses ?? defaultStatuses);
}

/// Done for the item on [line] said as [words] (0 for a ticket, whose [statuses] are its notebook's workflow): the
/// body as it is to be written, or null where there is nothing to tick.
String? doneIn(String body, {required int line, required String words, List<String>? statuses}) {
  if (line == 0) return ticketDone(body, statuses);
  final found = findItem(body, line, words);
  return found == null ? null : tickedOn(body, found);
}

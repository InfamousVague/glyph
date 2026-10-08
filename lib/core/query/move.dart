/// A card dragged into another lane of a query's board, in a note that is not the one on screen (the open note's
/// own are written in its editor). A port of `src/app/core/query/move.ts`. The grouped field is set to the lane's
/// value, or cleared with null for the "No …" lane: a ticket's or a record's front-matter property (properties.dart
/// `withProperty`), a to-do's inline field (task_fields.dart `withField`).
///
/// The to-do's line is found where the query read it, or, where the note has moved since, by its words as the query
/// read them; a line that is gone is left alone (null), rather than the wrong one written. A write that changes
/// nothing gives the body back unchanged. Pure.
library;

import '../properties.dart' show withProperty;
import '../task_fields.dart' show fieldsOf, withAssignee, withField;
import 'records.dart' show RecordKind;

/// A to-do's line with one field set, or cleared with null, through the one writer of a line's fields
/// (task_fields.dart `withField`). Its assignee is its people, written `@sam`, not a named field: setting it takes
/// off whoever is there and puts the one named on, so a query's person picker replaces the person as a ticket's
/// does.
String withTaskField(String line, String field, String? value) {
  if (field.toLowerCase() == 'assignee') {
    var cleared = line;
    for (final name in fieldsOf(line).assignees) {
      cleared = withAssignee(cleared, name, false);
    }
    return value != null && value.isNotEmpty ? withAssignee(cleared, value) : cleared;
  }
  return withField(line, field, value);
}

String? movedBody(String body, int line, String source, RecordKind kind, String field, String? value) {
  if (kind == RecordKind.task) {
    final lines = body.split('\n');
    final at = line >= 0 && line < lines.length && lines[line] == source ? line : lines.indexOf(source);
    if (at < 0) return null;
    final text = lines[at];
    final next = withTaskField(text, field, value);
    if (next == text) return body;
    lines[at] = next;
    return lines.join('\n');
  }
  return withProperty(body, field, value);
}

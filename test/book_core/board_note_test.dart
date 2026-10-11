import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/board_note.dart';
import 'package:ghost_md/core/boards.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;

/// The example board (lib/core/board_note.dart). The web has no test of `core/boardNote.ts` of its own; this holds
/// the note to what its words promise: it is the standard and nothing else, so the door reads two boards out of it.
void main() {
  test('is a note the boards read: its title, two fences, and every card an item of the note', () {
    final body = boardNoteBody();
    expect(noteTitle(body), boardTitle);
    final boards = boardsIn(body);
    expect([for (final board in boards) [for (final column in board.columns) column.name]], [
      ['This week', 'Waiting on Sam', 'Done'],
      ['Someday'],
    ]);
    final anchors = {for (final item in itemsIn(body)) item.id};
    for (final board in boards) {
      for (final column in board.columns) {
        expect(anchors, containsAll(column.cards), reason: column.name);
      }
    }
    expect([for (final lane in lanesOf(body)) lane.name], ['This week', 'Waiting on Sam', 'Done', 'Someday']);
    expect(body, endsWith('- [ ] Find a venue for the party ^venue\n'));
  });
}

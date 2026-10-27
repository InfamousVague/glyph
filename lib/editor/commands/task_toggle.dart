/// A tap on a to-do's box ticks it, and another clears it (Matt: "add ability to tap on todo list item to toggle the
/// x on and off"). Only the box: the words beside it are for writing, and a tap there puts the caret in them as
/// ever. The pure half of `src/app/editor/taskToggle.ts`, with `settleFences` of `src/app/editor/boards.ts`, which
/// its edit is made with.
///
/// The change is an ordinary edit - one undo, saved like typing - so a linked to-do's task follows it the way it
/// follows a box typed by hand.
///
/// What differs: the press itself (`taskToggle()`'s mousedown handler, `boxUnder`, and boxTaps.ts's `plainPress`
/// and `tapsRange`, which ask the view where a tap landed, with eight pixels of slop) is the view's; it calls
/// [boxAt] with the position under the tap and dispatches [toggleBox], then fires the `selection` haptic.
/// [settleFences] lives here until the boards' own editor piece (stage 5) has a home for it.
library;

import '../../core/boards.dart';
import '../../core/item_syntax.dart';
import '../../sounds/sound_pack.dart' show SoundEvent;
import '../../sounds/sounds.dart' show sounds;
import '../state/change.dart';
import '../state/state.dart';

/// The box on the line at `pos` (core/item_syntax.dart [taskBox]): where its brackets are and whether it's ticked,
/// or null.
({int from, int to, bool done})? boxAt(EditorState state, int pos) {
  final line = state.doc.lineAt(pos);
  final box = taskBox(line.text);
  if (box == null) return null;
  final from = line.from + box.at;
  return (from: from, to: from + 3, done: box.done);
}

/// The changes that bring every fence in the note back in step with its ticks, for a box turned somewhere other
/// than the board: a tap in the list or a task going Done in Notion. `ticks` is each item's line, counting from 1,
/// and the state its box is being set to; several at once are fine.
///
/// An item that is not a card, ticked in a list whose neighbours are on a board, joins that board in Done, and its
/// line gains the anchor that names it (core/boards.dart `settleTicks`).
///
/// Put them in the same transaction as the boxes themselves, so the note and its boards change together, as one
/// undo. Empty when nothing has to move, which is the usual answer.
List<ChangeSpec> settleFences(EditorState state, Map<int, bool> ticks) {
  final settled = settleTicks(state.doc.toString(), ticks);
  return <ChangeSpec>[
    for (final edit in settled.fences)
      ChangeSpec(from: state.doc.line(edit.from).to + 1, to: state.doc.line(edit.to).from - 1, insert: edit.body),
    // The anchor is put at the END of the item's line rather than the line written again, so it can never overlap
    // the one character the tick itself is changing at the start of it.
    for (final line in settled.lines) ChangeSpec(from: state.doc.line(line.number).to, insert: ' ^${line.anchor}'),
  ];
}

/// The same line with its box turned: an `x` in an empty one, a space in a ticked one. An item that is a card on a
/// board moves with it - ticked into Done, cleared back to the first lane - in the same edit and the same undo, so
/// the fence never drifts from the ticks ([settleFences]). `box` is what [boxAt] answered.
Transaction toggleBox(EditorState state, ({int from, int to, bool done}) box) {
  final line = state.doc.lineAt(box.from).number;
  // The tick's sound (Settings › Sounds; Matt, 2026-10-27): here, since every way a box is tapped comes through here
  // (the editor's handler, its gestures, a screen reader's tap, a query's list), and only as it is ticked, not cleared.
  if (!box.done) sounds.play(SoundEvent.todoTicked);
  return state.update(
    TransactionSpec(
      changes: <ChangeSpec>[
        ChangeSpec(from: box.from + 1, to: box.from + 2, insert: box.done ? ' ' : 'x'),
        ...settleFences(state, <int, bool>{line: !box.done}),
      ],
      userEvent: 'input.toggle',
    ),
  );
}

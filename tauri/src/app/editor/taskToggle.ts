import type { EditorState, Extension } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { fireNativeHaptic } from '../core/haptics.ts';
import { taskBox } from '../core/itemSyntax.ts';
import { settleFences } from './boards.ts';
import { plainPress, tapsRange } from './boxTaps.ts';

/**
 * A tap on a to-do's box ticks it, and another clears it (Matt: "add ability to tap on todo list item to toggle the x
 * on and off"). Only the box: the words beside it are for writing, and a tap there puts the caret in them as ever.
 *
 * The change is an ordinary edit - one undo, saved like typing - so a linked to-do's task follows it the way it
 * follows a box typed by hand (editor/doneSync.ts).
 */

/** The box on the line at `pos` (core/itemSyntax.ts `taskBox`): where its brackets are and whether it's ticked, or null. */
export function boxAt(state: EditorState, pos: number): { from: number; to: number; done: boolean } | null {
  const line = state.doc.lineAt(pos);
  const box = taskBox(line.text);
  if (!box) return null;
  const from = line.from + box.at;
  return { from, to: from + 3, done: box.done };
}

/**
 * The same line with its box turned: an `x` in an empty one, a space in a ticked one. An item that is a card on a
 * board moves with it - ticked into Done, cleared back to the first lane - in the same edit and the same undo, so the
 * fence never drifts from the ticks (editor/boards.ts `settleFences`).
 */
export function toggleBox(state: EditorState, box: { from: number; done: boolean }) {
  const line = state.doc.lineAt(box.from).number;
  return state.update({
    changes: [{ from: box.from + 1, to: box.from + 2, insert: box.done ? ' ' : 'x' }, ...settleFences(state, new Map([[line, !box.done]]))],
    userEvent: 'input.toggle',
  });
}

/** The box a tap at `x`, `y` lands on (editor/boxTaps.ts), or null. */
function boxUnder(view: EditorView, x: number, y: number) {
  const pos = view.posAtCoords({ x, y }, false);
  const box = boxAt(view.state, pos);
  return box && tapsRange(view, x, y, box.from, box.to) ? box : null;
}

export function taskToggle(): Extension {
  return EditorView.domEventHandlers({
    mousedown(event, view) {
      if (!plainPress(event, view)) return false;
      const box = boxUnder(view, event.clientX, event.clientY);
      if (!box) return false;
      // Taken here, before the caret moves: a tap on the box ticks it and leaves the caret where it was.
      event.preventDefault();
      view.dispatch(toggleBox(view.state, box));
      fireNativeHaptic('selection');
      return true;
    },
  });
}

import type { EditorView } from '@codemirror/view';

/**
 * A tap on a box drawn in the words: a to-do's `[ ]` (editor/taskToggle.ts) or a choice's `( )` (editor/choices.ts).
 * Both answer a plain press of the main button in a note that can be edited, landing on the box's three characters or
 * within a thumb's slop of them, and both take the press before the caret moves.
 */

/** How far outside the drawn box a tap still counts, in px: a box is small under a thumb. */
const SLOP_PX = 8;

/** Whether `event` is a plain press - the main button, no modifier - in a note that can be changed. */
export function plainPress(event: MouseEvent, view: EditorView): boolean {
  return event.button === 0 && !view.state.readOnly && !event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey;
}

/** Whether a tap at `x`, `y` lands on the characters `from`-`to`, or near enough to them. */
export function tapsRange(view: EditorView, x: number, y: number, from: number, to: number): boolean {
  const start = view.coordsAtPos(from, 1);
  const end = view.coordsAtPos(to, -1);
  if (!start || !end) return false;
  return x >= start.left - SLOP_PX && x <= end.right + SLOP_PX && y >= start.top - SLOP_PX && y <= start.bottom + SLOP_PX;
}

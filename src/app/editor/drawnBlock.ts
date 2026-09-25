import { StateEffect, StateField, type EditorState, type Extension, type Transaction } from '@codemirror/state';
import { EditorView } from '@codemirror/view';

/**
 * What every block drawn in place of its markdown shares: a table (editor/tables.ts), a diagram (editor/mermaid.ts),
 * a canvas's frame (editor/canvasFrames.ts) and a board (editor/boards.ts).
 *
 * Each is drawn while the caret is elsewhere and steps aside for its lines while the caret is in them, and a tap on
 * the drawing puts the caret there. So each needs to know, from inside a state field, whether the view has focus:
 * block decorations have to come from a state field, not a view plugin, and a field cannot ask the view. Focus is
 * therefore kept in a field of its own from `EditorView.focusChangeEffect`. The four blocks each kept a copy of that
 * field and of the effect that feeds it; this is the one, and a view that draws several kinds of block holds it once,
 * since CodeMirror installs the same extension a single time however many times it is listed.
 */

const setFocus = StateEffect.define<boolean>();

/** Whether the view has focus, as the last focus change said: false until it is first focused. */
const focusField = StateField.define<boolean>({
  create: () => false,
  update(focused, tr) {
    for (const effect of tr.effects) if (effect.is(setFocus)) return effect.value;
    return focused;
  },
});

/** The focus field and what feeds it: installed by each drawn block, held once. */
export const trackFocus: Extension = [focusField, EditorView.focusChangeEffect.of((_state, focusing) => setFocus.of(focusing))];

/** Whether the view has focus, for a state field that has to decide what to draw. */
export function focused(state: EditorState): boolean {
  return state.field(focusField, false) ?? false;
}

/** Whether `tr` is the view gaining or losing focus, which moves every drawn block's decision. */
export function focusMoved(tr: Transaction): boolean {
  return tr.effects.some((effect) => effect.is(setFocus));
}

/**
 * Whether the caret is in `from`-`to`, edges included, in a focused view: the block's lines are shown there, to be
 * typed in, rather than its drawing. A view with no caret - never focused, or left - draws every block.
 */
export function caretIn(state: EditorState, from: number, to: number): boolean {
  return focused(state) && state.selection.ranges.some((range) => range.to >= from && range.from <= to);
}

/**
 * A press on `element` puts the caret at `at`, the block's first line, so the drawing steps aside and its markdown
 * can be edited. A view that cannot be edited (the Formatted view) keeps the drawing: there is nothing to type.
 */
export function openOnPress(view: EditorView, element: HTMLElement, at: number): void {
  element.addEventListener('mousedown', (event) => {
    if (!view.state.facet(EditorView.editable)) return;
    event.preventDefault();
    view.dispatch({ selection: { anchor: at } });
    view.focus();
  });
}

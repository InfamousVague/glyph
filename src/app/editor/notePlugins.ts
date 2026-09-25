import type { EditorView } from '@codemirror/view';
import { plugins } from '../plugins/registry.ts';
import type { NoteEditing } from '../plugins/types.ts';
import type { LineSuggestion } from './suggestions.ts';
import type { SwipeAction } from './swipeItems.ts';

/**
 * How plugins reach the open note (plugins/types.ts): through the editor, so each change a plugin makes is one undo
 * and saves like typing, and anything a plugin has to say shows on the note the way a picture's problem does
 * (editor/useNotePictures.ts).
 *
 * Plain functions over the view rather than a hook: the note screen builds them on each render, and the editor reads
 * the ones it is given through refs at the moment they are used (editor/Editor.tsx), so a plugin switched on or off
 * is followed without the editor being rebuilt.
 */

/**
 * The note as plugins change it. `view` is the editor, when there is one; `body` answers the live document when there
 * is not (a canvas or a book drawn in its place); `say` puts a sentence on the note.
 */
export function noteEditing(noteId: string, view: EditorView | null, body: () => string, say: (message: string) => void): NoteEditing {
  return {
    noteId,
    body: () => view?.state.doc.toString() ?? body(),
    replaceLine(find, next) {
      const doc = view?.state.doc;
      if (!view || !doc) return false;
      for (let n = 1; n <= doc.lines; n += 1) {
        const line = doc.line(n);
        if (find(line.text, n)) {
          view.dispatch({
            changes: { from: line.from, to: line.to, insert: next(line.text) },
          });
          return true;
        }
      }
      return false;
    },
    say,
  };
}

/**
 * What a plugin does with one of this note's items, where one takes them (a Notion board, a GitHub issue): the swipe on
 * an item (editor/swipeItems.ts) and the press-and-hold menu's send (editor/ContextMenu.tsx) are the same action.
 * Null where no switched-on plugin takes this note's items.
 */
export function itemSend(noteId: string, editing: NoteEditing): SwipeAction | null {
  const action = plugins.itemAction(noteId);
  return action
    ? {
        label: action.label,
        busyLabel: action.busyLabel,
        run: (text) => action.run(text, editing),
      }
    : null;
}

/** The quiet words after lines a plugin could act on (editor/suggestions.ts), for the note's words as they are now. */
export function lineOffers(noteId: string, editing: NoteEditing, text: string): LineSuggestion[] {
  return plugins.suggestions(noteId, text).map((s) => ({
    line: s.line,
    label: s.label,
    busyLabel: s.busyLabel,
    run: () => s.run(editing),
  }));
}

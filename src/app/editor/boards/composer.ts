import type { EditorView } from '@codemirror/view';
import { fireNativeHaptic } from '../../core/haptics.ts';
import { newCard } from '../../core/boards.ts';

/**
 * The + on a column: a field at the top of it, for the new card's words (Matt: "a button on each board to add an
 * item, it should add the item to the list the board is derived from").
 *
 * The words are asked for before anything is written, and Enter writes the item under the board's last one with an
 * anchor named after them, and the card at the top of this column (core/boards.ts `newCard`). The field stays open
 * and empty for the next card; Escape, or leaving it empty, closes it. Nothing goes into the note's own lines by
 * the caret, so the line is always a proper task item, `- [ ] words ^anchor`.
 */
export function openComposer(view: EditorView, pane: HTMLElement, name: string): void {
  const already = pane.querySelector<HTMLInputElement>(':scope > .cm-boardCompose input');
  if (already) {
    already.focus();
    return;
  }
  const form = document.createElement('form');
  form.className = 'cm-boardCompose';
  // A form with a text field and a submit button is what a password manager watches for: 1Password and the rest
  // offered to save a login every time a card was added (Matt: "New Tasks are popping password manager save modal").
  // These say what it really is, in each of the ways they read.
  form.setAttribute('autocomplete', 'off');
  form.setAttribute('data-form-type', 'other');
  form.setAttribute('data-1p-ignore', '');
  form.setAttribute('data-lpignore', 'true');
  const field = document.createElement('input');
  field.type = 'text';
  field.className = 'cm-boardComposeField';
  field.placeholder = 'New card';
  field.enterKeyHint = 'done';
  field.autocapitalize = 'sentences';
  field.name = 'card';
  field.autocomplete = 'off';
  field.setAttribute('data-form-type', 'other');
  field.setAttribute('data-1p-ignore', '');
  field.setAttribute('data-lpignore', 'true');
  field.setAttribute('aria-label', `New card in ${name}`);
  const add = document.createElement('button');
  add.type = 'submit';
  add.className = 'cm-boardComposeAdd';
  add.textContent = 'Add';
  add.disabled = true;
  // Pressing Add must not take the focus from the field first, or the phone's keyboard drops between cards.
  add.addEventListener('mousedown', (event) => event.preventDefault());
  // Where the card's tick box goes, so the words typed start where a card's words do.
  const box = document.createElement('span');
  box.className = 'cm-boardComposeTick';
  box.setAttribute('aria-hidden', 'true');
  const ready = () => {
    add.disabled = !field.value.trim();
  };
  field.addEventListener('input', ready);
  form.append(box, field, add);

  const close = () => form.remove();
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const board = pane.closest('.cm-board');
    if (!board || !field.value.trim()) return;
    // Read where the board is now, not where it was when the field opened: the note may have changed above it.
    const open = view.state.doc.lineAt(view.posAtDOM(board)).number;
    if (!addCard(view, open, Number(pane.dataset.column ?? 0), field.value)) return;
    field.value = '';
    ready();
    fireNativeHaptic('selection');
  });
  field.addEventListener('keydown', (event) => {
    // Enter adds the card itself: a form inside the note's editable page is not sent by Enter on every browser, and
    // a keyboard still composing a word is left to finish it.
    if (event.key === 'Enter' && !event.isComposing) {
      event.preventDefault();
      form.requestSubmit();
    } else if (event.key === 'Escape') {
      event.preventDefault();
      close();
    }
  });
  field.addEventListener('blur', () => {
    if (field.value.trim()) return;
    window.setTimeout(() => {
      if (document.activeElement !== field) close();
    }, 150);
  });

  pane.querySelector(':scope > .cm-boardName')?.after(form);
  field.focus();
}

/** A card with these words in column `column` of the board that opens on line `open`: the fence and the new line together. */
function addCard(view: EditorView, open: number, column: number, words: string): boolean {
  const made = newCard(view.state.doc.toString(), open, column, words);
  if (!made) return false;
  const doc = view.state.doc;
  const top = doc.line(made.fence.from);
  const bottom = doc.line(made.fence.to);
  const end = made.at > doc.lines;
  const at = end ? doc.length : doc.line(made.at).from;
  // At the end of a note that does not end in a newline, the line needs one of its own in front of it.
  const tail = doc.length ? view.state.sliceDoc(doc.length - 1) : '\n';
  const insert = end ? `${tail === '\n' ? '' : '\n'}${made.text}` : `${made.text}\n`;
  view.dispatch({
    changes: [
      { from: top.to + 1, to: bottom.from - 1, insert: made.fence.body },
      { from: at, insert },
    ],
    userEvent: 'input.board',
  });
  return true;
}

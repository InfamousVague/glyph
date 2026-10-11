import { RangeSetBuilder, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, type DecorationSet } from '@codemirror/view';
import { itemAt, itemOnLine, itemsIn, refsIn } from '../../core/boards.ts';
import { anchorSpan } from '../../core/itemSyntax.ts';
import { goToLine } from './navigate.ts';

/**
 * The anchor on a line, and a pointer at one from the words (core/boards.ts).
 *
 * `^ship-page` at the end of an item is a name, not something to read: it is drawn small and faint, so the line
 * reads as its words. `[[#^ship-page]]` in the middle of a line is the other end of the same thing - a tap on it
 * goes to the item it names, wherever in the note that is.
 */
const anchorMark = Decoration.mark({ class: 'cm-itemAnchor' });
const refMark = Decoration.mark({ class: 'cm-itemRef' });
const goneMark = Decoration.mark({ class: 'cm-itemRef cm-itemRefGone' });

function anchors(state: EditorState): DecorationSet {
  const doc = state.doc.toString();
  const builder = new RangeSetBuilder<Decoration>();
  const named = new Set(itemsIn(doc).map((item) => item.id));
  for (let line = 1; line <= state.doc.lines; line += 1) {
    const at = state.doc.line(line);
    const marks: { from: number; to: number; mark: Decoration }[] = [];
    // The `^anchor` naming the item on the line - last, or with an item's mark after it (core/itemSyntax.ts).
    const anchor = itemOnLine(at.text) ? anchorSpan(at.text) : null;
    if (anchor) marks.push({ from: at.from + anchor.from, to: at.from + anchor.to, mark: anchorMark });
    for (const ref of refsIn(at.text, at.from)) marks.push({ from: ref.from, to: ref.to, mark: named.has(ref.id) ? refMark : goneMark });
    for (const mark of marks.sort((one, two) => one.from - two.from)) builder.add(mark.from, mark.to, mark.mark);
  }
  return builder.finish();
}

const anchorField = StateField.define<DecorationSet>({
  create: (state) => anchors(state),
  update: (value, tr) => (tr.docChanged ? anchors(tr.state) : value.map(tr.changes)),
  provide: (field) => EditorView.decorations.from(field),
});

/** A tap on `[[#^anchor]]`: the caret goes to the item it names. */
const refTaps = EditorView.domEventHandlers({
  mousedown(event, view) {
    const target = event.target as HTMLElement | null;
    if (!target?.classList.contains('cm-itemRef')) return false;
    const at = view.posAtDOM(target);
    const line = view.state.doc.lineAt(at);
    const ref = refsIn(line.text, line.from).find((found) => found.from <= at + 2 && found.to >= at);
    const item = ref ? itemAt(view.state.doc.toString(), ref.id) : null;
    if (!item) return false;
    event.preventDefault();
    goToLine(view, item.line);
    return true;
  },
});

/** Anchors drawn quiet, pointers at them drawn as links, and a tap on a pointer going to its item. */
export const itemAnchors: Extension = [anchorField, refTaps];

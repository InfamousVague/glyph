import { StateEffect, type Extension } from '@codemirror/state';
import { ViewPlugin, type EditorView, type ViewUpdate } from '@codemirror/view';
import { boardsIn, itemsIn } from '../core/boards.ts';
import { itemWords, markOf } from '../core/itemLinks.ts';
import { markNameFor, onMarkDetails, wantMarkDetails } from '../core/markDetails.ts';
import { forEachVisibleLine } from './lines.ts';

/**
 * Asking the plugins what the note's linked things are doing, and telling the note when they answer.
 *
 * A mark (core/itemLinks.ts) or a link a plugin reads is drawn from what that plugin knows (core/markDetails.ts): the
 * pill at the end of an item (editor/links.ts), the row of pills under it (editor/linkedRows.ts), and the box that
 * follows its task (editor/doneSync.ts). This is what keeps that knowledge fresh: the details of every linked thing in
 * view, and of every open card on a board in view, are asked for on opening, on coming back to the front, once a
 * minute while the note is open, and whenever the note changes or scrolls. The plugin decides whether a read is due.
 *
 * Answers arrive outside any update, so each is passed on as its own transaction, `detailsArrived`, at most once a
 * frame; everything that draws from the details redraws on it.
 */

/** Details arrived from a plugin: redraw the pills and rows. */
export const detailsArrived = StateEffect.define<null>();

const LINK = /\[[^\]]*\]\((https?:\/\/[^\s)]+)\)/g;

/** Every linked thing in view, marks and links a plugin reads, for reading their details again. */
function marksInView(view: EditorView): { name: string; url: string }[] {
  const marks: { name: string; url: string }[] = [];
  forEachVisibleLine(view, (line) => {
    const mark = itemWords(line.text) !== null ? markOf(line.text) : null;
    if (mark) marks.push(mark);
    else if (line.text.includes('](')) {
      for (const match of line.text.matchAll(LINK)) {
        const name = markNameFor(match[1] ?? '');
        if (name) marks.push({ name, url: match[1] ?? '' });
      }
    }
  });
  return [...marks, ...marksOnBoards(view)];
}

/**
 * The marks of the open to-dos on every board on screen.
 *
 * A board is drawn as one block in place of its fence (editor/boards.ts), so its lines are not among `visibleRanges`,
 * and its cards are items written further down the note, usually well out of view. Read only by their own lines, a
 * board being looked at never learned its tasks were done, so it never moved them (Matt: "a lot of the notion tickets
 * aren't moved to done"): his board had four cards in To do whose tasks were all Done in Notion, their items sixty
 * lines below it, and not one was read until they were scrolled to - then all four ticked and went to Done at once.
 *
 * Only the cards not ticked yet: what a board shows of a task is whether it is done, and those are the cards that can
 * move. The rest are read as ever when their own lines are in view. His board holds 66 cards, and reading every one
 * each minute the note is open would spend a third of what Notion allows Glyph, for four that could change.
 */
function marksOnBoards(view: EditorView): { name: string; url: string }[] {
  const { doc } = view.state;
  const { viewport } = view;
  const text = doc.toString();
  const shown = boardsIn(text).filter((board) => doc.line(board.from).from <= viewport.to && doc.line(board.to).to >= viewport.from);
  if (!shown.length) return [];
  const open = new Map(itemsIn(text).filter((item) => item.done === false).map((item) => [item.id, item.line]));
  const marks: { name: string; url: string }[] = [];
  for (const board of shown) {
    for (const column of board.columns) {
      for (const id of column.cards) {
        const number = open.get(id);
        const line = number === undefined ? null : doc.line(number).text;
        const mark = line !== null && itemWords(line) !== null ? markOf(line) : null;
        if (mark) marks.push(mark);
      }
    }
  }
  return marks;
}

/** How often an open note reads its tasks again, while it is on screen. */
const REREAD_MS = 60_000;

/**
 * The reads, and the redraw their answers bring. `still`: nothing is ever asked for, and the note is drawn from what
 * is already known - a note drawn small on a card - though an answer that arrives is still drawn.
 */
export function markReads({ still }: { still: boolean }): Extension {
  return ViewPlugin.fromClass(
    class {
      private readonly off: () => void;
      private readonly timer: number | null;
      private queued = false;

      constructor(readonly view: EditorView) {
        this.off = onMarkDetails(() => this.redraw());
        if (still) {
          this.timer = null;
          return;
        }
        this.timer = window.setInterval(() => this.want(false), REREAD_MS);
        document.addEventListener('visibilitychange', this.onVisible);
        this.want(false);
      }

      private readonly onVisible = () => {
        if (document.visibilityState === 'visible') this.want(false);
      };

      /** Asks for the details of the marks in view: read again if old, or now. */
      private want(fresh: boolean) {
        if (document.visibilityState === 'hidden') return;
        for (const mark of marksInView(this.view)) wantMarkDetails(mark.name, mark.url, fresh);
      }

      /** Answers arrive outside an update; the redraw is its own transaction, once per frame. */
      private redraw() {
        if (this.queued) return;
        this.queued = true;
        window.requestAnimationFrame(() => {
          this.queued = false;
          if (this.view.dom.isConnected) this.view.dispatch({ effects: detailsArrived.of(null) });
        });
      }

      update(update: ViewUpdate) {
        // While an IME composes, nothing is asked: the composition's end is a change of its own (editor/glyphLines.ts).
        if (still || update.view.composing) return;
        // A mark just made or scrolled to is read; one already read recently is not.
        if (update.docChanged || update.viewportChanged) this.want(false);
      }

      destroy() {
        this.off();
        if (this.timer !== null) window.clearInterval(this.timer);
        document.removeEventListener('visibilitychange', this.onVisible);
      }
    },
  );
}

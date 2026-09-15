import { Transaction, type Extension, type Text } from '@codemirror/state';
import { EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import { onMarkDetails, peekMarkDetails } from '../core/markDetails.ts';
import { linkedOn } from './linkedRows.ts';

/**
 * A to-do whose task is done gets its box ticked.
 *
 * Matt: "Notion items that are done should automatically update the checked
 * status of the checkbox for the item they're listed in." A linked item ends
 * with a mark (core/itemLinks.ts), and the plugin behind the mark reads the
 * task back for the pill (core/markDetails.ts). When what it reads says the
 * task is done and the line still says `- [ ]`, the box becomes `- [x]`, as
 * if it had been tapped: an edit to the note, saved like typing, not part of
 * the undo history (undoing a keystroke should not untick a task that Notion
 * says is finished). An item linked the old way, its words the link, is
 * ticked the same (linkedOn, editor/linkedRows.ts).
 *
 * Only that way round, and once per change of the task: a box unticked by
 * hand stays unticked until the task itself changes again, so the note never
 * fights the person holding it. Nothing is read here; the pills' own reads
 * (editor/links.ts) are what arrive, for the marks in view while the note is
 * open.
 */

/** An unticked to-do: its indent and bullet, then the open box. */
const OPEN_BOX = /^(\s*[-*+] )\[ \] /;

export interface Tick {
  /** The space inside the box. */
  from: number;
  to: number;
  url: string;
  /** When the task last changed as the service says it, or when it was read: the change this tick answers. */
  stamp: number;
}

/** The boxes to tick now: unticked to-dos whose mark's task reads as done, and not already ticked for that change. */
export function ticksDue(doc: Text, acted: ReadonlyMap<string, number>): Tick[] {
  const ticks: Tick[] = [];
  for (let n = 1; n <= doc.lines; n += 1) {
    const line = doc.line(n);
    const box = OPEN_BOX.exec(line.text);
    if (!box) continue;
    const mark = linkedOn(line.text);
    if (!mark?.item) continue;
    const entry = peekMarkDetails(mark.name, mark.url);
    if (entry?.state !== 'ready') continue;
    const { details } = entry;
    if (details.gone || details.status?.stage !== 'done') continue;
    const stamp = details.editedAt ?? details.readAt;
    if (acted.get(mark.url) === stamp) continue;
    const at = line.from + (box[1] ?? '').length + 1;
    ticks.push({ from: at, to: at + 1, url: mark.url, stamp });
  }
  return ticks;
}

export function doneSync(): Extension {
  return ViewPlugin.fromClass(
    class {
      private readonly acted = new Map<string, number>();
      private readonly off: () => void;
      private timer = 0;
      private gone = false;

      constructor(readonly view: EditorView) {
        this.off = onMarkDetails(() => this.later());
        this.later();
      }

      update(update: ViewUpdate): void {
        // A mark pasted or typed in, or a composition ending: look again.
        if (update.docChanged) this.later();
      }

      destroy(): void {
        this.gone = true;
        this.off();
        window.clearTimeout(this.timer);
      }

      /** Answers arrive outside an update, and a change cannot be dispatched from inside one: the tick is its own turn. */
      private later(): void {
        if (this.timer) return;
        this.timer = window.setTimeout(() => {
          this.timer = 0;
          this.sync();
        }, 0);
      }

      private sync(): void {
        // While an IME composes, the document is not touched (glyphLines.ts); the composition's end brings a doc change.
        if (this.gone || this.view.composing) return;
        const ticks = ticksDue(this.view.state.doc, this.acted);
        if (!ticks.length) return;
        for (const tick of ticks) this.acted.set(tick.url, tick.stamp);
        this.view.dispatch({
          changes: ticks.map(({ from, to }) => ({ from, to, insert: 'x' })),
          annotations: [Transaction.addToHistory.of(false), Transaction.userEvent.of('sync.tick')],
        });
      }
    },
  );
}

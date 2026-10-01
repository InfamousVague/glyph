import { RangeSetBuilder, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet } from '@codemirror/view';
import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { isoDay } from '../core/days.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { taskBox } from '../core/itemSyntax.ts';
import { queryFencesIn, withQueryHeight } from '../core/query/fence.ts';
import { readQuery } from '../core/query/read.ts';
import { libraryOf, recordCache, type QueryNote, type RecordCache } from '../core/query/records.ts';
import { runQuery, type Row } from '../core/query/run.ts';
import { caretIn, focusMoved, trackFocus } from './drawnBlock.ts';
import { fieldChipTheme } from './fieldChips.ts';
import { QueryView } from './QueryView.tsx';
import { toggleBox } from './taskToggle.ts';

/**
 * A ```query fence, drawn as what it finds (docs/QUERIES.md, docs/DESIGN.md §159). Matt asked what "notion and jira
 * like features" Markdown could give the app and took the database view among the first three: a fence of a few
 * lines, `from: tickets #bug`, `where: status != Done`, `show: board`, which any other app shows as the lines it is.
 *
 * The lines are read by core/query/read.ts and run over the library by core/query/run.ts; this is where the result is
 * drawn, in place of the fence, the way a board, a table and a diagram are drawn in place of theirs
 * (editor/drawnBlock.ts): the caret in the fence steps the drawing aside so the lines can be typed, and the pencil at
 * its head puts the caret there. A query that cannot be read is drawn as its lines and the sentence that says what is
 * wrong and where.
 *
 * **Live.** A query reads every note the screen hands it (`QueryOptions.notes`), the open note as its editor has it, so
 * a to-do typed under a query of to-dos is in it at once; and it is drawn again whenever the library changes
 * (`refreshQueries`), the note changes, and at midnight, when `today` moves. A note's reading is kept while its words
 * stay the same (core/query/records.ts `RecordCache`, one per editor), so a keystroke reads one note again, not all.
 *
 * **What a tap does.** A note or a ticket opens; a to-do opens its note at its line, or, in this note, puts the caret
 * there. A to-do's box ticks it where it is written: in this note with the same edit a tap on the box makes
 * (editor/taskToggle.ts `toggleBox`, its boards settled in the same undo), and in another through the screen
 * (`QueryOptions.tick`, core/query/tick.ts). Nothing else in a drawn query writes anything.
 */

/** What the screen hands the editor for its queries: the library, and how to reach and tick what a query lists. */
export interface QueryOptions {
  /** Every note a query reads: the library a screen shows, without the Trash, the archive, the Guide or templates' pages. */
  notes: () => readonly QueryNote[];
  /** The open note's id, whose words are read as its editor has them; null for a note not yet in the store. */
  noteId: string | null;
  /** Opens another note, at a to-do's line (from 0), or where it opens with null. */
  open: (noteId: string, line: number | null) => void;
  /** Ticks or clears a to-do in another note: its line as the query read it, and the line's words to find it by. */
  tick: (noteId: string, line: number, source: string, done: boolean) => void;
}

/** The library changed: every query is run and drawn again. */
export const refreshQueries = StateEffect.define<null>();

/** The library read for each editor, kept while each note's words stay the same. */
const caches = new WeakMap<EditorView, RecordCache>();

function cacheOf(view: EditorView): RecordCache {
  let cache = caches.get(view);
  if (!cache) {
    cache = recordCache();
    caches.set(view, cache);
  }
  return cache;
}

/** The library with the open note read as it is typed, and added where the store has not got it yet. */
function withOpen(notes: readonly QueryNote[], id: string | null, body: string): QueryNote[] {
  if (!id) return [...notes];
  const at = notes.findIndex((note) => note.id === id);
  if (at < 0) return [...notes, { id, body, createdAt: Date.now(), updatedAt: Date.now() }];
  const list = [...notes];
  list[at] = { ...list[at]!, body };
  return list;
}

/** A row's line in this editor: where the query read it, or where its words are now; null where it is gone. */
function lineOf(state: EditorState, row: Row): number | null {
  const at = row.line + 1;
  if (at >= 1 && at <= state.doc.lines && state.doc.line(at).text === row.source) return at;
  for (let n = 1; n <= state.doc.lines; n += 1) if (state.doc.line(n).text === row.source) return n;
  return null;
}

/** The React roots the queries are drawn in, by their element, so a change redraws the same root. */
const roots = new WeakMap<HTMLElement, Root>();

class QueryWidget extends WidgetType {
  constructor(
    readonly body: string,
    /** Where the caret goes to show the fence's lines: its first line inside. */
    readonly at: number,
    /** Moves on every change to the note or the library, which is when a query's answer can. */
    readonly stamp: number,
    readonly today: string,
    readonly editable: boolean,
    /** A board's lanes' height from the fence, in their ems; null for the board's own. */
    readonly height: number | null,
    readonly options: () => QueryOptions | null,
  ) {
    super();
  }

  eq(other: QueryWidget): boolean {
    return other.body === this.body && other.at === this.at && other.stamp === this.stamp && other.today === this.today && other.editable === this.editable && other.height === this.height;
  }

  get estimatedHeight(): number {
    return 220;
  }

  toDOM(view: EditorView): HTMLElement {
    const dom = document.createElement('div');
    dom.className = 'cm-query';
    // A press in the drawing is the drawing's, as a board's is: its default taken, so no caret lands in the note under
    // it and the drawing does not step aside. A press on a field keeps its default, to take the focus.
    dom.addEventListener('mousedown', (event) => {
      if (!(event.target instanceof Element && event.target.closest('input, textarea, select'))) event.preventDefault();
    });
    const root = createRoot(dom);
    roots.set(dom, root);
    this.draw(root, view, dom);
    return dom;
  }

  updateDOM(dom: HTMLElement, view: EditorView): boolean {
    const root = roots.get(dom);
    if (!root) return false;
    this.draw(root, view, dom);
    return true;
  }

  draw(root: Root, view: EditorView, dom: HTMLElement): void {
    const options = this.options();
    const reading = readQuery(this.body);
    const result = reading.query && options ? runQuery(reading.query, libraryOf(withOpen(options.notes(), options.noteId, view.state.doc.toString()), cacheOf(view)), this.today) : null;
    root.render(
      createElement(QueryView, {
        lines: this.body,
        problem: reading.problem,
        result,
        editable: this.editable,
        height: this.height,
        onHeight: (height: number | null) => {
          // Written into the opening fence, as a board's is (editor/boards/divider.ts): one change, one undo.
          const open = view.state.doc.lineAt(view.posAtDOM(dom));
          const next = withQueryHeight(open.text, height);
          if (next !== open.text) view.dispatch({ changes: { from: open.from, to: open.to, insert: next }, userEvent: 'input.query' });
        },
        thisNote: options?.noteId ?? null,
        onEdit: () => {
          // Focused first, so the caret lands in a view that has the focus and the drawing steps aside at once.
          view.focus();
          view.dispatch({ selection: { anchor: this.at }, scrollIntoView: true });
        },
        onOpen: (row: Row) => {
          if (row.noteId === options?.noteId) {
            const line = row.kind === 'task' ? lineOf(view.state, row) : 1;
            if (line === null) return;
            view.dispatch({ selection: { anchor: view.state.doc.line(line).to }, scrollIntoView: true });
            if (this.editable) view.focus();
            return;
          }
          options?.open(row.noteId, row.kind === 'task' ? row.line : null);
        },
        onTick: (row: Row) => {
          if (row.kind !== 'task' || row.done === null || !this.editable) return;
          fireNativeHaptic('selection');
          if (row.noteId !== options?.noteId) {
            options?.tick(row.noteId, row.line, row.source, !row.done);
            return;
          }
          const line = lineOf(view.state, row);
          if (line === null) return;
          const text = view.state.doc.line(line);
          const box = taskBox(text.text);
          if (box) view.dispatch(toggleBox(view.state, { from: text.from + box.at, done: box.done }));
        },
      }),
    );
  }

  destroy(dom: HTMLElement): void {
    const root = roots.get(dom);
    roots.delete(dom);
    // Never in the middle of CodeMirror's update, which may be inside a React render (editor/reactMount.ts).
    if (root) queueMicrotask(() => root.unmount());
  }

  ignoreEvent(): boolean {
    // Every press in a drawn query is its own: a row opened, a box ticked, a month turned. None of it moves the caret.
    return true;
  }
}

interface Drawn {
  stamp: number;
  today: string;
  decorations: DecorationSet;
}

function decorate(state: EditorState, stamp: number, today: string, options: () => QueryOptions | null): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const editable = state.facet(EditorView.editable) && !state.readOnly;
  for (const fence of queryFencesIn(state.doc.toString())) {
    const from = state.doc.line(fence.from).from;
    const to = state.doc.line(fence.to).to;
    // The caret in the fence: the lines themselves, to edit. Elsewhere, and in a view with no caret, the answer.
    if (editable && caretIn(state, from, to)) continue;
    const at = state.doc.line(Math.min(fence.from + 1, fence.to)).from;
    builder.add(from, to, Decoration.replace({ widget: new QueryWidget(fence.body, at, stamp, today, editable, fence.height, options), block: true }));
  }
  return builder.finish();
}

/** Ms to the next midnight on the device's clock, when `today` moves on. */
function untilMidnight(): number {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime() - now.getTime() + 500;
}

const theme = EditorView.baseTheme({
  '.cm-query': {
    display: 'block',
    boxSizing: 'border-box',
    // As wide as the note is, never as wide as a table's columns or a board's lanes, which scroll inside it: a block
    // widget's width decides the editor's, and a wide one ran every line of the note off the screen (the room is the
    // board's measure, editor/boards.ts `boardRoom`, which every editor that draws queries has).
    inlineSize: 'var(--cm-board-room, 100%)',
    margin: '0',
    // A block widget is not a line, so it has no line's indent: the note's own, given back, so the card lines up with
    // the words.
    paddingBlock: '0.4em',
    paddingInline: 'var(--cm-board-bleed, var(--app-gutter, 1rem))',
    textIndent: '0',
    cursor: 'default',
  },
});

/**
 * Every ```query fence in the note drawn as its answer, over the library `options` hands it; the lines as they are
 * where it answers null (a card's small note, a shared page), which is what any other app shows.
 */
export function queries(options: () => QueryOptions | null): Extension {
  const field = StateField.define<Drawn>({
    create: (state) => {
      const today = isoDay(new Date());
      return { stamp: 0, today, decorations: options() ? decorate(state, 0, today, options) : Decoration.none };
    },
    update(value, tr) {
      const refreshed = tr.effects.some((effect) => effect.is(refreshQueries));
      if (!refreshed && !tr.docChanged && !tr.selection && !tr.reconfigured && !focusMoved(tr)) return value;
      const stamp = value.stamp + (refreshed || tr.docChanged ? 1 : 0);
      const today = isoDay(new Date());
      return { stamp, today, decorations: options() ? decorate(tr.state, stamp, today, options) : Decoration.none };
    },
    provide: (state) => EditorView.decorations.from(state, (value) => value.decorations),
  });
  return [
    trackFocus,
    field,
    // At midnight every query is run again: `today`, and every overdue and due-today with it, has moved.
    ViewPlugin.fromClass(
      class {
        timer = 0;
        constructor(readonly view: EditorView) {
          this.arm();
        }
        arm(): void {
          this.timer = window.setTimeout(() => {
            this.view.dispatch({ effects: refreshQueries.of(null) });
            this.arm();
          }, untilMidnight());
        }
        destroy(): void {
          window.clearTimeout(this.timer);
        }
      },
    ),
    fieldChipTheme,
    theme,
  ];
}

import { RangeSetBuilder, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import type { TicketChoice } from '../book/tickets.ts';
import { issueKeyOf, isTicket, propertiesOf, withProperty, type StatusCategory } from '../core/properties.ts';
import { caretIn, focusMoved, trackFocus } from './drawnBlock.ts';
import { frontMatter, frontMatterDrawn } from './extended.ts';
import { forEachVisibleLine } from './lines.ts';
import { TicketPanel } from './TicketPanel.tsx';
import { wikiLinksIn } from './wikiLinks.ts';

/**
 * A ticket drawn in its note (Matt asked what Notion- and Jira-like features custom Markdown could give the app, "like
 * tickets and such", and picked tickets as notes; docs/DESIGN.md §157, docs/TICKETS.md). Two things, both drawn from
 * the Markdown and writing nothing but it:
 *
 * **The properties panel.** A note whose front matter says `type: ticket` is drawn with that front matter as a panel,
 * as Notion draws a page's properties over its words: the ticket's key, then Status, Assignee, Priority and Due, and
 * any of Start, Estimate, Blocked by, Parent and Labels it has (editor/TicketPanel.tsx). A tap on a value picks it - a
 * status from the notebook's workflow in its category's colour, a person the library already names or one typed, one
 * of the five priorities (core/taskFields.ts), a day, a number, other tickets by key or title - and the pick is
 * written into the front matter through core/properties.ts `withProperty`, one change, so one Undo takes it back.
 * Keys a ticket does not have are a quiet line under the panel, as the folded front matter names them
 * (editor/extended.ts), and that line, or the panel's own button, puts the caret in the front matter, where the panel
 * steps aside for the lines as they are written, as every drawn block does (editor/drawnBlock.ts). A ticket waiting
 * on another that is not done says so first, with a lock and the ticket it waits on.
 *
 * It replaces the folded front matter for a ticket (`frontMatterDrawn`), and only where the screen gave the library's
 * tickets to draw it with: a card's small note and a shared page draw the front matter as before. In a view that
 * cannot be edited the panel is read, with nothing to pick.
 *
 * **A key as a link.** `[[GHO-12]]` opens the ticket whose id is GHO-12 (App.tsx finds it by its key as well as by a
 * title), and is drawn with the ticket's title after it, its status's colour on a dot, struck through once it is done:
 * the key alone says nothing to a reader of the note. A key no ticket has is a link to a note not written yet, drawn as
 * every such link is (editor/wikiLinks.ts).
 *
 * The library changes under both (another ticket is closed, a person is named), so a new set of tickets is told to the
 * view (`refreshTickets`) and the panel and the titles are drawn again. A state field for the panel, as every block
 * widget is; a view plugin for the titles, which are inline.
 */

/** What the screen hands the editor for a ticket's panel and its keys: the library's tickets, read when they are drawn. */
export interface TicketOptions {
  /** The workflow this note's status moves through: its notebook's (book/tickets.ts), or the default. */
  statuses: () => readonly string[];
  /** The people the library already names, the most named first (book/tickets.ts `peopleIn`). */
  people: () => readonly string[];
  /** Every other ticket, for Blocked by and Parent. */
  choices: () => readonly TicketChoice[];
  /** The ticket a key or a title names, or null. */
  find: (target: string) => TicketChoice | null;
  /** Opens the ticket a key or a title names. */
  open: (target: string) => void;
  /** The key this note would get from its notebook, for a ticket that has none yet (book/tickets.ts `nextTicketId`). */
  nextId?: () => string | null;
}

/** The library's tickets changed: every panel and key title is drawn again. */
export const refreshTickets = StateEffect.define<null>();

// ---- writing --------------------------------------------------------------------------------------

/**
 * One property written into the note: `withProperty` over the whole body, dispatched as the smallest change that
 * makes it, so the caret and anything typed elsewhere stay put. The key keeps the case the note wrote it in.
 */
export function writeProperty(view: EditorView, key: string, value: string | readonly string[] | null): void {
  const doc = view.state.doc.toString();
  const written = propertiesOf(doc).find((property) => property.key.toLowerCase() === key)?.key ?? key;
  const next = withProperty(doc, written, value);
  if (next === doc) return;
  let start = 0;
  while (start < doc.length && start < next.length && doc[start] === next[start]) start += 1;
  let end = doc.length;
  let nextEnd = next.length;
  while (end > start && nextEnd > start && doc[end - 1] === next[nextEnd - 1]) {
    end -= 1;
    nextEnd -= 1;
  }
  view.dispatch({ changes: { from: start, to: end, insert: next.slice(start, nextEnd) }, userEvent: 'input.property' });
}

// ---- the panel ----------------------------------------------------------------------------------

/** The front matter as text, where it is, and where the caret goes to show its lines; null where there is none. */
function frontOf(state: EditorState): { text: string; from: number; to: number; at: number } | null {
  const front = frontMatter(state.doc);
  if (!front) return null;
  const from = state.doc.line(front.from).from;
  const to = state.doc.line(front.to).to;
  return { text: state.doc.sliceString(from, to), from, to, at: state.doc.line(Math.min(front.from + 1, front.to)).from };
}

/** Whether the note is a ticket by its front matter. */
function ticketNote(state: EditorState): boolean {
  const front = frontOf(state);
  return front !== null && isTicket(front.text);
}

/** The React roots the panels are drawn in, by their element, so a change redraws the same root. */
const roots = new WeakMap<HTMLElement, Root>();

class PanelWidget extends WidgetType {
  constructor(
    readonly text: string,
    readonly at: number,
    readonly version: number,
    readonly editable: boolean,
    readonly options: () => TicketOptions | null,
  ) {
    super();
  }

  eq(other: PanelWidget): boolean {
    return other.text === this.text && other.at === this.at && other.version === this.version && other.editable === this.editable;
  }

  get estimatedHeight(): number {
    return 240;
  }

  toDOM(view: EditorView): HTMLElement {
    const dom = document.createElement('div');
    dom.className = 'cm-ticketPanel';
    // A press on a value is the panel's, as a board's card's is (editor/boards/press.ts): its default taken, so the
    // browser puts no caret in the note under it and the panel does not step aside for the lines. A field keeps its
    // press, so it can take the focus and be typed in.
    dom.addEventListener('mousedown', (event) => {
      if (!(event.target instanceof Element && event.target.closest('input, textarea'))) event.preventDefault();
    });
    const root = createRoot(dom);
    roots.set(dom, root);
    this.draw(root, view);
    return dom;
  }

  updateDOM(dom: HTMLElement, view: EditorView): boolean {
    const root = roots.get(dom);
    if (!root) return false;
    this.draw(root, view);
    return true;
  }

  draw(root: Root, view: EditorView): void {
    root.render(
      createElement(TicketPanel, {
        front: this.text,
        options: this.options(),
        editable: this.editable,
        write: (key: string, value: string | readonly string[] | null) => writeProperty(view, key, value),
        // The caret on the first key: the panel steps aside, and the lines are there to type in.
        openLines: () => {
          view.dispatch({ selection: { anchor: this.at }, scrollIntoView: true });
          view.focus();
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
    // Every press in the panel is its own: a value picked, a field typed in. None of it moves the caret.
    return true;
  }
}

interface Panel {
  version: number;
  decorations: DecorationSet;
}

function panelOf(state: EditorState, version: number, options: () => TicketOptions | null): DecorationSet {
  const front = frontOf(state);
  if (!front || !isTicket(front.text) || caretIn(state, front.from, front.to)) return Decoration.none;
  const widget = new PanelWidget(front.text, front.at, version, state.facet(EditorView.editable) && !state.readOnly, options);
  return Decoration.set(Decoration.replace({ widget, block: true }).range(front.from, front.to));
}

// ---- a key's title --------------------------------------------------------------------------------

/** A ticket's title after its key's link, its status's colour on a dot before it. */
class KeyTitle extends WidgetType {
  constructor(
    readonly title: string,
    readonly category: StatusCategory,
    readonly status: string,
  ) {
    super();
  }

  eq(other: KeyTitle): boolean {
    return other.title === this.title && other.category === this.category && other.status === this.status;
  }

  toDOM(): HTMLElement {
    const span = document.createElement('span');
    span.className = 'cm-ticketTitle';
    span.dataset.category = this.category;
    span.title = this.status ? `${this.title} · ${this.status}` : this.title;
    const dot = document.createElement('span');
    dot.className = 'cm-ticketDot';
    dot.setAttribute('aria-hidden', 'true');
    span.append(dot, this.title);
    return span;
  }

  ignoreEvent(): boolean {
    // A press on the title is a press on the link: editor/wikiLinks.ts opens the ticket.
    return false;
  }
}

function keyTitles(view: EditorView, options: () => TicketOptions | null): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const lookup = options();
  if (!lookup) return builder.finish();
  // Not in the front matter, whose `blocked-by: "[[GHO-9]]"` is a line of keys, drawn as the panel or typed as it is.
  const front = frontMatter(view.state.doc);
  const after = front ? view.state.doc.line(front.to).to : -1;
  forEachVisibleLine(view, (line) => {
    if (line.from <= after || !line.text.includes('[[')) return;
    for (const link of wikiLinksIn(line.text, line.from)) {
      if (link.anchor || !issueKeyOf(link.title)) continue;
      const found = lookup.find(link.title);
      if (!found?.title) continue;
      builder.add(link.to, link.to, Decoration.widget({ widget: new KeyTitle(found.title, found.category, found.status ?? ''), side: 1 }));
    }
  });
  return builder.finish();
}

const theme = EditorView.baseTheme({
  // A block widget is not a line, so it takes the lines' gutter itself (markdown.module.css), as the fold did.
  '.cm-ticketPanel': { paddingInline: 'var(--app-gutter, 0)', paddingBlock: '0.2em 0.6em' },
  '.cm-ticketTitle': {
    marginInlineStart: '0.35em',
    color: 'var(--app-ink-2, var(--glacier-text-muted))',
    cursor: 'pointer',
  },
  '.cm-ticketDot': {
    display: 'inline-block',
    inlineSize: '0.5em',
    blockSize: '0.5em',
    marginInlineEnd: '0.3em',
    borderRadius: '50%',
    verticalAlign: '0.08em',
    background: 'var(--app-ink-4, currentColor)',
  },
  '.cm-ticketTitle[data-category="doing"] .cm-ticketDot': { background: 'var(--glacier-blue-9)' },
  '.cm-ticketTitle[data-category="done"] .cm-ticketDot': { background: 'var(--glacier-green-9)' },
  '.cm-ticketTitle[data-category="done"]': { textDecoration: 'line-through', textDecorationColor: 'color-mix(in oklch, currentColor 45%, transparent)' },
});

/**
 * A ticket's panel over its words and its key's title after a `[[GHO-12]]`, read from the library through `options`
 * when they are drawn; nothing where it answers null.
 */
export function tickets(options: () => TicketOptions | null): Extension {
  const panel = StateField.define<Panel>({
    create: (state) => ({ version: 0, decorations: options() ? panelOf(state, 0, options) : Decoration.none }),
    update(value, tr) {
      const refreshed = tr.effects.some((effect) => effect.is(refreshTickets));
      if (!refreshed && !tr.docChanged && !tr.selection && !tr.reconfigured && !focusMoved(tr)) return value;
      const version = value.version + (refreshed ? 1 : 0);
      return { version, decorations: options() ? panelOf(tr.state, version, options) : Decoration.none };
    },
    provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
  });
  return [
    trackFocus,
    panel,
    // The folded front matter steps aside for a ticket's panel (editor/extended.ts).
    frontMatterDrawn.of((state) => options() !== null && ticketNote(state)),
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;
        constructor(view: EditorView) {
          this.decorations = keyTitles(view, options);
        }
        update(update: ViewUpdate) {
          const refreshed = update.transactions.some((tr) => tr.effects.some((effect) => effect.is(refreshTickets)));
          if (update.docChanged || update.viewportChanged || refreshed) this.decorations = keyTitles(update.view, options);
        }
      },
      { decorations: (plugin) => plugin.decorations },
    ),
    theme,
  ];
}

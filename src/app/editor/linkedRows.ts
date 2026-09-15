import { Facet, StateEffect, StateField, type EditorState, type Extension, type Range } from '@codemirror/state';
import { Decoration, EditorView, WidgetType, type DecorationSet } from '@codemirror/view';
import { itemWords, markOf } from '../core/itemLinks.ts';
import { hasMarkDetails, markNameFor, peekMarkDetails, type MarkEntry } from '../core/markDetails.ts';
import { detailsArrived } from './links.ts';
import { mountMarkMenu } from './markMenuMount.tsx';

/**
 * What a note's links are linked to, shown under them, and the menu that
 * splits the note open where they are.
 *
 * Matt, on the first version's single pill: "Not all notion links are being
 * auto formatted to have the full pill showing details, I also think the
 * notion integration might need multiple pills to represent data so let's
 * think about reworking how we show the notion data in lists". And on tapping
 * it: "show a few options like opening the ticket in notion or un linking or
 * updating etc. Make these context menus split text in place … like it's
 * splitting the page right where it needs to go and make the options
 * typography and iconography heavy".
 *
 * - **Every linked line gets a row.** A list item ending in a mark
 *   (`[notion](…)`, core/itemLinks.ts), and any line with an ordinary link a
 *   plugin reads (the old `[Buy milk](https://www.notion.so/…)` items, a task
 *   pasted into a sentence), has a row of small pills under it, hung at the
 *   item's own indent: the service's name, solid; then the stage and status;
 *   then a pill for each fact (priority, due). The mark at the end of the
 *   line draws nothing while the row carries it (links.ts). A plugin that is
 *   off draws no row, and its mark is the old pill again.
 * - **A tap on the row splits the note open** under it: the lines below move
 *   down and the menu is in the gap, the width of the page, with its top and
 *   bottom edges shaded like a cut (editor/MarkMenu.tsx). Another tap on the
 *   row, a touch outside, or the back gesture closes it again.
 *
 * Block widgets can only come from state, so both are a StateField over the
 * whole document, recomputed when it changes, when details arrive (links.ts
 * dispatches `detailsArrived`), and when a menu opens or closes. Notes are
 * short; a line without `](` is skipped at once.
 */

export interface Linked {
  /** Where the line starts, when the row was drawn. */
  from: number;
  name: string;
  url: string;
  /** The line's words without the link's address: an item's words, or the link's own words in a sentence. */
  words: string;
  kind: 'mark' | 'link';
  item: boolean;
}

const LINK = /\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)/g;

/** The linked thing on a line, if there is one: an item's mark first, else the first link a plugin reads. */
export function linkedOn(text: string, from = 0): Linked | null {
  if (!text.includes('](')) return null;
  const words = itemWords(text);
  const mark = words !== null ? markOf(text) : null;
  if (mark && hasMarkDetails(mark.name)) return { from, name: mark.name, url: mark.url, words: words ?? '', kind: 'mark', item: true };
  for (const match of text.matchAll(LINK)) {
    const url = match[2] ?? '';
    const name = markNameFor(url);
    if (!name) continue;
    const said = words !== null ? words.replace(LINK, (_all, inner: string) => inner).trim() : (match[1] ?? '').trim();
    return { from, name, url, words: said, kind: 'link', item: words !== null };
  }
  return null;
}

/** The line with its link taken off and its words kept. */
export function unlinked(text: string, linked: Pick<Linked, 'kind' | 'url'>): string {
  if (linked.kind === 'mark') return text.replace(/\s*\[[a-z][a-z0-9-]*\]\((https?:\/\/[^\s)]+)\)\s*$/, '');
  const escaped = linked.url.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return text.replace(new RegExp(`\\[([^\\]]*)\\]\\(${escaped}\\)`), '$1');
}

export interface LinkMenus {
  /** A sentence on the note for a few seconds: what a menu action did, or why it couldn't. */
  say(message: string): void;
}

/** Whether rows open menus here, and what they say with. Absent (a read-only view): rows only. */
const menusFacet = Facet.define<LinkMenus | null, LinkMenus | null>({ combine: (values) => values.find(Boolean) ?? null });

/** Opens the menu under the line starting at `from`, or closes it with null. */
export const toggleMenu = StateEffect.define<number | null>();

const openMenu = StateField.define<number | null>({
  create: () => null,
  update(value, tr) {
    let next = value !== null && tr.docChanged ? tr.changes.mapPos(value, -1) : value;
    for (const effect of tr.effects) if (effect.is(toggleMenu)) next = effect.value;
    return next;
  },
});

const STAGE_WORDS = { todo: 'To do', doing: 'In progress', done: 'Done' } as const;

function faceOf(entry: MarkEntry | null): string {
  if (!entry) return '';
  if (entry.state !== 'ready') return entry.state;
  const { status, brief, gone } = entry.details;
  return [status?.stage, status?.label, brief.join('·'), gone ? 'gone' : ''].join('|');
}

class RowWidget extends WidgetType {
  readonly face: string;

  constructor(
    readonly linked: Linked,
    readonly entry: MarkEntry | null,
    readonly open: boolean,
    readonly menus: boolean,
  ) {
    super();
    this.face = faceOf(entry);
  }

  eq(other: RowWidget): boolean {
    return other.linked.url === this.linked.url && other.linked.item === this.linked.item && other.face === this.face && other.open === this.open && other.menus === this.menus;
  }

  get estimatedHeight(): number {
    return 24;
  }

  toDOM(view: EditorView): HTMLElement {
    const row = document.createElement('div');
    row.className = 'cm-linkRow';
    if (this.open) row.dataset.open = '';
    const pill = (className: string, text: string) => {
      const piece = document.createElement('span');
      piece.className = `cm-linkPill ${className}`;
      piece.textContent = text;
      row.append(piece);
      return piece;
    };
    const { name } = this.linked;
    pill('cm-linkPill-name', name.charAt(0).toUpperCase() + name.slice(1));
    const entry = this.entry;
    if (entry?.state === 'ready') {
      const { status, brief, gone, title } = entry.details;
      row.title = title;
      if (gone) pill('cm-linkPill-status', 'In trash').dataset.gone = '';
      else if (status) {
        const piece = pill('cm-linkPill-status', status.label || STAGE_WORDS[status.stage]);
        piece.dataset.stage = status.stage;
        const stage = document.createElement('span');
        stage.className = 'cm-linkStage';
        stage.setAttribute('aria-hidden', 'true');
        piece.prepend(stage);
      }
      if (!gone) {
        for (const fact of brief) {
          const piece = pill('cm-linkPill-fact', fact);
          if (fact.startsWith('Overdue')) piece.dataset.late = '';
        }
      }
    } else if (entry?.state === 'loading') {
      pill('cm-linkPill-quiet', 'Reading…');
    } else if (entry?.state === 'failed') {
      pill('cm-linkPill-quiet', 'Can’t read it').title = entry.message;
    }
    // Hung at the item's own indent: the line before carries it (glyphLines.ts `--hang`).
    requestAnimationFrame(() => {
      const line = row.previousElementSibling;
      if (line instanceof HTMLElement && line.classList.contains('cm-line')) {
        row.style.setProperty('--row-hang', getComputedStyle(line).getPropertyValue('--hang') || '0px');
      }
    });
    if (this.menus) {
      row.setAttribute('role', 'button');
      row.tabIndex = 0;
      row.setAttribute('aria-expanded', String(this.open));
      row.setAttribute('aria-label', `${name}: ${row.title || 'linked'}. ${this.open ? 'Close' : 'Open'} its menu.`);
      // A tap on the row is the row's: the editor must not move the caret or raise the keyboard.
      row.addEventListener('pointerdown', (event) => {
        event.preventDefault();
        event.stopPropagation();
      });
      row.addEventListener('mousedown', (event) => event.preventDefault());
      row.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        // The row sits after its line; whichever side of the line break CodeMirror counts it on, find the linked line.
        let line = view.state.doc.lineAt(view.posAtDOM(row));
        if (!linkedOn(line.text) && line.number > 1) line = view.state.doc.line(line.number - 1);
        const opened = view.state.field(openMenu, false);
        const isOpen = opened !== null && opened !== undefined && opened >= line.from && opened <= line.to;
        view.dispatch({ effects: toggleMenu.of(isOpen ? null : line.from) });
      });
    }
    return row;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

class MenuWidget extends WidgetType {
  constructor(
    readonly linked: Linked,
    readonly menus: LinkMenus,
  ) {
    super();
  }

  eq(other: MenuWidget): boolean {
    return other.linked.url === this.linked.url && other.linked.words === this.linked.words && other.linked.kind === this.linked.kind;
  }

  get estimatedHeight(): number {
    return 260;
  }

  toDOM(view: EditorView): HTMLElement {
    const host = document.createElement('div');
    host.className = 'cm-linkMenu';
    const linked = this.linked;
    const lineNow = () => {
      const from = view.state.field(openMenu, false);
      return from === null || from === undefined ? null : view.state.doc.lineAt(from);
    };
    const unmount = mountMarkMenu(host, {
      name: linked.name,
      url: linked.url,
      words: linked.words,
      say: this.menus.say,
      close: () => view.dispatch({ effects: toggleMenu.of(null) }),
      unlink: () => {
        const line = lineNow();
        if (!line) return;
        const next = unlinked(line.text, linked);
        view.dispatch({ changes: { from: line.from, to: line.to, insert: next }, effects: toggleMenu.of(null) });
      },
    });
    (host as HTMLElement & { unmountMenu?: () => void }).unmountMenu = unmount;
    return host;
  }

  destroy(dom: HTMLElement): void {
    (dom as HTMLElement & { unmountMenu?: () => void }).unmountMenu?.();
  }

  ignoreEvent(): boolean {
    return true;
  }
}

function build(state: EditorState): DecorationSet {
  const menus = state.facet(menusFacet);
  const open = state.field(openMenu, false) ?? null;
  const ranges: Range<Decoration>[] = [];
  const { doc } = state;
  for (let number = 1; number <= doc.lines; number += 1) {
    const line = doc.line(number);
    const linked = linkedOn(line.text, line.from);
    if (!linked) continue;
    const entry = peekMarkDetails(linked.name, linked.url);
    // An ordinary link that has never been read draws nothing extra; a mark always has its row.
    if (linked.kind === 'link' && !entry) continue;
    const isOpen = menus !== null && open !== null && open >= line.from && open <= line.to;
    ranges.push(Decoration.widget({ widget: new RowWidget(linked, entry, isOpen, menus !== null), block: true, side: 1 }).range(line.to));
    if (isOpen && menus) ranges.push(Decoration.widget({ widget: new MenuWidget(linked, menus), block: true, side: 2 }).range(line.to));
  }
  return Decoration.set(ranges, true);
}

const rows = StateField.define<DecorationSet>({
  create: build,
  update(value, tr) {
    const changed = tr.docChanged || tr.effects.some((effect) => effect.is(detailsArrived) || effect.is(toggleMenu)) || tr.startState.facet(menusFacet) !== tr.state.facet(menusFacet);
    return changed ? build(tr.state) : value;
  },
  provide: (field) => EditorView.decorations.from(field),
});

const rowsTheme = EditorView.baseTheme({
  '.cm-linkRow': {
    display: 'flex',
    flexWrap: 'wrap',
    alignItems: 'center',
    gap: '0.35em',
    paddingInline: 'calc(var(--app-gutter) + var(--row-hang, 0px)) var(--app-gutter)',
    paddingBlock: '0.1em 0.4em',
    fontSize: '0.7em',
    lineHeight: '1.6',
    userSelect: 'none',
    WebkitTapHighlightColor: 'transparent',
  },
  '.cm-linkRow[role="button"]': { cursor: 'pointer' },
  '.cm-linkPill': {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '0.4em',
    padding: '0 0.65em',
    borderRadius: '999px',
    border: '1px solid color-mix(in srgb, var(--app-ink, currentColor) 28%, transparent)',
    color: 'var(--app-ink-2, var(--glacier-text))',
    whiteSpace: 'nowrap',
  },
  '.cm-linkPill-name': {
    background: 'var(--app-ink, currentColor)',
    borderColor: 'var(--app-ink, currentColor)',
    color: 'var(--app-paper, #fff)',
    fontWeight: '600',
  },
  '.cm-linkPill-status': { color: 'var(--app-ink, var(--glacier-text))', fontWeight: '600' },
  '.cm-linkPill-fact[data-late]': { color: 'var(--app-ink, var(--glacier-text))', fontWeight: '700', borderColor: 'var(--app-ink, currentColor)' },
  '.cm-linkPill-quiet': { border: 'none', paddingInline: '0.2em', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  '.cm-linkPill-status[data-gone]': { textDecoration: 'line-through' },
  '.cm-linkStage': {
    boxSizing: 'border-box',
    width: '0.8em',
    height: '0.8em',
    borderRadius: '50%',
    border: '0.13em solid currentColor',
  },
  '.cm-linkPill-status[data-stage="doing"] .cm-linkStage': { background: 'linear-gradient(90deg, currentColor 50%, transparent 50%)' },
  '.cm-linkPill-status[data-stage="done"] .cm-linkStage': { background: 'currentColor' },
  '.cm-linkRow[data-open] .cm-linkPill-name': { boxShadow: '0 0 0 2px var(--app-paper, #fff), 0 0 0 3.5px var(--app-ink, currentColor)' },
  '.cm-itemMarkHidden': { display: 'none' },
});

/**
 * Rows of pills under linked lines, and, with `menus`, the menu a tap on a row
 * splits the note open for.
 */
export function linkedRows(menus: LinkMenus | null): Extension {
  return [menusFacet.of(menus), openMenu, rows, rowsTheme];
}

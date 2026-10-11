import { ensureSyntaxTree, syntaxTree } from '@codemirror/language';
import { type EditorState, type Extension, RangeSetBuilder, StateField } from '@codemirror/state';
import { Decoration, type DecorationSet, EditorView, WidgetType } from '@codemirror/view';
import { caretIn, focusMoved, openOnPress, trackFocus } from './drawnBlock.ts';
import { blankStamp, blanksRedraw, drawCell, tablePill } from './blanks.ts';

/**
 * Tables, shown as tables.
 *
 * A GFM table in a note is rows of pipes and dashes, which is how it is kept
 * and how it is edited, but not how anyone wants to read it on a phone. So a
 * table the caret is not in is drawn as a real table: header, rows, a
 * hairline grid, scrolling sideways inside itself when it is wider than the
 * screen. Tapping it puts the caret at its start, the drawn table steps aside,
 * and the pipes are there to edit; leaving it draws it again. In a view that
 * cannot be edited (the Formatted view) it simply stays drawn.
 *
 * Block decorations have to come from a state field, not a view plugin, and a
 * state field cannot ask the view whether it has focus, so focus is kept in a
 * field of its own, the one every drawn block shares (editor/drawnBlock.ts).
 */

interface Parsed {
  header: string[];
  align: Array<'left' | 'center' | 'right' | null>;
  rows: string[][];
}

/** The cells of one table line: split on unescaped pipes, the outer ones dropped. */
function cellsOfLine(line: string): string[] {
  const cells: string[] = [];
  let current = '';
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i]!;
    if (ch === '\\' && line[i + 1] === '|') {
      current += '|';
      i += 1;
    } else if (ch === '|') {
      cells.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  cells.push(current);
  const trimmed = line.trim();
  if (trimmed.startsWith('|')) cells.shift();
  if (trimmed.endsWith('|') && !trimmed.endsWith('\\|')) cells.pop();
  return cells.map((cell) => cell.trim());
}

export function parseTable(text: string): Parsed | null {
  const lines = text.split('\n').filter((line) => line.trim());
  if (lines.length < 2) return null;
  const header = cellsOfLine(lines[0]!);
  const divider = cellsOfLine(lines[1]!);
  if (!divider.every((cell) => /^:?-+:?$/.test(cell))) return null;
  const align = divider.map((cell) => (cell.startsWith(':') && cell.endsWith(':') ? 'center' : cell.endsWith(':') ? 'right' : cell.startsWith(':') ? 'left' : null));
  const rows = lines.slice(2).map((line) => {
    const cells = cellsOfLine(line);
    return header.map((_, i) => cells[i] ?? '');
  });
  return { header, align, rows };
}

/** A cell's words without the markup that would show as symbols: bold, italics, code ticks, link targets. */
function plainCell(text: string): string {
  return text
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/(\*\*|__)(.+?)\1/g, '$2')
    .replace(/(\*|_)(.+?)\1/g, '$2')
    .replace(/`([^`]+)`/g, '$1');
}

/** Where each cell of a table's text starts in it, by line and column: the raw words a blank or a fill is drawn from. */
function cellSpans(text: string): { raw: string; at: number }[][] {
  const out: { raw: string; at: number }[][] = [];
  let lineAt = 0;
  for (const line of text.split('\n')) {
    const row: { raw: string; at: number }[] = [];
    if (line.trim()) {
      const pipes = [...line.matchAll(/(?<!\\)\|/g)].map((m) => m.index);
      const edges = line.trim().startsWith('|') ? pipes : [-1, ...pipes];
      if (!line.trim().endsWith('|') || line.trim().endsWith('\\|')) edges.push(line.length);
      for (let i = 0; i + 1 < edges.length; i += 1) {
        const start = edges[i]! + 1;
        const cell = line.slice(start, edges[i + 1]);
        const lead = cell.length - cell.trimStart().length;
        row.push({ raw: cell.trim(), at: lineAt + start + lead });
      }
      out.push(row);
    }
    lineAt += line.length + 1;
  }
  return out;
}

/** A cell appended to a table line, before its trailing pipe where it has one, so `| a | b |` grows by one cell. */
function appendCell(line: string, cell: string): string {
  const end = line.trimEnd();
  return /(?<!\\)\|\s*$/.test(end) ? `${end} ${cell} |` : `${end} | ${cell}`;
}

/**
 * A table's source with one more column: a heading on the header row, dashes on the divider, and an empty cell on
 * every body row (editor/tables.ts, the + column button on a drawn table). Blank lines are left as they are.
 */
export function addTableColumn(text: string): string {
  let body = 0;
  return text
    .split('\n')
    .map((line) => {
      if (!line.trim()) return line;
      body += 1;
      return appendCell(line, body === 1 ? 'Column' : body === 2 ? '---' : '');
    })
    .join('\n');
}

/**
 * A table's source with one more row: an empty row, as wide as its header, after its last row (the + row button on a
 * drawn table). Its cells are left empty for the words to be typed in.
 */
export function addTableRow(text: string): string {
  const lines = text.split('\n');
  const columns = Math.max(1, cellsOfLine(lines[0] ?? '').length);
  const row = `| ${Array(columns).fill('').join(' | ')} |`;
  let last = lines.length - 1;
  while (last > 0 && !lines[last]!.trim()) last -= 1;
  lines.splice(last + 1, 0, row);
  return lines.join('\n');
}

class TableWidget extends WidgetType {
  constructor(
    readonly text: string,
    readonly from: number,
    /** Bumped as blanks change under the table (editor/blanks.ts), so its cells are drawn again. */
    readonly stamp: number,
    /** Whether the + row and + column buttons are drawn: only where the note can be changed. */
    readonly editable: boolean,
  ) {
    super();
  }

  eq(other: TableWidget): boolean {
    return other.text === this.text && other.from === this.from && other.stamp === this.stamp && other.editable === this.editable;
  }

  toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement('div');
    wrap.className = 'cm-glyphTableWrap';
    const parsed = parseTable(this.text);
    if (!parsed) {
      wrap.textContent = this.text;
      return wrap;
    }
    const table = document.createElement('table');
    table.className = 'cm-glyphTable';
    // Each cell's raw words and where they start, for a blank or a filled answer drawn in it (docs/DESIGN.md §145).
    const spans = cellSpans(this.text);
    const draw = (el: HTMLElement, value: string, line: number, column: number) => {
      const span = spans[line]?.[column];
      if (!span || !drawCell(view, el, span.raw, this.from + span.at, plainCell)) el.textContent = plainCell(value);
    };
    const head = table.createTHead().insertRow();
    parsed.header.forEach((label, i) => {
      const th = document.createElement('th');
      draw(th, label, 0, i);
      if (parsed.align[i]) th.style.textAlign = parsed.align[i]!;
      head.appendChild(th);
    });
    const body = table.createTBody();
    parsed.rows.forEach((row, r) => {
      const tr = body.insertRow();
      row.forEach((value, i) => {
        const td = tr.insertCell();
        draw(td, value, r + 2, i);
        if (parsed.align[i]) td.style.textAlign = parsed.align[i]!;
      });
    });
    wrap.appendChild(table);
    // Its blanks' Fill pill, after its last row.
    const pill = tablePill(view, this.from, this.from + this.text.length);
    if (pill) {
      const foot = document.createElement('div');
      foot.appendChild(pill);
      wrap.appendChild(foot);
    }
    // Grow the table without dropping into its pipes: a column on the right, a row below (Matt: make tables "easier
    // to create"). Each rewrites the table's source as one undo; the caret stays out, so the table is redrawn with
    // its new empty cells to tap and fill. The buttons keep their press from the wrap, or it would open the pipes.
    if (this.editable) {
      const tools = document.createElement('div');
      tools.className = 'cm-tableTools';
      const grow = (label: string, change: (text: string) => string) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'cm-tableGrow';
        button.textContent = label;
        button.addEventListener('mousedown', (event) => {
          event.preventDefault();
          event.stopPropagation();
        });
        button.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          const to = this.from + this.text.length;
          view.dispatch({ changes: { from: this.from, to, insert: change(this.text) }, userEvent: 'input.table' });
        });
        return button;
      };
      tools.append(grow('+ Column', addTableColumn), grow('+ Row', addTableRow));
      wrap.appendChild(tools);
    }
    openOnPress(view, wrap, this.from);
    return wrap;
  }

  ignoreEvent(event: Event): boolean {
    // Scrolling a wide table sideways is the table's; a tap is ours, to open it for editing.
    return event.type !== 'mousedown';
  }
}

function build(state: EditorState): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const tree = ensureSyntaxTree(state, state.doc.length, 40) ?? syntaxTree(state);
  const editable = state.facet(EditorView.editable);
  tree.iterate({
    enter(node) {
      if (node.name !== 'Table') return undefined;
      const from = state.doc.lineAt(node.from).from;
      const to = state.doc.lineAt(node.to).to;
      const inside = editable && caretIn(state, from, to);
      if (!inside) {
        builder.add(from, to, Decoration.replace({ widget: new TableWidget(state.doc.sliceString(from, to), from, state.field(blankStamp, false) ?? 0, editable), block: true }));
      }
      return false;
    },
  });
  return builder.finish();
}

const tableField = StateField.define<DecorationSet>({
  create: build,
  update(decorations, tr) {
    const treeMoved = syntaxTree(tr.state) !== syntaxTree(tr.startState);
    const blanksMoved = tr.effects.some((effect) => effect.is(blanksRedraw));
    if (tr.docChanged || tr.selection || treeMoved || focusMoved(tr) || tr.reconfigured || blanksMoved) return build(tr.state);
    return decorations;
  },
  provide: (field) => EditorView.decorations.from(field),
});

const tableTheme = EditorView.baseTheme({
  '.cm-glyphTableWrap': {
    overflowX: 'auto',
    margin: '0.35em 0',
    // A block widget is not a line, so it has no line's gutter: the same one, by hand.
    paddingInline: 'var(--app-gutter, 1rem)',
    cursor: 'text',
    WebkitOverflowScrolling: 'touch',
  },
  '.cm-glyphTable': {
    borderCollapse: 'collapse',
    fontSize: '0.92em',
    lineHeight: '1.35',
    minInlineSize: '60%',
  },
  // Words break between words, never inside one: a column is as wide as its
  // longest word, a long cell wraps at a comfortable measure, and a table
  // wider than the screen scrolls sideways in its wrap.
  '.cm-glyphTable th, .cm-glyphTable td': {
    padding: '0.35em 0.7em',
    border: '1px solid var(--glacier-border-subtle, rgba(127,127,127,0.3))',
    textAlign: 'start',
    verticalAlign: 'top',
    whiteSpace: 'pre-wrap',
    overflowWrap: 'normal',
    wordBreak: 'normal',
    maxInlineSize: '18em',
  },
  '.cm-glyphTable th': {
    whiteSpace: 'nowrap',
    fontWeight: '700',
    background: 'var(--app-paper-2, var(--glacier-surface-sunken, transparent))',
  },
  // The grow toolbar under a drawn table: two quiet buttons, a step quieter than the words.
  '.cm-tableTools': {
    display: 'flex',
    gap: '0.4em',
    margin: '0.35em 0 0',
  },
  '.cm-tableGrow': {
    appearance: 'none',
    display: 'inline-flex',
    alignItems: 'center',
    gap: '0.25em',
    padding: '0.2em 0.6em',
    border: '1px solid var(--glacier-border-subtle, rgba(127,127,127,0.3))',
    borderRadius: 'var(--glacier-radius-full, 999px)',
    background: 'transparent',
    color: 'var(--app-ink-3, currentColor)',
    font: 'inherit',
    fontSize: '0.8em',
    cursor: 'pointer',
    whiteSpace: 'nowrap',
  },
  '.cm-tableGrow:hover': {
    color: 'var(--app-ink, currentColor)',
    background: 'color-mix(in oklch, currentColor 8%, transparent)',
  },
  '.cm-tableGrow:focus-visible': {
    outline: '2px solid var(--glacier-focus-ring, var(--app-ink-2, currentColor))',
    outlineOffset: '1px',
  },
});

export function drawnTables(): Extension {
  return [trackFocus, tableField, tableTheme];
}

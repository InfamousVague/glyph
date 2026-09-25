import { ensureSyntaxTree, syntaxTree } from '@codemirror/language';
import { type EditorState, type Extension, RangeSetBuilder, StateField } from '@codemirror/state';
import { Decoration, type DecorationSet, EditorView, WidgetType } from '@codemirror/view';
import { caretIn, focusMoved, openOnPress, trackFocus } from './drawnBlock.ts';

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

class TableWidget extends WidgetType {
  constructor(
    readonly text: string,
    readonly from: number,
  ) {
    super();
  }

  eq(other: TableWidget): boolean {
    return other.text === this.text && other.from === this.from;
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
    const head = table.createTHead().insertRow();
    parsed.header.forEach((label, i) => {
      const th = document.createElement('th');
      th.textContent = plainCell(label);
      if (parsed.align[i]) th.style.textAlign = parsed.align[i]!;
      head.appendChild(th);
    });
    const body = table.createTBody();
    for (const row of parsed.rows) {
      const tr = body.insertRow();
      row.forEach((value, i) => {
        const td = tr.insertCell();
        td.textContent = plainCell(value);
        if (parsed.align[i]) td.style.textAlign = parsed.align[i]!;
      });
    }
    wrap.appendChild(table);
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
        builder.add(from, to, Decoration.replace({ widget: new TableWidget(state.doc.sliceString(from, to), from), block: true }));
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
    if (tr.docChanged || tr.selection || treeMoved || focusMoved(tr) || tr.reconfigured) return build(tr.state);
    return decorations;
  },
  provide: (field) => EditorView.decorations.from(field),
});

export function drawnTables(): Extension {
  return [
    trackFocus,
    tableField,
    EditorView.baseTheme({
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
    }),
  ];
}

import { EditorSelection, RangeSetBuilder, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, WidgetType, type DecorationSet } from '@codemirror/view';
import { boardsIn, cardsOf, columnFor, moveCard, putCard, setTaskDone, tasksIn, writeBoard, type BoardColumn, type Card, type Task } from '../core/boards.ts';

/**
 * Boards, shown as boards (docs/BOARDS.md, core/boards.ts).
 *
 * A ```board fence is columns; the tasks it names are anywhere in the note, each with its anchor. The fence is drawn
 * as a board of cards, the way a table is drawn as a table (editor/tables.ts): the markdown is what is kept and what
 * is edited, and the caret in the fence steps the drawing aside so the lines can be typed.
 *
 * A card IS its task, which is what Matt asked for ("linking the tasks in the board to a task on the page"):
 *
 * - Its tick box is the task's box. Ticking it ticks the line in the note, and moves the card to Done when the board
 *   has such a column.
 * - Its words are the task's words. Tapping them puts the caret on that line, so the board is a way around the note.
 * - The chevrons move it a column along, which rewrites the fence.
 * - A card whose task is gone is drawn with its anchor and nothing else, so it can be seen and taken out.
 */

const setFocus = StateEffect.define<boolean>();

const focusField = StateField.define<boolean>({
  create: () => false,
  update(focused, tr) {
    for (const effect of tr.effects) if (effect.is(setFocus)) return effect.value;
    return focused;
  },
});

/** Where a board is in the document, and what it holds. */
interface Drawn {
  /** The whole fence, from the first backtick to the last. */
  from: number;
  to: number;
  columns: BoardColumn[];
  tasks: Task[];
  cards: Card[];
}

function boards(state: EditorState): Drawn[] {
  const doc = state.doc.toString();
  const tasks = tasksIn(doc);
  return boardsIn(doc)
    .filter((board) => board.to > board.from)
    .map((board) => {
      const columns = board.columns;
      // A ticked task sits in Done wherever the fence has it, so the board never disagrees with the note.
      const cards = cardsOf(columns, tasks).map((card) => (card.task ? { ...card, column: Math.max(0, columnFor(columns, card.task)) } : card));
      return { from: state.doc.line(board.from).from, to: state.doc.line(board.to).to, columns, tasks, cards };
    });
}

class BoardWidget extends WidgetType {
  constructor(
    readonly board: Drawn,
    readonly face: string,
  ) {
    super();
  }

  eq(other: BoardWidget): boolean {
    return other.face === this.face;
  }

  toDOM(view: EditorView): HTMLElement {
    const board = document.createElement('div');
    board.className = 'cm-board';
    board.setAttribute('role', 'group');
    board.setAttribute('aria-label', 'Board');
    for (const [index, column] of this.board.columns.entries()) {
      const held = this.board.cards.filter((card) => card.column === index);
      const pane = document.createElement('section');
      pane.className = 'cm-boardColumn';
      const head = document.createElement('p');
      head.className = 'cm-boardName';
      head.textContent = column.name;
      const count = document.createElement('span');
      count.className = 'cm-boardCount';
      count.textContent = String(held.length);
      head.append(count);
      pane.append(head);
      for (const card of held) pane.append(this.drawCard(view, card, index));
      board.append(pane);
    }
    return board;
  }

  private drawCard(view: EditorView, card: Card, column: number): HTMLElement {
    const box = document.createElement('div');
    box.className = 'cm-boardCard';
    if (!card.task) box.dataset.gone = '';
    else if (card.task.done) box.dataset.done = '';

    const tick = document.createElement('button');
    tick.type = 'button';
    tick.className = 'cm-boardTick';
    tick.setAttribute('aria-label', card.task?.done ? `Untick ${card.task.text}` : `Tick ${card.task?.text ?? card.id}`);
    tick.disabled = !card.task;
    press(tick, () => this.tick(view, card));

    const words = document.createElement('button');
    words.type = 'button';
    words.className = 'cm-boardWords';
    words.textContent = card.task ? card.task.text : `^${card.id}`;
    words.setAttribute('aria-label', card.task ? `Go to ${card.task.text} in the note` : `${card.id}: this task is not in the note`);
    press(words, () => this.goTo(view, card));

    const moves = document.createElement('span');
    moves.className = 'cm-boardMoves';
    for (const [by, label, glyph] of [
      [-1, 'Move left', '‹'],
      [1, 'Move right', '›'],
    ] as const) {
      const move = document.createElement('button');
      move.type = 'button';
      move.className = 'cm-boardMove';
      move.textContent = glyph;
      move.setAttribute('aria-label', `${label}: ${card.task?.text ?? card.id}`);
      move.disabled = (by < 0 && column === 0) || (by > 0 && column === this.board.columns.length - 1);
      press(move, () => this.move(view, card, by));
      moves.append(move);
    }

    box.append(tick, words, moves);
    return box;
  }

  /** The card's tick box is the task's: the line is ticked, and a Done column takes the card. */
  private tick(view: EditorView, card: Card): void {
    const task = card.task;
    if (!task) return;
    const line = view.state.doc.line(task.line);
    const done = !task.done;
    const changes = [{ from: line.from, to: line.to, insert: setTaskDone(line.text, done) }];
    const put = done ? this.board.columns.findIndex((column) => /^done\b|\bdone$/i.test(column.name.trim())) : 0;
    const columns = put >= 0 ? putCard(this.board.columns, card.id, put) : null;
    view.dispatch({ changes: columns ? [...changes, this.fence(view, columns)] : changes, userEvent: 'input.board' });
  }

  private move(view: EditorView, card: Card, by: number): void {
    view.dispatch({ changes: this.fence(view, moveCard(this.board.columns, card.id, by)), userEvent: 'input.board' });
  }

  /** The fence rewritten: the columns as a person would have typed them, between the two ``` lines. */
  private fence(view: EditorView, columns: readonly BoardColumn[]) {
    const open = view.state.doc.lineAt(this.board.from);
    const close = view.state.doc.lineAt(this.board.to);
    return { from: open.to + 1, to: close.from - 1, insert: writeBoard(columns) };
  }

  /** The words are a way into the note: the caret lands on the task, and the note scrolls to it. */
  private goTo(view: EditorView, card: Card): void {
    if (!card.task) return;
    const line = view.state.doc.line(card.task.line);
    view.dispatch({ selection: EditorSelection.cursor(line.to), effects: EditorView.scrollIntoView(line.from, { y: 'center' }), scrollIntoView: true });
    view.focus();
  }

  ignoreEvent(): boolean {
    return false;
  }
}

/** A button that answers a tap without the editor taking the press as a caret move. */
function press(button: HTMLElement, run: () => void): void {
  button.addEventListener('mousedown', (event) => event.preventDefault());
  button.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopPropagation();
    run();
  });
}

/** What a board looks like now, so the widget is rebuilt only when something on it changed. */
function faceOf(board: Drawn): string {
  return [
    board.columns.map((column) => `${column.name}:${column.cards.join(',')}`).join('|'),
    board.cards.map((card) => `${card.id}@${card.column}:${card.task ? `${card.task.done ? 'x' : ' '}${card.task.text}` : 'gone'}`).join('|'),
  ].join('||');
}

function decorate(state: EditorState, focused: boolean): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const board of boards(state)) {
    // The caret in the fence: the lines themselves, to edit. Elsewhere, and in a view with no caret, the board.
    const inside = focused && state.selection.ranges.some((range) => range.from <= board.to && range.to >= board.from);
    if (inside) continue;
    builder.add(board.from, board.to, Decoration.replace({ widget: new BoardWidget(board, faceOf(board)), block: true }));
  }
  return builder.finish();
}

const boardField = StateField.define<DecorationSet>({
  create: (state) => decorate(state, false),
  update(value, tr) {
    const focused = tr.state.field(focusField);
    return tr.docChanged || tr.selection || tr.startState.field(focusField) !== focused ? decorate(tr.state, focused) : value;
  },
  provide: (field) => EditorView.decorations.from(field),
});

const boardTheme = EditorView.baseTheme({
  '.cm-board': {
    display: 'flex',
    gap: '0.6em',
    overflowX: 'auto',
    margin: '0.4em 0 0.8em',
    padding: '0.1em 0.1em 0.4em',
    scrollbarWidth: 'none',
    fontSize: '0.86em',
    textIndent: '0',
  },
  '.cm-boardColumn': {
    flex: '0 0 auto',
    inlineSize: 'min(72vw, 15rem)',
    display: 'flex',
    flexDirection: 'column',
    gap: '0.4em',
  },
  '.cm-boardName': {
    display: 'flex',
    alignItems: 'center',
    gap: '0.5em',
    margin: '0',
    fontSize: '0.8em',
    fontWeight: '700',
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
  },
  '.cm-boardCount': {
    minInlineSize: '1.5em',
    padding: '0 0.4em',
    borderRadius: '999px',
    border: '1px solid var(--app-rule, currentColor)',
    textAlign: 'center',
    letterSpacing: '0',
  },
  '.cm-boardCard': {
    display: 'flex',
    alignItems: 'flex-start',
    gap: '0.5em',
    padding: '0.55em 0.6em',
    borderRadius: 'var(--glacier-radius-lg, 0.75rem)',
    background: 'var(--app-paper-2, var(--glacier-surface))',
    border: '1px solid var(--app-rule, var(--glacier-border-subtle))',
  },
  '.cm-boardCard[data-done] .cm-boardWords': { textDecoration: 'line-through', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  '.cm-boardCard[data-gone] .cm-boardWords': { fontStyle: 'italic', color: 'var(--app-ink-3, var(--glacier-text-muted))' },
  '.cm-boardTick': {
    flex: 'none',
    inlineSize: '1.15em',
    blockSize: '1.15em',
    marginBlockStart: '0.1em',
    padding: '0',
    borderRadius: '0.3em',
    border: '1.5px solid var(--app-ink, currentColor)',
    background: 'none',
    cursor: 'pointer',
  },
  '.cm-boardCard[data-done] .cm-boardTick': {
    background: 'var(--app-ink, currentColor)',
    // The tick itself, drawn rather than set, so it is the same on every phone.
    clipPath: 'polygon(14% 52%, 38% 76%, 86% 22%, 96% 34%, 40% 94%, 6% 62%)',
  },
  '.cm-boardTick:disabled': { opacity: '0.4', cursor: 'default' },
  '.cm-boardWords': {
    flex: '1 1 auto',
    padding: '0',
    border: 'none',
    background: 'none',
    font: 'inherit',
    textAlign: 'start',
    color: 'inherit',
    cursor: 'pointer',
  },
  '.cm-boardMoves': { display: 'flex', flex: 'none', gap: '0.15em' },
  '.cm-boardMove': {
    inlineSize: '1.4em',
    blockSize: '1.4em',
    padding: '0',
    border: 'none',
    borderRadius: '0.35em',
    background: 'none',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    font: 'inherit',
    lineHeight: '1',
    cursor: 'pointer',
  },
  '.cm-boardMove:disabled': { opacity: '0.25', cursor: 'default' },
});

/** Boards drawn in a note, the fence still there to edit. */
export function drawnBoards(): Extension {
  return [focusField, boardField, boardTheme, EditorView.focusChangeEffect.of((_state, focusing) => setFocus.of(focusing))];
}

import { Annotation, StateEffect, StateField, type ChangeDesc, type ChangeSpec, type EditorState, type Extension, type Range, type Text } from '@codemirror/state';
import { Decoration, EditorView, WidgetType, type DecorationSet } from '@codemirror/view';

/**
 * The AI's changes, tracked in the note: what it added, tinted; what it took
 * away, struck through where it was; and, on each run of changes, Keep and
 * Revert.
 *
 * Matt chose auto-apply with marks over a preview: the model's lines go into
 * the note as they finish (ai/land.ts), and the note itself is always the
 * text as it now reads - which is what is saved, synced and shared. So the
 * marks are decorations over that text, never text in it: an added range is
 * a mark, the words that went are a widget drawn struck through where they
 * were (a block above the line for whole lines, inline for words within
 * one), and the pills are a widget at the end of a run of changes. The
 * records live in a state field, mapped through every edit, so a person can
 * type around them while the model is still writing.
 *
 * A change is kept - its marks go - when Keep is tapped, when Keep all is,
 * or when the person types on its line: the words are theirs then. Revert
 * puts the old words back and takes the new ones out. Both are one edit,
 * so one Undo takes either back.
 *
 * The landing state (`landingField`) is the lander's bookmark while it runs:
 * where the next line goes and where the old words end, mapped through the
 * person's typing, with the ranges they touched, which are theirs and are
 * never struck.
 */

export interface AiChange {
  id: string;
  runId: string;
  /** The added words, as a range in the note; empty (from === to) for a change that only took words away. */
  from: number;
  to: number;
  /** The words the change took away, drawn struck through where they were; empty for words only added. */
  removed: string;
  /** Whether the change is whole lines (drawn as a block, reverted with its newline) or words within a line. */
  block: boolean;
}

export interface Landing {
  /** Whose bookmark it is, so a run that ended after another took its place never puts the newer one away. */
  runId: string | null;
  /** Where the run's first line landed. */
  start: number;
  /** Where the next line goes. */
  cursor: number;
  /** Where the old words the run is replacing end. */
  oldEnd: number;
  /** What the person typed while the run was on: theirs, never struck. */
  touched: readonly { from: number; to: number }[];
}

/** On every transaction the AI makes: landing a line, reverting a change, undoing a run, signing the note. */
export const aiEdit = Annotation.define<'land' | 'revert' | 'undo' | 'sign'>();

function mapChange(change: AiChange, mapping: ChangeDesc): AiChange {
  return { ...change, from: mapping.mapPos(change.from, 1), to: mapping.mapPos(change.to, -1) };
}

export const addAiChanges = StateEffect.define<readonly AiChange[]>({ map: (changes, mapping) => changes.map((c) => mapChange(c, mapping)) });
export const keepAiChanges = StateEffect.define<readonly string[]>();
export const keepAllAiChanges = StateEffect.define<null>();
/** The marks a note was closed with, back on it (ai/marks.ts). */
export const restoreAiChanges = StateEffect.define<readonly AiChange[]>({ map: (changes, mapping) => changes.map((c) => mapChange(c, mapping)) });
export const setLanding = StateEffect.define<Pick<Landing, 'runId' | 'start' | 'cursor' | 'oldEnd'> | null>({
  map: (landing, mapping) => landing && { ...landing, start: mapping.mapPos(landing.start, -1), cursor: mapping.mapPos(landing.cursor, -1), oldEnd: mapping.mapPos(landing.oldEnd, -1) },
});

export const aiChangesField = StateField.define<readonly AiChange[]>({
  create: () => [],
  update(value, tr) {
    let next = value;
    if (tr.docChanged && next.length) {
      next = next.map((c) => mapChange(c, tr.changes)).filter((c) => c.to >= c.from && (c.to > c.from || c.removed));
      if (!tr.annotation(aiEdit)) {
        // The person wrote on a change's line: the words are theirs now, and the marks go.
        const lines = touchedLines(tr.newDoc, tr.changes);
        next = next.filter((c) => !onLines(tr.newDoc, c, lines));
      }
    }
    for (const effect of tr.effects) {
      if (effect.is(addAiChanges)) next = [...next, ...effect.value];
      else if (effect.is(keepAiChanges)) {
        const gone = new Set(effect.value);
        next = next.filter((c) => !gone.has(c.id));
      } else if (effect.is(keepAllAiChanges)) next = [];
      else if (effect.is(restoreAiChanges)) next = [...effect.value];
    }
    if (next !== value) next = [...next].sort((a, b) => a.from - b.from || a.to - b.to);
    return next;
  },
});

function touchedLines(doc: Text, changes: ChangeDesc): Set<number> {
  const lines = new Set<number>();
  changes.iterChangedRanges((_fromA, _toA, fromB, toB) => {
    const first = doc.lineAt(Math.min(fromB, doc.length)).number;
    const last = doc.lineAt(Math.min(toB, doc.length)).number;
    for (let n = first; n <= last; n += 1) lines.add(n);
  });
  return lines;
}

function onLines(doc: Text, change: AiChange, lines: Set<number>): boolean {
  const first = doc.lineAt(Math.min(change.from, doc.length)).number;
  const last = doc.lineAt(Math.min(change.to, doc.length)).number;
  for (let n = first; n <= last; n += 1) if (lines.has(n)) return true;
  return false;
}

export const landingField = StateField.define<Landing | null>({
  create: () => null,
  update(value, tr) {
    let next = value;
    if (next && tr.docChanged) {
      const touched = next.touched.map((r) => ({ from: tr.changes.mapPos(r.from, -1), to: tr.changes.mapPos(r.to, 1) }));
      if (!tr.annotation(aiEdit)) {
        tr.changes.iterChangedRanges((_fromA, _toA, fromB, toB) => touched.push({ from: fromB, to: toB }));
      }
      next = { runId: next.runId, start: tr.changes.mapPos(next.start, -1), cursor: tr.changes.mapPos(next.cursor, -1), oldEnd: tr.changes.mapPos(next.oldEnd, -1), touched };
    }
    for (const effect of tr.effects) {
      if (effect.is(setLanding)) next = effect.value ? { ...effect.value, touched: next?.touched ?? [] } : null;
    }
    return next;
  },
});

/** Whether a stretch of the note is one the person wrote in while the run was on. */
export function touchedIn(landing: Landing, from: number, to: number): boolean {
  return landing.touched.some((r) => r.from < Math.max(to, from + 1) && r.to > from);
}

// ---- drawing ----------------------------------------------------------------------------------

/** The words that went, struck through: a block above the line for whole lines, or inline before the words that came. */
class GoneWidget extends WidgetType {
  constructor(
    readonly text: string,
    readonly block: boolean,
  ) {
    super();
  }

  eq(other: GoneWidget): boolean {
    return other.text === this.text && other.block === this.block;
  }

  toDOM(): HTMLElement {
    if (this.block) {
      const box = document.createElement('div');
      box.className = 'cm-aiGoneBlock';
      box.setAttribute('aria-label', 'Words the AI took out');
      for (const line of this.text.split('\n')) {
        const row = document.createElement('div');
        row.className = 'cm-aiGoneLine';
        row.textContent = line || ' ';
        box.appendChild(row);
      }
      return box;
    }
    const span = document.createElement('span');
    span.className = 'cm-aiGone';
    span.setAttribute('aria-label', 'Words the AI took out');
    span.textContent = this.text.replace(/^\s+/, '');
    return span;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

/** Keep and Revert, at the end of a run of changes. */
class PillsWidget extends WidgetType {
  constructor(readonly ids: readonly string[]) {
    super();
  }

  eq(other: PillsWidget): boolean {
    return other.ids.join() === this.ids.join();
  }

  toDOM(view: EditorView): HTMLElement {
    const box = document.createElement('span');
    box.className = 'cm-aiPills';
    box.setAttribute('aria-label', 'This change from the AI');
    for (const [word, act] of [
      ['Keep', () => keepChanges(view, this.ids)],
      ['Revert', () => revertChanges(view, this.ids)],
    ] as const) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'cm-aiPill';
      button.dataset.act = word.toLowerCase();
      button.textContent = word;
      // A press on a pill is a press on the pill, not a caret move (editor/suggestions.ts has the reasoning: a touch's
      // default must stay, or it never becomes a click on a phone).
      for (const kind of ['pointerdown', 'mousedown'] as const) {
        button.addEventListener(kind, (event) => {
          event.preventDefault();
          event.stopPropagation();
        });
      }
      button.addEventListener('touchstart', (event) => event.stopPropagation());
      button.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        act();
      });
      box.appendChild(button);
    }
    return box;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

/** Changes that touch or sit on neighbouring lines, from one run, share one pair of pills. */
export function groupChanges(doc: Text, changes: readonly AiChange[]): { ids: string[]; to: number }[] {
  const groups: { ids: string[]; to: number; runId: string; line: number }[] = [];
  for (const change of changes) {
    const line = doc.lineAt(Math.min(change.to, doc.length)).number;
    const last = groups[groups.length - 1];
    if (last && last.runId === change.runId && line <= last.line + 1) {
      last.ids.push(change.id);
      last.to = Math.max(last.to, change.to);
      last.line = Math.max(last.line, line);
    } else groups.push({ ids: [change.id], to: change.to, runId: change.runId, line });
  }
  return groups.map(({ ids, to }) => ({ ids, to }));
}

function decorate(state: EditorState): DecorationSet {
  const changes = state.field(aiChangesField);
  if (!changes.length) return Decoration.none;
  const doc = state.doc;
  const ranges: Range<Decoration>[] = [];
  for (const change of changes) {
    if (change.removed) {
      if (change.block) ranges.push(Decoration.widget({ widget: new GoneWidget(change.removed, true), block: true, side: -1 }).range(doc.lineAt(Math.min(change.from, doc.length)).from));
      else ranges.push(Decoration.widget({ widget: new GoneWidget(change.removed, false), side: -1 }).range(change.from));
    }
    if (change.to > change.from) ranges.push(Decoration.mark({ class: 'cm-aiAdded' }).range(change.from, change.to));
  }
  for (const group of groupChanges(doc, changes)) {
    ranges.push(Decoration.widget({ widget: new PillsWidget(group.ids), side: 1 }).range(doc.lineAt(Math.min(group.to, doc.length)).to));
  }
  return Decoration.set(ranges, true);
}

// ---- acting -----------------------------------------------------------------------------------

/** These changes are the person's now: their marks go, the words stay. */
export function keepChanges(view: EditorView, ids: readonly string[]): void {
  view.dispatch({ effects: keepAiChanges.of(ids) });
}

export function keepAllChanges(view: EditorView): void {
  view.dispatch({ effects: keepAllAiChanges.of(null) });
}

/** The edit that puts one change back as it was. */
function revertSpec(change: AiChange, doc: Text): ChangeSpec {
  if (!change.block) return { from: change.from, to: change.to, insert: change.removed };
  if (change.to > change.from) {
    if (change.removed) return { from: change.from, to: change.to, insert: change.removed };
    // Words only added, on lines of their own: the lines go, their newline with them.
    const after = doc.sliceString(change.to, change.to + 1);
    return { from: change.from, to: after === '\n' ? change.to + 1 : change.to, insert: '' };
  }
  // Lines only taken away: back where they were, on lines of their own.
  const before = change.from > 0 ? doc.sliceString(change.from - 1, change.from) : '\n';
  const lead = before === '\n' ? '' : '\n';
  const tail = change.from < doc.length ? '\n' : '';
  return { from: change.from, to: change.from, insert: `${lead}${change.removed}${tail}` };
}

/** The old words back, the new ones out, in one edit. */
export function revertChanges(view: EditorView, ids: readonly string[]): void {
  const wanted = new Set(ids);
  const mine = view.state.field(aiChangesField).filter((c) => wanted.has(c.id));
  if (!mine.length) return;
  view.dispatch({
    changes: mine.map((c) => revertSpec(c, view.state.doc)),
    effects: keepAiChanges.of(ids),
    annotations: aiEdit.of('revert'),
    userEvent: 'ai.revert',
  });
}

/** The changes a run made, still marked. */
export function changesOfRun(state: EditorState, runId: string): readonly AiChange[] {
  return state.field(aiChangesField).filter((c) => c.runId === runId);
}

// ---- the extension ----------------------------------------------------------------------------

const theme = EditorView.baseTheme({
  // Added words: a wash of the page's ink behind them, faint enough to read through.
  '.cm-aiAdded': {
    backgroundColor: 'color-mix(in oklch, var(--app-ink, currentColor) 11%, transparent)',
    borderRadius: '3px',
    boxDecorationBreak: 'clone',
    WebkitBoxDecorationBreak: 'clone',
  },
  // Words that went: struck through, in the faintest ink, and never as dark as the words that stayed.
  '.cm-aiGone': {
    color: 'var(--app-ink-4, currentColor)',
    textDecoration: 'line-through',
    textDecorationColor: 'color-mix(in oklch, var(--app-ink, currentColor) 45%, transparent)',
    marginInlineEnd: '0.3em',
  },
  '.cm-aiGoneBlock': {
    color: 'var(--app-ink-4, currentColor)',
    textDecoration: 'line-through',
    textDecorationColor: 'color-mix(in oklch, var(--app-ink, currentColor) 45%, transparent)',
    whiteSpace: 'pre-wrap',
    padding: '0 0 0.1em',
  },
  '.cm-aiGoneLine': {
    minHeight: '1em',
  },
  // Keep and Revert: two outlined words a step smaller than the line, like the suggestion pill they are cousins of.
  '.cm-aiPills': {
    display: 'inline-flex',
    gap: '0.35em',
    marginInlineStart: '0.6em',
    verticalAlign: '0.15em',
    whiteSpace: 'nowrap',
  },
  '.cm-aiPill': {
    appearance: 'none',
    display: 'inline-block',
    padding: '0 0.6em',
    border: '1px solid color-mix(in oklch, currentColor 45%, transparent)',
    borderRadius: '999px',
    background: 'transparent',
    color: 'var(--app-ink-3, currentColor)',
    font: 'inherit',
    fontSize: '0.68em',
    lineHeight: '1.7',
    cursor: 'pointer',
    userSelect: 'none',
    WebkitTapHighlightColor: 'transparent',
  },
  '.cm-aiPill[data-act="keep"]': {
    color: 'var(--app-ink, currentColor)',
    borderColor: 'color-mix(in oklch, currentColor 70%, transparent)',
  },
  '.cm-aiPill:active': {
    background: 'color-mix(in oklch, currentColor 12%, transparent)',
  },
});

export interface AiChangesOptions {
  /** Told the marks every time they change, for the note to keep them with it (ai/marks.ts). */
  onMarks?: (changes: readonly AiChange[]) => void;
}

export function aiChanges(options: AiChangesOptions = {}): Extension {
  return [
    aiChangesField,
    landingField,
    EditorView.decorations.compute([aiChangesField], decorate),
    theme,
    EditorView.updateListener.of((update) => {
      const now = update.state.field(aiChangesField);
      if (now !== update.startState.field(aiChangesField)) options.onMarks?.(now);
    }),
  ];
}

import { RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { listLead } from '../core/itemSyntax.ts';

/**
 * A to-do's box and a choice's round box drawn as controls (Matt: "for checkboxes and radios render a large UI
 * component where the [ ] or (x) would be but make them take up the same physical space in the note";
 * docs/DESIGN.md §166).
 *
 * The characters stay in the line, in the monospace face that already makes `[ ]` and `[x]` one width
 * (markdown.module.css `.taskMarker`, choices.ts), and are made transparent; the control is drawn over them, centred
 * in their width and taller than their letters. So nothing on the line moves: a wrapped item still hangs under its
 * first word (glyphLines.ts measures the characters), a tap lands where it did (taskToggle.ts, choices.ts), a
 * selection and a copy take the characters, and Markdown and Formatted draw the same. With the caret or a selection
 * inside the three characters they show as typed, so a box can still be written by hand.
 */

export interface BoxControl {
  /** Where the `[` or `(` is. */
  from: number;
  /** Just past the `]` or `)`. */
  to: number;
  kind: 'task' | 'choice';
  /** Ticked, or picked. */
  on: boolean;
}

/** Nodes whose lines are not list items however they read. */
const CODE = new Set(['FencedCode', 'CodeBlock', 'CodeText', 'HTMLBlock']);

function inCode(state: EditorState, pos: number): boolean {
  for (let node: ReturnType<ReturnType<typeof syntaxTree>['resolveInner']> | null = syntaxTree(state).resolveInner(pos, 1); node; node = node.parent) {
    if (CODE.has(node.name)) return true;
  }
  return false;
}

/** Whether the caret or a selection is inside the box's characters, where they show as typed. */
function writing(state: EditorState, from: number, to: number): boolean {
  return state.selection.ranges.some((range) => (range.empty ? range.head > from && range.head < to : range.from < to && range.to > from));
}

/**
 * The boxes to draw as controls on the lines `from`-`to`: every to-do's box and choice's round box, but those in code
 * and, while the note has the caret (`focused`), those it is inside.
 */
export function boxControls(state: EditorState, from: number, to: number, focused: boolean): BoxControl[] {
  const found: BoxControl[] = [];
  const { doc } = state;
  for (let n = doc.lineAt(from).number, last = doc.lineAt(to).number; n <= last; n += 1) {
    const line = doc.line(n);
    const lead = listLead(line.text);
    if (!lead || lead.boxAt < 0) continue;
    const kind = lead.done != null ? 'task' : 'choice';
    const at = line.from + lead.boxAt;
    const box = { from: at, to: at + 3, kind, on: (kind === 'task' ? lead.done : lead.picked) === true } as const;
    if (inCode(state, at)) continue;
    if (focused && writing(state, box.from, box.to)) continue;
    found.push(box);
  }
  return found;
}

const marks = {
  task: Decoration.mark({ class: 'cm-boxControl', attributes: { 'data-box': 'task' } }),
  taskOn: Decoration.mark({ class: 'cm-boxControl', attributes: { 'data-box': 'task', 'data-on': '' } }),
  choice: Decoration.mark({ class: 'cm-boxControl', attributes: { 'data-box': 'choice' } }),
  choiceOn: Decoration.mark({ class: 'cm-boxControl', attributes: { 'data-box': 'choice', 'data-on': '' } }),
};

function decorate(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const { from, to } of view.visibleRanges) {
    for (const box of boxControls(view.state, from, to, view.hasFocus)) {
      builder.add(box.from, box.to, marks[box.on ? (box.kind === 'task' ? 'taskOn' : 'choiceOn') : box.kind]);
    }
  }
  return builder.finish();
}

/** Lucide's check, white on the ticked box. */
const CHECK = `url("data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>')}")`;

/** The control's size: larger than the letters it stands on, narrower than their three-character width. */
const SIZE = '1.3em';

const centred = {
  content: '""',
  position: 'absolute',
  insetInlineStart: '50%',
  insetBlockStart: '50%',
  transform: 'translate(-50%, -50%)',
  boxSizing: 'border-box',
  pointerEvents: 'none',
} as const;

const theme = EditorView.baseTheme({
  '.cm-boxControl': {
    position: 'relative',
    color: 'transparent',
  },
  // The highlighter's own span for `[ ]` (`.taskMarker`) may sit inside, with its accent colour.
  '.cm-boxControl *': {
    color: 'transparent',
  },
  '.cm-boxControl::before': {
    ...centred,
    inlineSize: SIZE,
    blockSize: SIZE,
    border: '0.12em solid color-mix(in oklch, var(--glacier-accent-solid) 70%, var(--glacier-text-subtle))',
    borderRadius: '0.32em',
    background: 'var(--glacier-bg)',
    transition: 'background-color 120ms ease, border-color 120ms ease',
  },
  '.cm-boxControl[data-on]::before': {
    borderColor: 'var(--glacier-accent-solid)',
    background: 'var(--glacier-accent-solid)',
  },
  '.cm-boxControl[data-box="task"][data-on]::after': {
    ...centred,
    inlineSize: SIZE,
    blockSize: SIZE,
    background: 'var(--glacier-accent-contrast)',
    WebkitMask: `${CHECK} center / 68% no-repeat`,
    mask: `${CHECK} center / 68% no-repeat`,
  },
  // A choice is round, and picked it is a ring with a dot in it rather than a filled box.
  '.cm-boxControl[data-box="choice"]::before': {
    borderRadius: '50%',
  },
  '.cm-boxControl[data-box="choice"][data-on]::before': {
    background: 'var(--glacier-bg)',
  },
  '.cm-boxControl[data-box="choice"][data-on]::after': {
    ...centred,
    inlineSize: '0.62em',
    blockSize: '0.62em',
    borderRadius: '50%',
    background: 'var(--glacier-accent-solid)',
  },
  '@media (prefers-reduced-motion: reduce)': {
    '.cm-boxControl::before': { transition: 'none' },
  },
});

export function drawnBoxes(): Extension {
  return [
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;
        constructor(view: EditorView) {
          this.decorations = decorate(view);
        }
        update(update: ViewUpdate) {
          if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) {
            this.decorations = decorate(update.view);
          }
        }
      },
      { decorations: (value) => value.decorations },
    ),
    theme,
  ];
}

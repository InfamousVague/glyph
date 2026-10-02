import { RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { syntaxTree } from '@codemirror/language';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { listLead } from '../core/itemSyntax.ts';

/**
 * A to-do's box and a choice's round box drawn as controls (Matt: "for checkboxes and radios render a large UI
 * component where the [ ] or (x) would be but make them take up the same physical space in the note";
 * docs/DESIGN.md §166).
 *
 * The box is one atomic widget drawn in place of the three characters `[ ]`, `[x]`, `( )` or `(x)`, holding those
 * characters inside it in the monospace face that already makes them one width (markdown.module.css `.taskMarker`,
 * choices.ts), made transparent, so the control sits centred in their width and nothing on the line moves. The
 * characters are still in the document, so a copy and the Markdown view take them, and ticking a box changes them.
 *
 * It is ONE widget rather than a mark over the characters, and the widget is updated in place when it is ticked
 * (`updateDOM`) rather than torn down and built again. A mark drawn with a `::before` could split across the two text
 * runs a toggle's edit leaves behind, and for the length of the fill's transition the box was drawn twice (Matt: "the
 * checkboxes duplicate when clicking during the animation"). A single widget cannot split, and updating it in place
 * keeps the fill's animation.
 *
 * With the caret or a selection touching the three characters the box gives way to them, so it can still be written
 * by hand: arrow onto it and the `[ ]` is there to edit.
 */

export interface BoxControl {
  /** Where the `[` or `(` is. */
  from: number;
  /** Just past the `]` or `)`. */
  to: number;
  kind: 'task' | 'choice';
  /** Ticked, or picked. */
  on: boolean;
  /** The three characters, held inside the widget for their width. */
  text: string;
}

/** Nodes whose lines are not list items however they read. */
const CODE = new Set(['FencedCode', 'CodeBlock', 'CodeText', 'HTMLBlock']);

function inCode(state: EditorState, pos: number): boolean {
  for (let node: ReturnType<ReturnType<typeof syntaxTree>['resolveInner']> | null = syntaxTree(state).resolveInner(pos, 1); node; node = node.parent) {
    if (CODE.has(node.name)) return true;
  }
  return false;
}

/**
 * Whether the caret or a selection touches the box's characters, where they show as typed. Edges count (the caret at
 * either side), so arrowing onto the box reveals it: a replaced widget has no inside for the caret to land in.
 */
function writing(state: EditorState, from: number, to: number): boolean {
  return state.selection.ranges.some((range) => range.from <= to && range.to >= from);
}

/**
 * The boxes to draw as controls on the lines `from`-`to`: every to-do's box and choice's round box, but those in code
 * and, while the note has the caret (`focused`), those it is touching.
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
    const box: BoxControl = { from: at, to: at + 3, kind, on: (kind === 'task' ? lead.done : lead.picked) === true, text: line.text.slice(lead.boxAt, lead.boxAt + 3) };
    if (inCode(state, at)) continue;
    if (focused && writing(state, box.from, box.to)) continue;
    found.push(box);
  }
  return found;
}

/** Lucide's check, black on the ticked box's accent fill. */
const CHECK = `url("data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>')}")`;

/** The control's size: larger than the letters it stands on, narrower than their three-character width. */
const SIZE = '1.3em';

/**
 * The box, as one element drawn in place of its characters. The characters sit inside it, transparent, for the width;
 * the `::before` is the box and the `::after` the check or the dot. Ticking it flips `data-on`, which the stylesheet
 * animates, and `updateDOM` does that on the same node so the box is never drawn twice.
 */
class BoxWidget extends WidgetType {
  constructor(
    readonly kind: 'task' | 'choice',
    readonly on: boolean,
    readonly text: string,
  ) {
    super();
  }

  eq(other: BoxWidget): boolean {
    return other.kind === this.kind && other.on === this.on && other.text === this.text;
  }

  toDOM(): HTMLElement {
    const box = document.createElement('span');
    box.className = 'cm-boxControl';
    box.dataset.box = this.kind;
    if (this.on) box.dataset.on = '';
    const text = document.createElement('span');
    text.className = 'cm-boxText';
    text.textContent = this.text;
    box.append(text);
    return box;
  }

  /** The same node updated, not a new one: a toggle flips the fill on the box already on the page, so it animates. */
  updateDOM(dom: HTMLElement): boolean {
    if (!(dom instanceof HTMLElement) || !dom.classList.contains('cm-boxControl')) return false;
    dom.dataset.box = this.kind;
    if (this.on) dom.dataset.on = '';
    else delete dom.dataset.on;
    const text = dom.querySelector('.cm-boxText');
    if (text && text.textContent !== this.text) text.textContent = this.text;
    return true;
  }

  /** A press is the note's, for taskToggle.ts and choices.ts to answer by where it landed; the widget takes nothing. */
  ignoreEvent(): boolean {
    return false;
  }
}

function decorate(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  for (const { from, to } of view.visibleRanges) {
    for (const box of boxControls(view.state, from, to, view.hasFocus)) {
      builder.add(box.from, box.to, Decoration.replace({ widget: new BoxWidget(box.kind, box.on, box.text) }));
    }
  }
  return builder.finish();
}

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
    display: 'inline-block',
  },
  // The characters inside, kept for their width and transparent; the control is drawn over them.
  '.cm-boxText': {
    color: 'transparent',
    fontFamily: 'var(--glacier-font-mono)',
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

import { RangeSetBuilder, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, WidgetType, type DecorationSet } from '@codemirror/view';
import { createElement } from 'react';
import { CanvasView } from '../canvas/CanvasView.tsx';
import { canvasOf, type Canvas } from '../canvas/jsonCanvas.ts';
import { caretIn, focusMoved, openOnPress, trackFocus } from './drawnBlock.ts';
import { mountReact } from './reactMount.ts';

/**
 * A canvas in a frame inside a note (Matt: "embed a frame of a canvas within another note so we can browse the
 * canvas from within a frame inside the note").
 *
 *   ![[Cabin weekend, laid out]]
 *
 * A line that is only that - a wiki link with `!` before it, which is how Obsidian embeds one note in another - is
 * drawn as the canvas it names, in a frame the note's width and a screen's third tall, browsable as the canvas
 * itself is: a finger or a wheel pans, a pinch or the modifier and wheel zooms, the minimap sits in the corner, and
 * the whole canvas is fitted to the frame to begin with. It is the canvas note's own view (canvas/CanvasView.tsx)
 * with no way to change it, so what is drawn is what is on the canvas note now, and a card that is a note draws
 * that note small as it does there. Over the frame, the canvas's name and an Open, which opens the canvas note.
 *
 * The line keeps its markdown: with the caret on it the frame steps aside and the line shows as typed, the way a
 * diagram's fence does (editor/mermaid.ts), and leaving it draws the frame again. The words are a wiki link like
 * any other (editor/wikiLinks.ts), so the note reads as a link to the canvas anywhere else, and a title that names
 * no canvas - no note, or a note of words - is left as the link it is.
 *
 * A state field, as pictures and diagrams are: a block widget's height has to be known before layout, and a plugin's
 * decorations cannot say. The document is scanned whole; embeds are rare and notes are short.
 */

/** A line that is only an embed: `![[Title]]`, with whatever `#anchor` the link carries. */
const FRAME = /^\s*!\[\[([^\]\n]{1,120})\]\]\s*$/;

export interface Frame {
  /** The line, counting from 1. */
  line: number;
  /** The title as written: everything before a `#`. */
  title: string;
}

/** Every embed in the note, in order. */
export function framesIn(doc: string): Frame[] {
  const found: Frame[] = [];
  const lines = doc.split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const match = FRAME.exec(lines[i] ?? '');
    if (!match) continue;
    const inside = (match[1] ?? '').trim();
    const hash = inside.indexOf('#');
    const title = (hash >= 0 ? inside.slice(0, hash) : inside).trim();
    if (title) found.push({ line: i + 1, title });
  }
  return found;
}

export interface FrameOptions {
  /** A note's body by its title, or null where there is no note: the canvas is read from it. */
  body: (title: string) => string | null;
  /** For the canvas's own note cards: whether a note exists, and opening one. `open` also opens the canvas note. */
  known: (title: string) => boolean;
  open: (title: string, anchor?: string) => void;
  /** Which way the app is painted, for the canvas's colours. */
  dark: () => boolean;
}

/** How tall a frame is, in CSS pixels, at most; the theme below keeps it under half the screen on a phone. */
const FRAME_HEIGHT = 360;
/** The bar over the frame: its name and the Open. */
const BAR_HEIGHT = 30;

/** Canvas notes read, by body: a keystroke elsewhere in the note must not parse every canvas again. */
const parsed = new Map<string, Canvas | null>();

function canvasIn(body: string): Canvas | null {
  let canvas = parsed.get(body);
  if (canvas === undefined) {
    canvas = canvasOf(body);
    if (parsed.size > 32) parsed.clear();
    parsed.set(body, canvas);
  }
  return canvas;
}

/** How to take a frame's canvas down again, by the element it was drawn in. */
const unmounts = new WeakMap<HTMLElement, () => void>();

class FrameWidget extends WidgetType {
  constructor(
    readonly title: string,
    /** The canvas note's body, which is what says whether the frame is the same one. */
    readonly body: string,
    readonly canvas: Canvas,
    readonly from: number,
    readonly dark: boolean,
    readonly options: FrameOptions,
  ) {
    super();
  }

  eq(other: FrameWidget): boolean {
    return other.title === this.title && other.body === this.body && other.from === this.from && other.dark === this.dark;
  }

  get estimatedHeight(): number {
    return FRAME_HEIGHT + BAR_HEIGHT;
  }

  toDOM(view: EditorView): HTMLElement {
    const wrap = document.createElement('figure');
    wrap.className = 'cm-canvasFrame';
    wrap.setAttribute('aria-label', `Canvas: ${this.title}`);

    const bar = document.createElement('figcaption');
    bar.className = 'cm-canvasFrameBar';
    const name = document.createElement('span');
    name.className = 'cm-canvasFrameName';
    name.textContent = this.title;
    name.title = 'Edit the link';
    // A press on the name puts the caret on the line: the frame steps aside and the link can be edited.
    openOnPress(view, name, this.from);
    const open = document.createElement('button');
    open.type = 'button';
    open.className = 'cm-canvasFrameOpen';
    open.textContent = 'Open';
    open.setAttribute('aria-label', `Open the canvas ${this.title}`);
    open.addEventListener('click', (event) => {
      event.preventDefault();
      this.options.open(this.title);
    });
    bar.append(name, open);

    const box = document.createElement('div');
    box.className = 'cm-canvasFrameBox';
    wrap.append(bar, box);

    // The canvas note's own view, with no `onChange`: browsable, not changeable.
    unmounts.set(
      wrap,
      mountReact(
        box,
        createElement(CanvasView, {
          canvas: this.canvas,
          dark: this.dark,
          wiki: { known: this.options.known, open: this.options.open, body: this.options.body },
        }),
      ),
    );
    return wrap;
  }

  destroy(dom: HTMLElement): void {
    unmounts.get(dom)?.();
    unmounts.delete(dom);
  }

  ignoreEvent(): boolean {
    // Every gesture in the frame is the canvas's: a drag pans it, a wheel too, and the name and Open have their own.
    return true;
  }
}

/** The app painted the other way, or a note changed: every frame is looked at again, and redrawn where it differs. */
export const refreshCanvasFrames = StateEffect.define<null>();

const theme = EditorView.baseTheme({
  '.cm-canvasFrame': {
    display: 'block',
    margin: '0',
    // A block widget is not a line, so it has no line's gutter: the same one, by hand (editor/mermaid.ts does this too).
    padding: '0.4em var(--app-gutter, 1rem) 0.8em',
  },
  '.cm-canvasFrameBar': {
    display: 'flex',
    alignItems: 'center',
    gap: '0.6em',
    blockSize: `${BAR_HEIGHT}px`,
    padding: '0 0.2em',
    fontSize: '0.86em',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
  },
  '.cm-canvasFrameName': {
    flex: '1',
    minInlineSize: '0',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
    cursor: 'text',
  },
  '.cm-canvasFrameOpen': {
    appearance: 'none',
    margin: '0',
    padding: '0.15em 0.75em',
    border: '1px solid var(--glacier-border-subtle)',
    borderRadius: '999px',
    background: 'transparent',
    color: 'inherit',
    font: 'inherit',
    cursor: 'pointer',
  },
  '.cm-canvasFrameOpen:hover': {
    color: 'var(--app-ink, currentColor)',
    borderColor: 'color-mix(in oklch, var(--app-ink, currentColor) 40%, transparent)',
  },
  '.cm-canvasFrameBox': {
    blockSize: `clamp(220px, 42vh, ${FRAME_HEIGHT}px)`,
    border: '1px solid var(--glacier-border-subtle)',
    borderRadius: 'var(--glacier-radius-lg, 16px)',
    overflow: 'hidden',
    // The frame's gestures are the canvas's, never the note's scroll.
    touchAction: 'none',
  },
});

/** `![[A canvas]]` on a line of its own draws that canvas in a frame. */
export function canvasFrames(options: FrameOptions): Extension {
  const build = (state: EditorState): DecorationSet => {
    const builder = new RangeSetBuilder<Decoration>();
    const editable = state.facet(EditorView.editable);
    const dark = options.dark();
    for (const frame of framesIn(state.doc.toString())) {
      const line = state.doc.line(frame.line);
      // The caret on the line: the link itself, to edit. Elsewhere, and in a view with no caret, the canvas.
      const inside = editable && caretIn(state, line.from, line.to);
      if (inside) continue;
      const body = options.body(frame.title);
      const canvas = body === null ? null : canvasIn(body);
      if (body === null || !canvas) continue;
      builder.add(line.from, line.to, Decoration.replace({ widget: new FrameWidget(frame.title, body, canvas, line.from, dark, options), block: true }));
    }
    return builder.finish();
  };

  const field = StateField.define<DecorationSet>({
    create: build,
    update(decorations, tr) {
      const poked = focusMoved(tr) || tr.effects.some((effect) => effect.is(refreshCanvasFrames));
      if (tr.docChanged || tr.selection || poked || tr.reconfigured) return build(tr.state);
      return decorations;
    },
    provide: (field) => EditorView.decorations.from(field),
  });

  return [trackFocus, field, theme];
}

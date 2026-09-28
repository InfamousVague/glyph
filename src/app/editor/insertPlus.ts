import { Prec, StateEffect, StateField, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import { prefersStill } from '../core/motion.ts';
import { plusLine } from './plusLine.ts';

/**
 * The + beside the line (Matt: "Add a + button next to the line we're typing in, in the empty gutter padding and add
 * a menu to add things like geotag cards images videos and more"). It opens the list of things to add
 * (editor/AddList.tsx); where each goes is editor/inserts.ts.
 *
 * **Where.** The only empty room beside a line is the line's own start padding, the gutter every line already leaves
 * (markdown.module.css, `--app-gutter`), so the + sits there beside the caret's line: two strokes in the third ink, no
 * ring, since the app's ring is wider than the phone's gutter. It is a button in the scroller, not in the lines, as
 * the swipe's tile is (editor/swipeItems.ts), so none of CodeMirror's handlers on the content ever see it and nothing
 * in the lines moves. Its target is that line's gutter and nothing more: a tap in another line's gutter, or on this
 * line's first letter, still lands where it always did.
 *
 * **When.** On an empty line only (Matt: "EMPTY LINES ONLY, on every platform, Mac hover included"), the rule and its
 * gates are editor/plusLine.ts. It comes once the caret has rested there for `SETTLE_MS`, so Enter, Enter in a run
 * never flickers it, and the first letter typed makes the line one with words and takes it away at once. A + that
 * had not finished arriving goes with no fade. Nothing about it waits for the keyboard to finish composing: showing
 * and hiding it never touches the lines. A note opened to be read shows nothing: the note screen never focuses the
 * editor on its own.
 *
 * **The press** is the suggestion pill's rule, proven on the phone (editor/suggestions.ts): a pointer or mouse press
 * has its default taken away, which keeps the editor's focus, its caret and the keyboard; a touch is only kept from
 * the editor, since a touch whose default is taken never becomes a click on Android; and a long press is kept from
 * press and hold (editor/pressAndHold.ts). A tap or a click turns the + into a × and asks for the list; the editor
 * keeps its focus, so the list is driven from the editor's keys (Up, Down, Enter, Escape, Left and Right), with the
 * highlighted row named to a screen reader by `aria-activedescendant`, as CodeMirror's own completion list is. Any
 * other key, a change or a caret move closes it. Tab reaches the + from the editor even while it waits, and Enter on
 * it opens the list with the focus in it.
 *
 * While shown, its line carries `cm-plusLine`, which fades the bookmark's edge in the same gutter; the class is only
 * changed while nothing is being composed, since rebuilding a line under a live composition breaks typing on a phone
 * (editor/glyphLines.ts).
 */

/** How long the caret rests on an empty line before the + comes: long enough that Enter, Enter never flickers it. */
export const SETTLE_MS = 150;
/** The + arriving, on typing's own arc (editor/wispMotion.ts `IN_MS`); a keystroke inside it takes it at once. */
const IN_MS = 350;
/** The + leaving, a deleted letter's beat (editor/wispMotion.ts `DELETE_MS`). */
const OUT_MS = 140;

/** The keys the open list takes from the editor. */
export type PlusKey = 'up' | 'down' | 'enter' | 'escape' | 'left' | 'right';

/** The + pressed: the button (the list is placed against its row), and how it was pressed. */
export interface PlusOpening {
  button: HTMLElement;
  /** The line the + was beside, counting from 1. */
  line: number;
  /** A fine pointer (the Mac), a finger, or the keyboard on the + itself (focus goes into the list). */
  by: 'pointer' | 'touch' | 'keyboard';
}

export interface PlusHooks {
  /** Whether the screen allows a + now (editor/NoteScreen.tsx): asked on every look. */
  allowed: () => boolean;
  onOpen: (opening: PlusOpening) => void;
  /** The list is to close: a key it does not take, a change, a caret move, the × pressed. */
  onClose: () => void;
  /** A key while the list is open from the editor: whether the list took it. */
  onKey: (key: PlusKey) => boolean;
}

/** The list open, as the editor knows it: its element's id and the row lit, for a screen reader. */
export interface PlusMenu {
  list: string;
  active: string | null;
}

/** The screen's own reasons changed (an AI run started or ended, the view switched): the + looks again. */
export const plusRecheck = StateEffect.define<null>();
/** The list opened or closed (null), or its lit row moved. */
export const plusMenu = StateEffect.define<PlusMenu | null>();
/** The line the + is shown beside, by its start, or null. */
const plusShown = StateEffect.define<number | null>();

const menuField = StateField.define<PlusMenu | null>({
  create: () => null,
  update(value, tr) {
    let next = value;
    for (const effect of tr.effects) if (effect.is(plusMenu)) next = effect.value;
    return next;
  },
});

/** Whether the list is open, for a caller outside the plugin. */
export function plusOpen(view: EditorView): boolean {
  return view.state.field(menuField, false) != null;
}

/** The list closed, as the editor knows it: the × turns back into a +. Before a row writes, so the write is not read as a change made with the list open. */
export function closePlus(view: EditorView): void {
  if (plusOpen(view) && view.dom.isConnected) view.dispatch({ effects: plusMenu.of(null) });
}

const shownField = StateField.define<number | null>({
  create: () => null,
  update(value, tr) {
    let next = value !== null && tr.docChanged ? tr.changes.mapPos(value, -1) : value;
    for (const effect of tr.effects) if (effect.is(plusShown)) next = effect.value;
    return next;
  },
});

const plusLineMark = Decoration.line({ class: 'cm-plusLine' });

/** The class on the +'s line, at its start however it moved; CodeMirror keeps the line's DOM while only this changes. */
const plusLineClass = EditorView.decorations.compute([shownField], (state) => {
  const pos = state.field(shownField);
  if (pos === null) return Decoration.none;
  return Decoration.set([plusLineMark.range(state.doc.lineAt(Math.min(pos, state.doc.length)).from)]);
});

/** The lit row named to a screen reader while the list is driven from the editor. */
const menuAttributes = EditorView.contentAttributes.compute([menuField], (state): Record<string, string> => {
  const menu = state.field(menuField);
  return menu?.active ? { 'aria-controls': menu.list, 'aria-activedescendant': menu.active } : {};
});

const KEYS: Record<string, PlusKey> = { ArrowUp: 'up', ArrowDown: 'down', Enter: 'enter', Escape: 'escape', ArrowLeft: 'left', ArrowRight: 'right' };
const MODIFIERS = new Set(['Shift', 'Control', 'Alt', 'Meta', 'CapsLock', 'Fn']);

/** Two strokes, round-capped, drawn in the ink the button is. */
const PLUS_SVG = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M6 1.5v9M1.5 6h9" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>';

type Look = 'off' | 'waiting' | 'shown' | 'leaving';

/** The line's own element, whose box is the row the + sits beside; null where it is not drawn (off screen). */
function lineElement(view: EditorView, from: number): HTMLElement | null {
  try {
    const at = view.domAtPos(from).node;
    return (at instanceof HTMLElement ? at : at.parentElement)?.closest<HTMLElement>('.cm-line') ?? null;
  } catch {
    return null;
  }
}

function plusView(hooks: PlusHooks) {
  return ViewPlugin.fromClass(
    class {
      readonly button: HTMLButtonElement;
      private look: Look = 'off';
      /** The line the + is for, counting from 1. */
      private line: number | null = null;
      private shownAt = 0;
      private settleTimer = 0;
      private leaveTimer = 0;
      private pointer: string | null = null;
      private gone = false;

      constructor(readonly view: EditorView) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'cm-plus';
        button.innerHTML = PLUS_SVG;
        button.setAttribute('aria-label', 'Add to this note');
        button.setAttribute('aria-haspopup', 'menu');
        button.setAttribute('aria-expanded', 'false');
        button.hidden = true;
        button.dataset.state = 'off';
        this.button = button;
        const keep = (event: Event) => {
          event.preventDefault();
          event.stopPropagation();
        };
        button.addEventListener('pointerdown', (event) => {
          this.pointer = event.pointerType;
          keep(event);
        });
        button.addEventListener('mousedown', keep);
        // Only kept from the editor: a touchstart whose default is taken away never becomes a click on Android.
        button.addEventListener('touchstart', (event) => event.stopPropagation(), { passive: true });
        // A long press on the + is not press and hold's (editor/pressAndHold.ts listens on the editor for it).
        button.addEventListener('contextmenu', keep);
        button.addEventListener('click', (event) => {
          keep(event);
          const by = event.detail === 0 ? 'keyboard' : this.pointer === 'mouse' || this.pointer === 'pen' ? 'pointer' : 'touch';
          this.pointer = null;
          this.toggle(by);
        });
        // Tab reaches it while it waits: taking the focus shows it at once.
        button.addEventListener('focus', () => {
          if (this.look === 'waiting') this.show();
        });
        button.addEventListener('blur', () => queueMicrotask(() => this.reconsider(false)));
        view.scrollDOM.appendChild(button);
        view.scrollDOM.addEventListener('pointermove', this.hover);
        this.reconsider(false);
      }

      update(update: ViewUpdate) {
        const open = update.state.field(menuField, false) != null;
        this.button.setAttribute('aria-expanded', String(open));
        if (open) {
          // The list is up: the + stays, a ×, whatever the rules say. What the person does in the note closes it.
          if (update.docChanged || update.selectionSet) queueMicrotask(() => hooks.onClose());
          if (update.geometryChanged || update.viewportChanged) this.place();
          return;
        }
        const menuMoved = update.transactions.some((tr) => tr.effects.some((effect) => effect.is(plusMenu) || effect.is(plusRecheck)));
        if (update.docChanged || update.selectionSet || update.focusChanged || menuMoved) this.reconsider(update.docChanged || update.selectionSet);
        else if (update.geometryChanged || update.viewportChanged) this.place();
        this.markLine();
      }

      destroy() {
        this.gone = true;
        window.clearTimeout(this.settleTimer);
        window.clearTimeout(this.leaveTimer);
        this.view.scrollDOM.removeEventListener('pointermove', this.hover);
        this.button.remove();
      }

      /** The line the + belongs beside now, by the rules (editor/plusLine.ts). */
      private target() {
        const view = this.view;
        const focused = view.hasFocus || document.activeElement === this.button;
        return plusLine(view.state, { focused, editable: view.state.facet(EditorView.editable), allowed: hooks.allowed() });
      }

      /** Looks again: the + stays where it is, goes, or waits to come beside another line. */
      private reconsider(changed: boolean) {
        if (this.gone || plusOpen(this.view)) return;
        window.clearTimeout(this.settleTimer);
        const line = this.target();
        if (this.look === 'shown') {
          if (line && line.number === this.line && !changed) {
            this.place();
            return;
          }
          this.out(changed);
        }
        this.line = line?.number ?? null;
        if (!line) {
          if (this.look !== 'leaving') this.set('off');
          return;
        }
        if (this.look !== 'leaving') {
          this.set('waiting');
          this.place();
        }
        this.settleTimer = window.setTimeout(() => this.show(), SETTLE_MS);
      }

      private show() {
        if (this.gone) return;
        window.clearTimeout(this.settleTimer);
        window.clearTimeout(this.leaveTimer);
        const line = this.target();
        if (!line || line.number !== this.line) {
          this.reconsider(false);
          return;
        }
        this.set('shown');
        this.shownAt = performance.now();
        this.place();
        this.markLine();
      }

      /** The + going: on a deleted letter's beat, or at once when it had not finished arriving or motion is asked to be still. */
      private out(changed: boolean) {
        window.clearTimeout(this.leaveTimer);
        const arriving = performance.now() - this.shownAt < IN_MS;
        if ((changed && arriving) || prefersStill()) {
          this.button.dataset.cut = '';
          this.set('waiting');
          requestAnimationFrame(() => delete this.button.dataset.cut);
          return;
        }
        this.set('leaving');
        this.leaveTimer = window.setTimeout(() => {
          if (this.look !== 'leaving') return;
          this.set(this.line === null ? 'off' : 'waiting');
          this.place();
        }, OUT_MS);
      }

      private set(look: Look) {
        this.look = look;
        this.button.dataset.state = look;
        this.button.hidden = look === 'off';
        this.markLine();
      }

      /** The +'s line carries `cm-plusLine` while the + is shown there, changed only while nothing is composed. */
      private markLine() {
        queueMicrotask(() => {
          if (this.gone || this.view.composing) return;
          const state = this.view.state;
          const want = this.look === 'shown' && this.line !== null && this.line <= state.doc.lines ? state.doc.line(this.line).from : null;
          const now = state.field(shownField, false) ?? null;
          const nowLine = now === null ? null : state.doc.lineAt(Math.min(now, state.doc.length)).from;
          if (nowLine !== want) this.view.dispatch({ effects: plusShown.of(want) });
        });
      }

      /** The + opened or closed: the list is the screen's (editor/AddList.tsx). */
      private toggle(by: PlusOpening['by']) {
        if (plusOpen(this.view)) {
          hooks.onClose();
          return;
        }
        if (this.look === 'waiting' && by === 'keyboard') this.show();
        if (this.look !== 'shown' || this.line === null) return;
        hooks.onOpen({ button: this.button, line: this.line, by });
      }

      /** A fine pointer over the +'s place while it waits brings it at once. */
      private hover = (event: PointerEvent) => {
        if (event.pointerType !== 'mouse' || this.look !== 'waiting') return;
        const box = this.button.getBoundingClientRect();
        if (event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom) this.show();
      };

      /** Beside its line's row: measured from the line's own box, in the scroller's coordinates, as the swipe's tile is. */
      private place() {
        if (this.look === 'leaving' || this.line === null) return;
        const number = this.line;
        this.view.requestMeasure({
          key: this,
          read: (view) => {
            if (number > view.state.doc.lines) return null;
            const from = view.state.doc.line(number).from;
            const element = lineElement(view, from);
            if (!element) return null;
            const row = element.getBoundingClientRect();
            const scroller = view.scrollDOM.getBoundingClientRect();
            return { top: row.top - scroller.top + view.scrollDOM.scrollTop, height: row.height, left: view.contentDOM.offsetLeft };
          },
          write: (box) => {
            if (!box) return;
            this.button.style.top = `${box.top}px`;
            this.button.style.height = `${box.height}px`;
            this.button.style.left = `${box.left}px`;
          },
        });
      }
    },
  );
}

/** While the list is open from the editor, its keys go to it; any other key closes it and does what it always does. */
function menuKeys(hooks: PlusHooks): Extension {
  return Prec.highest(
    EditorView.domEventHandlers({
      keydown(event, view) {
        if (!plusOpen(view)) return false;
        const key = KEYS[event.key];
        if (key && hooks.onKey(key)) {
          event.preventDefault();
          return true;
        }
        if (MODIFIERS.has(event.key)) return false;
        hooks.onClose();
        return false;
      },
    }),
  );
}

const plusTheme = EditorView.baseTheme({
  '.cm-plus': {
    position: 'absolute',
    top: '0',
    left: '0',
    zIndex: '3',
    // The gutter's width and the row's height (set on placing): its target, and no more.
    inlineSize: 'var(--app-gutter, 1rem)',
    display: 'grid',
    placeItems: 'center',
    margin: '0',
    padding: '0',
    border: 'none',
    borderRadius: '0',
    background: 'transparent',
    color: 'var(--app-ink-3, currentColor)',
    cursor: 'pointer',
    opacity: '0',
    transform: 'translateY(2px)',
    transition: `opacity ${OUT_MS}ms ease-out, transform ${OUT_MS}ms ease-out, color 120ms ease-out`,
    WebkitTapHighlightColor: 'transparent',
    touchAction: 'manipulation',
  },
  '.cm-plus[hidden]': { display: 'none' },
  // Waiting out the settle, or leaving: in the tab order, never under a finger.
  ".cm-plus[data-state='waiting'], .cm-plus[data-state='leaving']": { pointerEvents: 'none' },
  ".cm-plus[data-state='shown'], .cm-plus[aria-expanded='true']": {
    opacity: '1',
    transform: 'none',
    transition: `opacity ${IN_MS}ms cubic-bezier(0.2, 0.8, 0.2, 1), transform ${IN_MS}ms cubic-bezier(0.2, 0.8, 0.2, 1), color 120ms ease-out`,
  },
  '.cm-plus[data-cut]': { transition: 'none' },
  '.cm-plus svg': {
    // 12px at the default spacing, and smaller with the gutter, never past 8px.
    inlineSize: 'clamp(8px, calc(var(--app-gutter, 1rem) - 6px), 0.75rem)',
    blockSize: 'clamp(8px, calc(var(--app-gutter, 1rem) - 6px), 0.75rem)',
    transition: 'transform var(--app-turn, 420ms ease)',
  },
  // Open, the + is a ×: the same strokes, turned.
  ".cm-plus[aria-expanded='true'] svg": { transform: 'rotate(45deg)' },
  ".cm-plus:active, .cm-plus[aria-expanded='true']": { color: 'var(--app-ink, currentColor)' },
  '.cm-plus:focus-visible': {
    outline: '2px solid var(--glacier-focus-ring, currentColor)',
    outlineOffset: '-2px',
    opacity: '1',
  },
  '@media (hover: hover) and (pointer: fine)': {
    '.cm-plus:hover': { color: 'var(--app-ink-2, currentColor)' },
  },
  // The bookmark's gold edge is in the same gutter: it steps aside on the +'s own beat while the + is there.
  '.cm-bookmarked::before': { transition: `opacity ${OUT_MS}ms ease-out` },
  '.cm-bookmarked.cm-plusLine::before': { opacity: '0' },
  '@media (prefers-reduced-motion: reduce)': {
    '.cm-plus': { transform: 'none', transition: 'none' },
    ".cm-plus[data-state='shown'], .cm-plus[aria-expanded='true']": { transition: 'opacity 160ms linear' },
    '.cm-plus svg': { transition: 'none' },
  },
});

/** The + beside an empty line, and what opens its list: only the note screen installs it (editor/Editor.tsx `plus`). */
export function insertPlus(hooks: PlusHooks): Extension {
  return [menuField, shownField, plusLineClass, menuAttributes, plusView(hooks), menuKeys(hooks), plusTheme];
}

import { Facet, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet } from '@codemirror/view';
import { keyboardUp, watchKeyboard } from '../core/keyboard.ts';
import type { NameOffer } from '../core/noteNames.ts';
import { frontMatter } from './extended.ts';

/**
 * A new note's blank page, under its first line (docs/DESIGN.md §144): the names it can be given (core/noteNames.ts),
 * a row of quiet chips, and under them whatever the screen puts in its own element there, which is the template cards
 * and the ghost (editor/NoteScreen.tsx). Matt: "Add suggestions for note names like the days date and other standard
 * note formats", and the templates "on the blank page itself".
 *
 * **Inside the editor**, as a block after line 1, so it follows the line wherever the map's box above puts it and the
 * page scrolls it with the words. CodeMirror takes a block decoration only from a state field, so this is one, as the
 * folded front matter is (editor/extended.ts). The screen says what is offered (`setOffers`): the names, or none, and
 * its element, only while the note is fresh and blank (core/untouched.ts).
 *
 * **Only while the page is being written in**: the editor has the focus (or the focus is on a chip, reached by Tab), and
 * the page is ready for words. Ready is a device with no keyboard on the screen, the keyboard up (core/keyboard.ts), or
 * a tap of the person's own ended on the words, or a key of theirs reached them. A tap is taken at its click, its last
 * event, and never at its pointerup: a touch's mouse events and its click come after the finger has left, at the place
 * it left, so chips drawn at the pointerup were under the click and it picked one (found in review: a first tap on a
 * blank page at 412 named the note or made A day). Nothing drawn at the click is any event's target, so the tap that
 * raises the keyboard never picks a name. Once ready, the page stays ready.
 *
 * **Gone at the first letter** in line 1: the screen stops offering, and the field draws nothing over a line with words
 * whatever it was told. **The press** is the suggestion pill's (editor/suggestions.ts): a pointer or mouse press has its
 * default taken, so the caret does not move, the keyboard does not drop and press and hold does not start; a touch is
 * only stopped, since a touch with its default taken never becomes a click on Android; the click names the note. The
 * block has no margin of its own, which is how CodeMirror measures a block's height; its gap under line 1 is padding.
 */

/** What the screen offers on the blank page: the names, and its element for what goes under them. */
export interface BlankOffers {
  names: readonly NameOffer[] | null;
  /** The screen's own element, drawn under the names: its cards and the ghost. Null for nothing under them. */
  host: HTMLElement | null;
}

/** How the page is told: the name pressed, and the block shown or gone. */
export interface NameChipsConfig {
  /** A device with no keyboard on the screen: the page is ready for words from the start. */
  readyAtOnce: boolean;
  onName: (name: string) => void;
  onShown?: (shown: boolean) => void;
}

const config = Facet.define<NameChipsConfig, NameChipsConfig | null>({ combine: (values) => values[0] ?? null });

/** What the screen offers now. */
export const setOffers = StateEffect.define<BlankOffers>();
/** The editor gained or lost the focus. */
const focusChanged = StateEffect.define<boolean>();
/** The focus went into the block (a chip reached by Tab), or left it. */
const insideChanged = StateEffect.define<boolean>();
/** The page is ready for words. */
const pageReady = StateEffect.define<null>();

interface Page {
  offers: BlankOffers;
  focused: boolean;
  inside: boolean;
  ready: boolean;
  decorations: DecorationSet;
}

const NOTHING: BlankOffers = { names: null, host: null };

function sameNames(one: readonly NameOffer[], two: readonly NameOffer[]): boolean {
  return one.length === two.length && one.every((offer, i) => offer.name === two[i]!.name && offer.label === two[i]!.label);
}

class OffersWidget extends WidgetType {
  constructor(
    readonly names: readonly NameOffer[],
    readonly host: HTMLElement | null,
  ) {
    super();
  }

  eq(other: OffersWidget): boolean {
    return other.host === this.host && sameNames(other.names, this.names);
  }

  toDOM(view: EditorView): HTMLElement {
    const block = document.createElement('div');
    block.className = 'cm-blankOffers';
    // Told after the focus has moved, never inside an update: a block taken away with a chip focused says so on its way out.
    const tell = (inside: boolean) =>
      queueMicrotask(() => {
        if (view.dom.isConnected) view.dispatch({ effects: insideChanged.of(inside) });
      });
    block.addEventListener('focusin', () => tell(true));
    block.addEventListener('focusout', (event) => {
      if (!(event.relatedTarget instanceof Node && block.contains(event.relatedTarget))) tell(false);
    });
    this.fill(block, view);
    return block;
  }

  updateDOM(dom: HTMLElement, view: EditorView): boolean {
    dom.replaceChildren();
    this.fill(dom, view);
    return true;
  }

  private fill(block: HTMLElement, view: EditorView): void {
    if (this.names.length) {
      const group = document.createElement('div');
      group.className = 'cm-nameChips';
      group.setAttribute('role', 'group');
      group.setAttribute('aria-label', 'Names for this note');
      for (const offer of this.names) group.append(chip(offer, view));
      block.append(group);
    }
    if (this.host) block.append(this.host);
  }

  ignoreEvent(): boolean {
    return true;
  }
}

/** One name: a button, pressed the way the suggestion pill is (editor/suggestions.ts). */
function chip(offer: NameOffer, view: EditorView): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'cm-nameChip';
  button.textContent = offer.name;
  button.setAttribute('aria-label', offer.label);
  button.dataset.kind = offer.kind;
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
    view.state.facet(config)?.onName(offer.name);
  });
  return button;
}

/** The block after the first line of words, while everything it waits for holds; nothing otherwise. */
function build(state: EditorState, page: Omit<Page, 'decorations'>): DecorationSet {
  const { names, host } = page.offers;
  if (!(names?.length || host) || !(page.focused || page.inside) || !page.ready) return Decoration.none;
  const front = frontMatter(state.doc);
  const first = front ? front.to + 1 : 1;
  if (first > state.doc.lines) return Decoration.none;
  const line = state.doc.line(first);
  if (line.text.trim()) return Decoration.none;
  return Decoration.set(Decoration.widget({ widget: new OffersWidget(names ?? [], host), block: true, side: 1 }).range(line.to));
}

const pageField = StateField.define<Page>({
  create: (state) => {
    const ready = state.facet(config)?.readyAtOnce ?? false;
    const page = { offers: NOTHING, focused: false, inside: false, ready, decorations: Decoration.none };
    return page;
  },
  update(value, tr) {
    let { offers, focused, inside, ready } = value;
    let told = false;
    for (const effect of tr.effects) {
      if (effect.is(setOffers)) {
        offers = effect.value;
        told = true;
      } else if (effect.is(focusChanged)) {
        focused = effect.value;
        told = true;
      } else if (effect.is(insideChanged)) {
        inside = effect.value;
        told = true;
      } else if (effect.is(pageReady)) {
        ready = true;
        told = true;
      }
    }
    if (!told && !tr.docChanged) return value;
    const next = { offers, focused, inside, ready };
    return { ...next, decorations: build(tr.state, next) };
  },
  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
});

/** Whether the names block is drawn now, for a test or the screen to ask. */
export function offersShown(state: EditorState): boolean {
  return (state.field(pageField, false)?.decorations.size ?? 0) > 0;
}

/**
 * The field told of the editor's focus as it stands. CodeMirror tells its extensions of a focus change once
 * (`focusChangeEffect`), and drops the telling when another change lands first: a new note is focused and given its
 * names and its + in the same moment, and on the Fold's build the names never learned the note had the focus. So the
 * focus is read again a moment after each focus and blur, and told when the field has it wrong.
 */
function syncFocus(view: EditorView): void {
  const page = view.state.field(pageField, false);
  if (!page || !view.dom.isConnected) return;
  const has = view.hasFocus;
  if (page.focused !== has) view.dispatch({ effects: focusChanged.of(has) });
}

/** How long after a focus or a blur the field's word on it is checked: after CodeMirror's own 10ms. */
const FOCUS_CHECK_MS = 20;

/** The page is ready for words, once, from whichever of its signs came first. */
function ready(view: EditorView): void {
  const page = view.state.field(pageField, false);
  if (!page || page.ready) return;
  view.dispatch({ effects: pageReady.of(null) });
}

/** The keyboard's coming, and the person's own tap and key: each makes the page ready. */
const readiness = ViewPlugin.fromClass(
  class {
    private readonly stop: () => void;

    constructor(view: EditorView) {
      if (keyboardUp()) queueMicrotask(() => view.dom.isConnected && ready(view));
      this.stop = watchKeyboard((up) => {
        if (up && view.dom.isConnected) ready(view);
      });
    }

    destroy(): void {
      this.stop();
    }
  },
  {
    eventHandlers: {
      focus(_event, view) {
        window.setTimeout(() => syncFocus(view), FOCUS_CHECK_MS);
      },
      blur(_event, view) {
        window.setTimeout(() => syncFocus(view), FOCUS_CHECK_MS);
      },
      // The tap's click, its last event: see the header. The block is drawn only once the page is ready, so a click
      // on it is never the sign.
      click(_event, view) {
        ready(view);
      },
      keydown(_event, view) {
        ready(view);
      },
    },
  },
);

const theme = EditorView.baseTheme({
  // The gap under line 1, as padding: a tap aimed at the line lands on the line.
  '.cm-blankOffers': {
    paddingBlockStart: '0.75rem',
    paddingInline: 'var(--app-gutter, 0)',
    cursor: 'default',
  },
  '.cm-nameChips': {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 'var(--glacier-space-2)',
  },
  // Quiet: the interface's face, the third ink and a hairline, a size under the words, as a suggestion pill is.
  '.cm-nameChip': {
    appearance: 'none',
    margin: '0',
    padding: 'var(--glacier-space-1) var(--glacier-space-3)',
    border: 'var(--glacier-hairline) solid var(--app-rule, var(--glacier-border-subtle))',
    borderRadius: 'var(--glacier-radius-full)',
    background: 'transparent',
    color: 'var(--app-ink-3, var(--glacier-text-muted))',
    fontFamily: 'var(--glacier-font-sans)',
    fontSize: 'var(--glacier-font-size-sm)',
    lineHeight: '1.5',
    // Proportional figures: Inter's tabular ones spread an ISO name's hyphens to "2026 - 09 - 28" (found in review).
    whiteSpace: 'nowrap',
    cursor: 'pointer',
    WebkitTapHighlightColor: 'transparent',
  },
  '.cm-nameChip:hover, .cm-nameChip:focus-visible': {
    color: 'var(--app-ink-2, var(--glacier-text))',
    borderColor: 'var(--app-ink-3, var(--glacier-border))',
  },
  '.cm-nameChip:focus-visible': {
    outline: '2px solid var(--glacier-focus-ring)',
    outlineOffset: '2px',
  },
});

/** The blank page's names and the screen's element under them, for the note screen's editor. */
export function nameChips(given: NameChipsConfig): Extension {
  return [
    config.of(given),
    pageField,
    EditorView.focusChangeEffect.of((_state, focusing) => focusChanged.of(focusing)),
    readiness,
    EditorView.updateListener.of((update) => {
      const was = offersShown(update.startState);
      const now = offersShown(update.state);
      if (was !== now) update.state.facet(config)?.onShown?.(now);
    }),
    theme,
  ];
}

import { RangeSetBuilder, StateEffect, StateField, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { Suspense, createElement, lazy, useState } from 'react';
import type { GeoTag } from '../core/geotag.ts';
import { placeOfLine } from '../core/placeRefs.ts';
import { onPreferences, preferences } from '../core/preferences.ts';
import { forEachLineOutsideFences, inFence, selectedLines } from './lines.ts';
import { mountReact } from './reactMount.ts';

/**
 * A place in the words, drawn (core/placeRefs.ts): the map card under a line that is only a link to a `geo:` address,
 * and the line folded to its name away from the caret.
 *
 *   [Cais do Sodré, Lisbon](geo:38.7057,-9.1446)
 *
 * The line keeps its Markdown, as a picture's line does (editor/images.ts), and the card is a block widget under it,
 * so the caret and the saved note are exactly as written. Off the caret's line the `[` and the `](geo:…)` fold away
 * and only the name reads, as a long address reads short (editor/links.ts); on the caret's line, in a note being
 * written, it is all there to edit. The card is the note's own map card (editor/MapCard.tsx) with no place chip, since
 * the line above says the name, and a tap on it opens the maps app.
 *
 * Where it may fetch is the caller's to say, read once (editor/Editor.tsx `places`): `live` on the note screen, which
 * draws OpenStreetMap's tiles where the map switch is on and Local only is off, and the quiet card with the reason
 * otherwise; `ask` on a shared page (src/read/Reader.tsx), which fetches nothing until the reader taps "Show the map";
 * and `off` everywhere else, a notebook read straight through and a note drawn small included, whose promise is that
 * nothing on it fetches. There the line still reads as its name.
 *
 * The card's component is fetched only when a place is drawn: a shared page mostly has none, and the card would
 * otherwise ride in the chunk it shares with the app.
 */

export type PlaceMode = 'live' | 'ask' | 'off';

/** How a card draws, from where it is and the switches: MapCard's `mode`, and why it is quiet. */
export function placeLook(mode: Exclude<PlaceMode, 'off'>, prefs: { localOnly: boolean; mapTiles: boolean }): { mode: 'map' | 'quiet' | 'ask'; quietWhy?: 'local-only' | 'off' } {
  if (mode === 'ask') return { mode: 'ask' };
  if (prefs.localOnly) return { mode: 'quiet', quietWhy: 'local-only' };
  if (!prefs.mapTiles) return { mode: 'quiet', quietWhy: 'off' };
  return { mode: 'map' };
}

const MapCard = lazy(() => import('./MapCard.tsx').then((module) => ({ default: module.MapCard })));

/** The card, and the reader's "Show the map" turning it into a map: the only state a place card keeps. */
function PlaceMap({ tag, look, dark }: { tag: GeoTag; look: ReturnType<typeof placeLook>; dark: boolean }) {
  const [asked, setAsked] = useState(false);
  const mode = look.mode === 'ask' && asked ? 'map' : look.mode;
  return createElement(
    Suspense,
    { fallback: null },
    createElement(MapCard, { tag, mode, quietWhy: look.quietWhy, dark, where: false, onShow: () => setAsked(true), className: 'cm-placeMap' }),
  );
}

const unmounts = new WeakMap<HTMLElement, () => void>();

class PlaceWidget extends WidgetType {
  constructor(
    readonly tag: GeoTag,
    readonly look: ReturnType<typeof placeLook>,
    readonly dark: boolean,
  ) {
    super();
  }

  eq(other: PlaceWidget): boolean {
    const a = this.tag;
    const b = other.tag;
    return a.lat === b.lat && a.lon === b.lon && a.place === b.place && a.rough === b.rough && other.look.mode === this.look.mode && other.look.quietWhy === this.look.quietWhy && other.dark === this.dark;
  }

  /** The card's own height (6rem, 8rem from 600px wide) and the room around it, so the note does not jump as it draws. */
  get estimatedHeight(): number {
    if (typeof window === 'undefined') return 110;
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
    return (window.innerWidth >= 600 ? 8 : 6) * rem + 0.85 * rem;
  }

  toDOM(): HTMLElement {
    const wrap = document.createElement('div');
    wrap.className = 'cm-placeCard';
    wrap.dataset.mode = this.look.mode;
    const box = document.createElement('div');
    box.className = 'cm-placeCardBox';
    wrap.append(box);
    unmounts.set(wrap, mountReact(box, createElement(PlaceMap, { tag: this.tag, look: this.look, dark: this.dark })));
    return wrap;
  }

  destroy(dom: HTMLElement): void {
    unmounts.get(dom)?.();
    unmounts.delete(dom);
  }

  /** The card's taps are its own: the editor does not move the caret under them. */
  ignoreEvent(): boolean {
    return true;
  }
}

/** Local only, the map switch or the page's side changed: every card is drawn again as it now should be. */
export const refreshPlaceCards = StateEffect.define<null>();

function cardsOf(state: EditorState, mode: Exclude<PlaceMode, 'off'>, dark: boolean): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const look = placeLook(mode, preferences());
  forEachLineOutsideFences(state.doc, (line) => {
    const place = placeOfLine(line.text);
    if (place) builder.add(line.to, line.to, Decoration.widget({ widget: new PlaceWidget(place.tag, look, dark), block: true, side: 1 }));
  });
  return builder.finish();
}

/** A block widget's height has to be known before layout, so the cards come from a field, as pictures do. */
function cardField(mode: Exclude<PlaceMode, 'off'>, dark: () => boolean) {
  return StateField.define<DecorationSet>({
    create: (state) => cardsOf(state, mode, dark()),
    update(value, tr) {
      if (tr.docChanged || tr.effects.some((effect) => effect.is(refreshPlaceCards))) return cardsOf(tr.state, mode, dark());
      return value;
    },
    provide: (field) => EditorView.decorations.from(field),
  });
}

/** A switch changed: the cards look again. */
const listen = ViewPlugin.fromClass(
  class {
    private readonly off: () => void;
    constructor(readonly view: EditorView) {
      this.off = onPreferences(() => this.view.dispatch({ effects: refreshPlaceCards.of(null) }));
    }
    destroy() {
      this.off();
    }
  },
);

/** The `[` and the `](geo:…)` of a place line, as ranges of the document. */
function foldsOf(from: number, text: string, words: string): { from: number; to: number }[] {
  const link = /\[([^[\]\n]*)\]\(geo:[^)\s]*\)/i.exec(text);
  if (!link || link[1]?.trim() !== words) return [];
  const open = from + link.index;
  const close = open + 1 + (link[1]?.length ?? 0);
  return [
    { from: open, to: open + 1 },
    { from: close, to: open + link[0].length },
  ];
}

const hidden = Decoration.replace({});

function foldAll(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const editable = view.state.facet(EditorView.editable);
  // The lines the selection touches show their places whole, while the note is being written (editor/links.ts).
  const active = editable && view.hasFocus ? selectedLines(view.state) : new Set<number>();
  const doc = view.state.doc;
  for (const { from, to } of view.visibleRanges) {
    for (let line = doc.lineAt(from); ; line = doc.line(line.number + 1)) {
      if (!active.has(line.number)) {
        const place = placeOfLine(line.text);
        // A place's line in fenced code is the code's words, as the cards take it: asked of a place's line alone.
        if (place && !inFence(doc, line.number)) for (const fold of foldsOf(line.from, line.text, place.words)) builder.add(fold.from, fold.to, hidden);
      }
      if (line.to >= to || line.number >= doc.lines) break;
    }
  }
  return builder.finish();
}

/** The place lines folded to their names off the caret, looked at again whenever what they show may have moved. */
const folds = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = foldAll(view);
    }
    update(update: ViewUpdate) {
      // While an IME composes, a line's DOM must not be replaced (editor/glyphLines.ts).
      if (update.view.composing) {
        if (update.docChanged) this.decorations = this.decorations.map(update.changes);
        return;
      }
      if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) this.decorations = foldAll(update.view);
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

const theme = EditorView.baseTheme({
  '.cm-placeCard': {
    // The card's chips in the app's own hand and size, as on the card at the top of the note, not the note's.
    fontFamily: 'var(--glacier-font-sans, system-ui)',
    fontSize: '1rem',
    lineHeight: '1.5',
    paddingBlock: '0.25em 0.6em',
    // Level with the words: a block widget sits outside the lines, which take the gutter as padding.
    paddingInline: 'calc(var(--app-safe-left, 0px) + var(--app-gutter, 0px)) calc(var(--app-safe-right, 0px) + var(--app-gutter, 0px))',
  },
  // The card's own height held while its component arrives, so nothing under it moves when it does.
  '.cm-placeCardBox': { minBlockSize: '6rem', maxInlineSize: '32rem' },
  '@media (min-width: 600px)': {
    '.cm-placeCardBox': { minBlockSize: '8rem' },
  },
});

/**
 * Places in the words: cards under their lines as `mode` says, and the lines folded to their names. Read once, when
 * the editor is made; `dark` is asked whenever the cards are drawn.
 */
export function placeCards(mode: PlaceMode, { dark }: { dark: () => boolean }): Extension {
  if (mode === 'off') return [folds];
  return [cardField(mode, dark), listen, folds, theme];
}

import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder, StateEffect, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import { prefersStill } from '../core/motion.ts';
import type { InlineFormat } from '../plugins/types.ts';
import { hiddenDefs, svgElement } from './svgFilters.ts';

/**
 * Effects on words: moving looks a mark can give the text between its delimiters (plugins/types.ts `FormatLook`
 * 'effect'), written as an emoji twice either side (Matt: "Effects should be shown by double emoji wrapping them so
 * heat should be two fire emoji's wrapping either side"). `🔥🔥too hot to touch🔥🔥` is heat, `❄️❄️frozen❄️❄️` frost,
 * `🌊🌊out to sea🌊🌊` a wave, `✨✨silver✨✨` a shimmer and `👻👻nobody there👻👻` a haunting.
 *
 * The words stay words, in their places, kerned and wrapped exactly as they would be without the effect, so the line
 * never moves when an effect comes or goes. The delimiters stay the dimmed marks every delimiter is (docs/DESIGN.md
 * §3.2), which is also what the note reads as anywhere else - two flames either side of some words.
 *
 * Unlike the spoiler's smoke (wispFormat.ts), an effect is meant to be read: it moves the letters, it does not hide
 * them. There are three kinds, by what the effect is:
 *
 * - **Heat rising off the words** (`RisingEffect`: heat). The words themselves are bold, in their own colour, and it
 *   is the text above them that wavers, seen through the hot air they give off (Matt: "The fire effect should be
 *   messing with the text above it with the heat waves the text itself should just have solid in the existing color
 *   but bold"), as the onboarding's flame bent the words it stood behind rather than itself. The words shimmer too,
 *   but only slightly, a fraction of the haze over the line above (Matt: "give a slight but not as intense heat effect
 *   to the text itself being heated"), so they still read as solid. Where the text above is is a question about the
 *   layout, not the document - a wrapped line, a wide heading, a proportional face - so it is measured after each draw
 *   (`textAbove`), and the haze follows on the next frame.
 * - **A filter over the whole stretch** (`FilterEffect`: frost), where the effect is one field the words sit in - a
 *   rime - and a letter-by-letter filter would be a dozen small frosts.
 * - **A movement passed along the letters** (`LetterEffect`: wave, shimmer, haunt), where each letter moves on its own
 *   clock a step behind the one before, so the movement travels along the words: a ripple, a glint, a fading. Each
 *   letter is an inline mark with a CSS animation, delayed by its place; inline, and moved by relative position rather
 *   than a transform (which an inline box does not take), so nothing round it reflows. The delays are negative - the
 *   same phases, started long ago - so a line drawn fresh is already moving rather than starting letter by letter.
 *
 * While the caret is in the words the effect lifts, so they can be edited as plain text, and it comes back when the
 * caret leaves; a view that cannot be edited never lifts it. With reduced motion an effect is drawn and does not move:
 * a filter at rest, a haunting half-there, a wave and a shimmer plain. Effects nest, so a haze can shimmer.
 *
 * A filter is sized to the type it is on (`FilterEffect.build` is given the font's size), because a displacement is in
 * pixels: a bend that reads as heat on body text would tear small print apart and barely touch a title. A letter
 * effect is in em, so it sizes itself. Adding an effect is an entry in `TEXT_EFFECTS` and a mark that names it
 * (plugins/marks/index.tsx).
 */

export interface RisingEffect {
  kind: 'rising';
  /**
   * Fills `filter` for the text above the words, for type `fontPx` high, at `strength` (1 for the line just above, less
   * for the one above that, where the heat has thinned), and for the words themselves at `own`. `still` is reduced
   * motion.
   */
  build(filter: SVGFilterElement, fontPx: number, still: boolean, strength: number): void;
  region: { x: number; y: number; width: number; height: number };
  /** The words' own look, as a CodeMirror theme spec for `.cm-effect-<name>`: heat's are bold. */
  theme: Parameters<typeof EditorView.baseTheme>[0];
  /** How strongly each line above is drawn through the haze, nearest first. */
  strengths: readonly number[];
  /** How strongly the words themselves waver: well under the line above, so they stay solid and bold to read. */
  own: number;
}

export interface FilterEffect {
  kind: 'filter';
  /**
   * Fills `filter` with its primitives, for type `fontPx` high. `still` is reduced motion: the effect is drawn as it
   * looks at rest and nothing in it animates.
   */
  build(filter: SVGFilterElement, fontPx: number, still: boolean): void;
  /** The room round the words the effect may draw into, as fractions of their box, so a bent letter is never clipped. */
  region: { x: number; y: number; width: number; height: number };
}

export interface LetterEffect {
  kind: 'letters';
  /** One turn of a letter's animation, in ms: the CSS in `theme` must run for this long. */
  cycleMs: number;
  /** How far behind the letter before it each letter runs, in ms. */
  stepMs: number;
  /** Its CSS, as a CodeMirror theme spec: the `.cm-effect-<name>` rule, its keyframes and its reduced-motion rule. */
  theme: Parameters<typeof EditorView.baseTheme>[0];
}

export type TextEffect = RisingEffect | FilterEffect | LetterEffect;

/** The type the filters are tuned on: a note's body text. */
const TUNED_PX = 16;

/** How much bigger than body text `fontPx` is, held above half so small print keeps a visible effect. */
const scaleFor = (fontPx: number) => Math.max(0.5, fontPx / TUNED_PX);

/**
 * Heat's haze, over the text above the heated words: it wobbles and softens as if seen through the air over a fire,
 * the haze the onboarding's "AI" burned behind (Matt: "the heated effect that gives the wavey blur like we used on the
 * "AI" text on with the fire on the original onboarding flow"). The same filter: fractal noise stretched tall (a lower
 * frequency across than down, so the bend runs in rising bands), breathing between two frequencies every 2.4 seconds
 * and re-rolled six times in 0.9 seconds, driving a displacement; then a breath of blur, the "blur" in the wavy blur.
 * `strength` scales the bend and the blur, so the line two above is a gentler haze than the line just above, and the
 * heated words themselves (`own`) a gentler one still.
 *
 * The onboarding's numbers (a 0.035 by 0.11 noise, a bend of 7) were for 40-pixel display type; carried to body text
 * as they were, or scaled straight down with it, the bend is a few pixels of grit on fine noise and reads as ragged
 * letters rather than hot air (measured by eye side by side, 2026-09-25: five variants at 16 px). These are the ones
 * that read as heat at 16 px - waves about four times a letter's height, a bend of a third of it - and everything
 * scales with the type it is on, so a heading's haze and a list item's look the same.
 */
function heat(filter: SVGFilterElement, fontPx: number, still: boolean, strength = 1): void {
  const k = scaleFor(fontPx);
  const low = `${(0.02 / k).toFixed(4)} ${(0.085 / k).toFixed(4)}`;
  const high = `${(0.028 / k).toFixed(4)} ${(0.12 / k).toFixed(4)}`;
  const moving = still
    ? []
    : [
        svgElement('animate', { attributeName: 'baseFrequency', values: `${low};${high};${low}`, dur: '2.4s', repeatCount: 'indefinite' }),
        svgElement('animate', { attributeName: 'seed', values: '7;8;9;10;11;12', dur: '0.9s', calcMode: 'discrete', repeatCount: 'indefinite' }),
      ];
  filter.append(
    svgElement('feTurbulence', { type: 'fractalNoise', baseFrequency: low, numOctaves: 2, seed: 7, result: 'noise' }, ...moving),
    svgElement('feDisplacementMap', { in: 'SourceGraphic', in2: 'noise', scale: (5.5 * k * strength).toFixed(2), xChannelSelector: 'R', yChannelSelector: 'G', result: 'bent' }),
    svgElement('feGaussianBlur', { in: 'bent', stdDeviation: (0.6 * k * strength).toFixed(2) }),
  );
}

/**
 * Frost: the letters cooled towards ice, and a grainy rime grown out of their edges that creeps over seven seconds,
 * holds, and draws back, its crystals re-rolled now and then. The rime is the letters' own shape thickened, kept only
 * where fine noise is bright enough (so it is specks, not an outline), flooded with ice and softened. Its colour is
 * set by the theme (`.cm-effectFrostIce` below): pale ice on the dark page, a deeper ice blue on paper, where pale ice
 * would be white on white. The cooling is a colour matrix, so it keeps whichever ink the page has - white goes to ice,
 * black to a deep blue-black.
 */
function frost(filter: SVGFilterElement, fontPx: number, still: boolean): void {
  const k = scaleFor(fontPx);
  const reach = 1.4 * k;
  const creep = still
    ? []
    : [svgElement('animate', { attributeName: 'radius', values: `${(0.5 * reach).toFixed(2)};${reach.toFixed(2)};${reach.toFixed(2)};${(0.5 * reach).toFixed(2)}`, keyTimes: '0;0.45;0.8;1', dur: '7s', repeatCount: 'indefinite' })];
  const reroll = still ? [] : [svgElement('animate', { attributeName: 'seed', values: '3;4;5;6', dur: '4.8s', calcMode: 'discrete', repeatCount: 'indefinite' })];
  filter.append(
    svgElement('feColorMatrix', { in: 'SourceGraphic', type: 'matrix', values: '0.82 0 0 0 0.02  0 0.92 0 0 0.04  0 0 1 0 0.1  0 0 0 1 0', result: 'cold' }),
    svgElement('feMorphology', { in: 'SourceAlpha', operator: 'dilate', radius: reach.toFixed(2), result: 'thick' }, ...creep),
    svgElement('feTurbulence', { type: 'fractalNoise', baseFrequency: (0.55 / k).toFixed(3), numOctaves: 2, seed: 3, result: 'grain' }, ...reroll),
    svgElement('feColorMatrix', { in: 'grain', type: 'matrix', values: '0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 5 -1.9', result: 'specks' }),
    svgElement('feComposite', { in: 'thick', in2: 'specks', operator: 'in', result: 'rimeShape' }),
    svgElement('feFlood', { class: 'cm-effectFrostIce', 'flood-color': '#b9e2ff', 'flood-opacity': 0.95, result: 'ice' }),
    svgElement('feComposite', { in: 'ice', in2: 'rimeShape', operator: 'in', result: 'rime' }),
    svgElement('feGaussianBlur', { in: 'rime', stdDeviation: (0.35 * k).toFixed(2), result: 'soft' }),
    svgElement('feMerge', {}, svgElement('feMergeNode', { in: 'soft' }), svgElement('feMergeNode', { in: 'cold' })),
  );
}

/** The CSS for moving letters, where reduced motion is asked for: none of it. */
const STILL = '@media (prefers-reduced-motion: reduce)';

/** The effects the editor can draw, by the name a mark's look gives. */
export const TEXT_EFFECTS = {
  heat: {
    kind: 'rising',
    build: heat,
    region: { x: -0.08, y: -0.45, width: 1.16, height: 1.9 },
    theme: { '.cm-effect-heat': { fontWeight: '700' } },
    strengths: [1, 0.55],
    own: 0.3,
  },
  frost: { kind: 'filter', build: frost, region: { x: -0.1, y: -0.5, width: 1.2, height: 2 } },
  /** Wave: the words bob along the line, a ripple passing through them from the first letter to the last. */
  wave: {
    kind: 'letters',
    cycleMs: 1600,
    stepMs: 70,
    theme: {
      '.cm-effect-wave': { position: 'relative', animation: 'glyph-effect-wave 1.6s ease-in-out infinite' },
      '@keyframes glyph-effect-wave': { '0%, 100%': { top: '0' }, '25%': { top: '-0.14em' }, '75%': { top: '0.1em' } },
      [STILL]: { '.cm-effect-wave': { animation: 'none' } },
    },
  },
  /**
   * Shimmer: a glint slides across the words every few seconds. On the dark page it is a glow round each letter as
   * it passes; on paper, where a glow of dark ink is a smudge, the letter goes pale for a moment instead, a sheen.
   */
  shimmer: {
    kind: 'letters',
    cycleMs: 3200,
    stepMs: 55,
    theme: {
      '&dark .cm-effect-shimmer': { animation: 'glyph-effect-glint 3.2s ease-in-out infinite' },
      '&light .cm-effect-shimmer': { animation: 'glyph-effect-sheen 3.2s ease-in-out infinite' },
      '@keyframes glyph-effect-glint': {
        '0%, 76%, 100%': { textShadow: 'none' },
        '85%': { textShadow: '0 0 0.28em currentColor, 0 0 0.6em color-mix(in srgb, currentColor 55%, transparent)' },
      },
      '@keyframes glyph-effect-sheen': {
        '0%, 76%, 100%': { color: 'inherit' },
        '85%': { color: 'color-mix(in srgb, currentColor 32%, var(--glacier-bg, #fbfaf7))' },
      },
      [STILL]: { '.cm-effect-shimmer': { animation: 'none !important' } },
    },
  },
  /** Haunt: the words fade almost away and back, slowly, the fading drifting along them like something passing. */
  haunt: {
    kind: 'letters',
    cycleMs: 4400,
    stepMs: 110,
    theme: {
      '.cm-effect-haunt': { animation: 'glyph-effect-haunt 4.4s ease-in-out infinite' },
      '@keyframes glyph-effect-haunt': { '0%, 100%': { opacity: '1', filter: 'none' }, '50%': { opacity: '0.3', filter: 'blur(0.05em)' } },
      [STILL]: { '.cm-effect-haunt': { animation: 'none', opacity: '0.55' } },
    },
  },
} satisfies Record<string, TextEffect>;

export type TextEffectName = keyof typeof TEXT_EFFECTS;

export interface EffectLook {
  /** The delimiter's length in code units: `🔥🔥` is four. */
  length: number;
  effect: TextEffectName;
}

export interface EffectRange {
  from: number;
  to: number;
  effect: TextEffectName;
}

/**
 * The stretches to draw an effect on in `range`: the words of every node in `looks`, delimiters aside, except a node
 * the selection touches while `atCaret`, which is an editable view with the focus. Nested effects are each a stretch,
 * outer first.
 */
export function effectRanges(state: EditorState, looks: ReadonlyMap<string, EffectLook>, range: { from: number; to: number }, atCaret: boolean): EffectRange[] {
  const found: EffectRange[] = [];
  syntaxTree(state).iterate({
    from: range.from,
    to: range.to,
    enter(node) {
      const look = looks.get(node.name);
      if (!look) return undefined;
      const from = node.from + look.length;
      const to = node.to - look.length;
      if (to <= from) return false;
      if (atCaret && state.selection.ranges.some((r) => r.to >= node.from && r.from <= node.to)) return false;
      found.push({ from, to, effect: look.effect });
      return undefined;
    },
  });
  return found;
}

export interface EffectLetter {
  from: number;
  to: number;
  /** The animation's delay: negative, and a step later for each letter, so the movement travels and is already under way. */
  delayMs: number;
}

/** The letters of a stretch for a letter effect, spaces aside, each a character whole however many code units it is. */
export function effectLetters(state: EditorState, stretch: { from: number; to: number }, effect: Pick<LetterEffect, 'cycleMs' | 'stepMs'>): EffectLetter[] {
  const letters: EffectLetter[] = [];
  let pos = stretch.from;
  let place = 0;
  for (const ch of state.doc.sliceString(stretch.from, stretch.to)) {
    if (!/\s/.test(ch)) {
      letters.push({ from: pos, to: pos + ch.length, delayMs: ((place * effect.stepMs) % effect.cycleMs) - effect.cycleMs });
      place += 1;
    }
    pos += ch.length;
  }
  return letters;
}

/** A stretch of words as laid out: one per visual line it runs over, in the view's own coordinates. */
export interface Segment {
  left: number;
  right: number;
  top: number;
}

/** What the view says about a point on the page, for `textAbove`: the text line there, or nothing. */
export type ProbeLine = (x: number, y: number) => { from: number; to: number; top: number; empty: boolean } | null;

/** How many visual lines up the text above may be found: the line just above, past one blank line between paragraphs. */
const SEARCH = 3;
/** How far either side of the words the heat reaches, in line heights. */
const SPREAD = 0.35;

/**
 * The text above one laid-out stretch of heated words: for each strength, nearest first, the document range under the
 * words' width (and a little either side) on a line of text above them. The first is the nearest line with any text,
 * looked for up to `SEARCH` lines up, so a blank line between paragraphs does not end the heat; each further one is the
 * line straight above the last, where the heat has thinned, and stops at a blank line. `probe` reads the layout: given
 * a point, the text under it as a range, the top of its visual line, and whether the line is blank there.
 */
export function textAbove(segment: Segment, lineHeight: number, strengths: readonly number[], probe: ProbeLine): { from: number; to: number; strength: number }[] {
  const found: { from: number; to: number; strength: number }[] = [];
  const spread = lineHeight * SPREAD;
  let top = segment.top;
  let searched = 0;
  for (const strength of strengths) {
    let hit: { from: number; to: number; top: number } | null = null;
    while (searched < SEARCH) {
      searched += 1;
      const y = top - lineHeight / 2;
      const start = probe(segment.left - spread, y);
      const end = probe(segment.right + spread, y);
      if (!start || !end) return found;
      top = Math.min(start.top, end.top);
      if (start.empty && end.empty) {
        // A blank line: the heat carries over it to the first text above, but no further past the first it reached.
        if (found.length) return found;
        continue;
      }
      hit = { from: Math.min(start.from, end.from), to: Math.max(start.to, end.to), top };
      break;
    }
    if (!hit || hit.to <= hit.from) return found;
    found.push({ from: hit.from, to: hit.to, strength });
    // The next line up is only ever the one straight above this one.
    searched = SEARCH - 1;
  }
  return found;
}

/** The stretch from `from` to `to` as laid out: one segment per visual line, read from the view's character boxes. */
function segmentsOf(view: EditorView, from: number, to: number): Segment[] {
  const segments: Segment[] = [];
  let current: Segment | null = null;
  // A long heated paragraph is measured by its first stretch only; heat off a whole page of words would be noise.
  const end = Math.min(to, from + 400);
  for (let pos = from; pos < end; ) {
    const code = view.state.doc.sliceString(pos, Math.min(pos + 2, end)).codePointAt(0) ?? 0;
    const next = pos + (code > 0xffff ? 2 : 1);
    const a = view.coordsAtPos(pos, 1);
    const b = view.coordsAtPos(next, -1);
    if (a && b) {
      if (current && Math.abs(a.top - current.top) < 2) current.right = Math.max(current.right, b.right);
      else {
        current = { left: a.left, right: b.right, top: a.top };
        segments.push(current);
      }
    }
    pos = next;
  }
  return segments;
}

/** The layout, as `textAbove` asks for it: the line under a point, as a range across the words' width. */
function probeOf(view: EditorView): ProbeLine {
  const box = view.contentDOM.getBoundingClientRect();
  return (x, y) => {
    if (y < box.top) return null;
    const pos = view.posAtCoords({ x: Math.min(Math.max(x, box.left + 1), box.right - 1), y }, false);
    const at = view.coordsAtPos(pos, 1) ?? view.coordsAtPos(pos, -1);
    if (!at) return null;
    const line = view.state.doc.lineAt(pos);
    return { from: pos, to: pos, top: at.top, empty: line.length === 0 || /^\s*$/.test(line.text) };
  };
}

/** Said to the plugin when the text above its heated words has been measured afresh and differs from what it drew. */
const heatMeasured = StateEffect.define<null>();

let instances = 0;

export function textEffects(formats: readonly InlineFormat[]): Extension {
  const looks = new Map<string, EffectLook>();
  for (const format of formats) {
    if (format.look.kind === 'effect' && format.look.effect in TEXT_EFFECTS) looks.set(format.name, { length: format.delimiter.length, effect: format.look.effect });
  }
  if (!looks.size) return [];
  const used = new Set([...looks.values()].map((look) => look.effect));
  const plugin = ViewPlugin.fromClass(
    class {
      decorations: DecorationSet = Decoration.none;
      private readonly svg: SVGSVGElement;
      private readonly defs: SVGDefsElement;
      private readonly prefix: string;
      /** The size the filters were last built for, so they are rebuilt only when the type changes size. */
      private builtFor = 0;
      private readonly filters = new Map<TextEffectName, Decoration>();
      /** A rising effect's haze over the text above, one mark per strength (`${name}:${strength}`). */
      private readonly hazes = new Map<string, Decoration>();
      /** A rising effect's words: their own look, and their own slight waver. */
      private readonly wordMarks = new Map<TextEffectName, Decoration>();
      /** The text above heated words, as last measured: drawn through the haze on the next draw. */
      private above: { from: number; to: number; effect: TextEffectName; strength: number }[] = [];
      private destroyed = false;
      /** A letter effect's marks, one per delay, made once. */
      private readonly letters = new Map<string, Decoration>();

      constructor(readonly view: EditorView) {
        instances += 1;
        this.prefix = `glyph-effect-${instances}`;
        ({ svg: this.svg, defs: this.defs } = hiddenDefs(view.dom));
        this.redraw();
      }

      update(update: ViewUpdate) {
        const measured = update.transactions.some((tr) => tr.effects.some((effect) => effect.is(heatMeasured)));
        if (update.docChanged) this.above = [];
        if (measured || update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged || update.geometryChanged || syntaxTree(update.state) !== syntaxTree(update.startState)) {
          this.redraw();
        }
      }

      destroy() {
        this.destroyed = true;
        this.svg.remove();
      }

      /** Each filter effect's filter, built for the type the note is set in. */
      private build(fontPx: number) {
        if (fontPx === this.builtFor) return;
        this.builtFor = fontPx;
        this.defs.replaceChildren();
        const still = prefersStill();
        /** A filter in the view's defs, over `region` and filled by `fill`: its id, for a mark's style to name. */
        const addFilter = (id: string, region: RisingEffect['region'], fill: (filter: SVGFilterElement) => void): string => {
          const filter = svgElement('filter', {
            id,
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height,
            'color-interpolation-filters': 'sRGB',
          }) as SVGFilterElement;
          fill(filter);
          this.defs.appendChild(filter);
          return id;
        };
        for (const name of used) {
          const effect: TextEffect = TEXT_EFFECTS[name];
          if (effect.kind === 'rising') {
            const own = addFilter(`${this.prefix}-${name}-own`, effect.region, (filter) => effect.build(filter, fontPx, still, effect.own));
            this.wordMarks.set(name, Decoration.mark({ class: `cm-textEffect cm-effect-${name}`, attributes: { 'data-effect': name, style: `filter:url(#${own})` } }));
            for (const strength of effect.strengths) {
              const id = addFilter(`${this.prefix}-${name}-above-${Math.round(strength * 100)}`, effect.region, (filter) => effect.build(filter, fontPx, still, strength));
              this.hazes.set(`${name}:${strength}`, Decoration.mark({ class: 'cm-textEffectAbove', attributes: { 'data-effect': `${name}-above`, style: `filter:url(#${id})` } }));
            }
            continue;
          }
          if (effect.kind !== 'filter') continue;
          const id = addFilter(`${this.prefix}-${name}`, effect.region, (filter) => effect.build(filter, fontPx, still));
          this.filters.set(name, Decoration.mark({ class: 'cm-textEffect', attributes: { 'data-effect': name, style: `filter:url(#${id})` } }));
        }
      }

      private letterMark(name: TextEffectName, delayMs: number): Decoration {
        const key = `${name}:${delayMs}`;
        let mark = this.letters.get(key);
        if (!mark) {
          mark = Decoration.mark({ class: `cm-textEffect cm-effect-${name}`, attributes: { 'data-effect': name, style: `animation-delay:${delayMs}ms` } });
          this.letters.set(key, mark);
        }
        return mark;
      }

      private redraw() {
        const { view } = this;
        const size = Number.parseFloat(getComputedStyle(view.contentDOM).fontSize);
        this.build(Number.isFinite(size) && size > 0 ? size : TUNED_PX);
        const first = view.visibleRanges[0];
        const last = view.visibleRanges[view.visibleRanges.length - 1];
        const atCaret = view.state.facet(EditorView.editable) && view.hasFocus;
        const found = first && last ? effectRanges(view.state, looks, { from: first.from, to: last.to }, atCaret) : [];
        const marks: { from: number; to: number; mark: Decoration }[] = [];
        const rising: EffectRange[] = [];
        for (const stretch of found) {
          const effect: TextEffect = TEXT_EFFECTS[stretch.effect];
          if (effect.kind === 'rising') {
            const mark = this.wordMarks.get(stretch.effect);
            if (mark) marks.push({ from: stretch.from, to: stretch.to, mark });
            rising.push(stretch);
          } else if (effect.kind === 'filter') {
            const mark = this.filters.get(stretch.effect);
            if (mark) marks.push({ from: stretch.from, to: stretch.to, mark });
          } else {
            for (const letter of effectLetters(view.state, stretch, effect)) marks.push({ from: letter.from, to: letter.to, mark: this.letterMark(stretch.effect, letter.delayMs) });
          }
        }
        // The haze over the text above heated words, as last measured, where it is still text outside the heat itself.
        const heated = rising.map((r) => [r.from, r.to] as const);
        for (const above of this.above) {
          if (above.to > view.state.doc.length || heated.some(([from, to]) => above.from < to && above.to > from)) continue;
          const mark = this.hazes.get(`${above.effect}:${above.strength}`);
          if (mark) marks.push({ from: above.from, to: above.to, mark });
        }
        // Nested effects give marks out of order (the outer stretch, then the inner one's letters); the builder wants them sorted.
        marks.sort((a, b) => a.from - b.from || b.to - a.to);
        const builder = new RangeSetBuilder<Decoration>();
        for (const { from, to, mark } of marks) builder.add(from, to, mark);
        this.decorations = builder.finish();
        this.measureAbove(rising);
      }

      /**
       * Where the text above the heated words is, read once the view is laid out, and drawn on the next update when it
       * has moved. A haze changes no layout, so this settles after one round: the second measure finds what the first
       * did and dispatches nothing.
       */
      private measureAbove(rising: readonly EffectRange[]) {
        this.view.requestMeasure({
          key: this,
          read: (view) => {
            const lineHeight = view.defaultLineHeight;
            const probe = probeOf(view);
            return rising.flatMap((stretch) => {
              const effect: TextEffect = TEXT_EFFECTS[stretch.effect];
              if (effect.kind !== 'rising') return [];
              return segmentsOf(view, stretch.from, stretch.to).flatMap((segment) =>
                textAbove(segment, lineHeight, effect.strengths, probe).map((above) => ({ ...above, effect: stretch.effect })),
              );
            });
          },
          write: (next, view) => {
            const same = next.length === this.above.length && next.every((a, i) => a.from === this.above[i]!.from && a.to === this.above[i]!.to && a.strength === this.above[i]!.strength);
            if (same) return;
            this.above = next;
            // Not from inside the measure: a transaction then is refused, so it goes on the next turn.
            window.setTimeout(() => {
              if (!this.destroyed) view.dispatch({ effects: heatMeasured.of(null) });
            }, 0);
          },
        });
      }
    },
    { decorations: (plugin) => plugin.decorations },
  );
  // Plain inline spans for the filters, so the words wrap and kern as they would with no effect on them; the letter
  // effects' own CSS; and the frost's ice, a colour for each page.
  const letterThemes = [...used].flatMap((name) => {
    const effect: TextEffect = TEXT_EFFECTS[name];
    return effect.kind === 'letters' || effect.kind === 'rising' ? [EditorView.baseTheme(effect.theme)] : [];
  });
  const theme = EditorView.baseTheme({
    '.cm-textEffect': {},
    '.cm-textEffectAbove': {},
    '&dark .cm-effectFrostIce': { floodColor: '#cdeaff' },
    '&light .cm-effectFrostIce': { floodColor: '#5aa6da' },
  });
  return [plugin, theme, ...letterThemes];
}

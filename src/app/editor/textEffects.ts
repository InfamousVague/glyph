import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import type { InlineFormat } from '../plugins/types.ts';

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
 * them. There are two kinds, by what the effect is:
 *
 * - **A filter over the whole stretch** (`FilterEffect`: heat, frost), where the effect is one field the words sit in -
 *   hot air, a rime - and a letter-by-letter filter would be twelve small fires.
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

export type TextEffect = FilterEffect | LetterEffect;

const SVG_NS = 'http://www.w3.org/2000/svg';

function element(name: string, attributes: Record<string, string | number>, ...children: Element[]): Element {
  const node = document.createElementNS(SVG_NS, name);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, String(value));
  node.append(...children);
  return node;
}

/** The type the filters are tuned on: a note's body text. */
const TUNED_PX = 16;

/** How much bigger than body text `fontPx` is, held above half so small print keeps a visible effect. */
const scaleFor = (fontPx: number) => Math.max(0.5, fontPx / TUNED_PX);

/**
 * Heat: the letters wobble and soften as if seen through the air over a fire, the haze the onboarding's "AI" burned
 * behind (Matt: "the heated effect that gives the wavey blur like we used on the "AI" text on with the fire on the
 * original onboarding flow"). The same filter: fractal noise stretched tall (a lower frequency across than down, so
 * the bend runs in rising bands), breathing between two frequencies every 2.4 seconds and re-rolled six times in 0.9
 * seconds, driving a displacement of the words; then a breath of blur, which is the "blur" in the wavy blur.
 *
 * The onboarding's numbers (a 0.035 by 0.11 noise, a bend of 7) were for 40-pixel display type; carried to body text
 * as they were, or scaled straight down with it, the bend is a few pixels of grit on fine noise and reads as ragged
 * letters rather than hot air (measured by eye side by side, 2026-09-25: five variants at 16 px). These are the ones
 * that read as heat at 16 px - waves about four times a letter's height, a bend of a third of it - and everything
 * scales with the type it is on, so a heading's haze and a list item's look the same.
 */
function heat(filter: SVGFilterElement, fontPx: number, still: boolean): void {
  const k = scaleFor(fontPx);
  const low = `${(0.02 / k).toFixed(4)} ${(0.085 / k).toFixed(4)}`;
  const high = `${(0.028 / k).toFixed(4)} ${(0.12 / k).toFixed(4)}`;
  const moving = still
    ? []
    : [
        element('animate', { attributeName: 'baseFrequency', values: `${low};${high};${low}`, dur: '2.4s', repeatCount: 'indefinite' }),
        element('animate', { attributeName: 'seed', values: '7;8;9;10;11;12', dur: '0.9s', calcMode: 'discrete', repeatCount: 'indefinite' }),
      ];
  filter.append(
    element('feTurbulence', { type: 'fractalNoise', baseFrequency: low, numOctaves: 2, seed: 7, result: 'noise' }, ...moving),
    element('feDisplacementMap', { in: 'SourceGraphic', in2: 'noise', scale: (5.5 * k).toFixed(2), xChannelSelector: 'R', yChannelSelector: 'G', result: 'bent' }),
    element('feGaussianBlur', { in: 'bent', stdDeviation: (0.6 * k).toFixed(2) }),
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
    : [element('animate', { attributeName: 'radius', values: `${(0.5 * reach).toFixed(2)};${reach.toFixed(2)};${reach.toFixed(2)};${(0.5 * reach).toFixed(2)}`, keyTimes: '0;0.45;0.8;1', dur: '7s', repeatCount: 'indefinite' })];
  const reroll = still ? [] : [element('animate', { attributeName: 'seed', values: '3;4;5;6', dur: '4.8s', calcMode: 'discrete', repeatCount: 'indefinite' })];
  filter.append(
    element('feColorMatrix', { in: 'SourceGraphic', type: 'matrix', values: '0.82 0 0 0 0.02  0 0.92 0 0 0.04  0 0 1 0 0.1  0 0 0 1 0', result: 'cold' }),
    element('feMorphology', { in: 'SourceAlpha', operator: 'dilate', radius: reach.toFixed(2), result: 'thick' }, ...creep),
    element('feTurbulence', { type: 'fractalNoise', baseFrequency: (0.55 / k).toFixed(3), numOctaves: 2, seed: 3, result: 'grain' }, ...reroll),
    element('feColorMatrix', { in: 'grain', type: 'matrix', values: '0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 5 -1.9', result: 'specks' }),
    element('feComposite', { in: 'thick', in2: 'specks', operator: 'in', result: 'rimeShape' }),
    element('feFlood', { class: 'cm-effectFrostIce', 'flood-color': '#b9e2ff', 'flood-opacity': 0.95, result: 'ice' }),
    element('feComposite', { in: 'ice', in2: 'rimeShape', operator: 'in', result: 'rime' }),
    element('feGaussianBlur', { in: 'rime', stdDeviation: (0.35 * k).toFixed(2), result: 'soft' }),
    element('feMerge', {}, element('feMergeNode', { in: 'soft' }), element('feMergeNode', { in: 'cold' })),
  );
}

/** The CSS for moving letters, where reduced motion is asked for: none of it. */
const STILL = '@media (prefers-reduced-motion: reduce)';

/** The effects the editor can draw, by the name a mark's look gives. */
export const TEXT_EFFECTS = {
  heat: { kind: 'filter', build: heat, region: { x: -0.08, y: -0.45, width: 1.16, height: 1.9 } },
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

const prefersStill = () => typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;

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
      /** A letter effect's marks, one per delay, made once. */
      private readonly letters = new Map<string, Decoration>();

      constructor(readonly view: EditorView) {
        instances += 1;
        this.prefix = `glyph-effect-${instances}`;
        this.svg = document.createElementNS(SVG_NS, 'svg');
        this.svg.setAttribute('aria-hidden', 'true');
        this.svg.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
        this.defs = document.createElementNS(SVG_NS, 'defs');
        this.svg.appendChild(this.defs);
        view.dom.appendChild(this.svg);
        this.redraw();
      }

      update(update: ViewUpdate) {
        if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged || update.geometryChanged || syntaxTree(update.state) !== syntaxTree(update.startState)) {
          this.redraw();
        }
      }

      destroy() {
        this.svg.remove();
      }

      /** Each filter effect's filter, built for the type the note is set in. */
      private build(fontPx: number) {
        if (fontPx === this.builtFor) return;
        this.builtFor = fontPx;
        this.defs.replaceChildren();
        const still = prefersStill();
        for (const name of used) {
          const effect: TextEffect = TEXT_EFFECTS[name];
          if (effect.kind !== 'filter') continue;
          const id = `${this.prefix}-${name}`;
          const filter = element('filter', {
            id,
            x: effect.region.x,
            y: effect.region.y,
            width: effect.region.width,
            height: effect.region.height,
            'color-interpolation-filters': 'sRGB',
          }) as SVGFilterElement;
          effect.build(filter, fontPx, still);
          this.defs.appendChild(filter);
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
        for (const stretch of found) {
          const effect: TextEffect = TEXT_EFFECTS[stretch.effect];
          if (effect.kind === 'filter') {
            const mark = this.filters.get(stretch.effect);
            if (mark) marks.push({ from: stretch.from, to: stretch.to, mark });
          } else {
            for (const letter of effectLetters(view.state, stretch, effect)) marks.push({ from: letter.from, to: letter.to, mark: this.letterMark(stretch.effect, letter.delayMs) });
          }
        }
        // Nested effects give marks out of order (the outer stretch, then the inner one's letters); the builder wants them sorted.
        marks.sort((a, b) => a.from - b.from || b.to - a.to);
        const builder = new RangeSetBuilder<Decoration>();
        for (const { from, to, mark } of marks) builder.add(from, to, mark);
        this.decorations = builder.finish();
      }
    },
    { decorations: (plugin) => plugin.decorations },
  );
  // Plain inline spans for the filters, so the words wrap and kern as they would with no effect on them; the letter
  // effects' own CSS; and the frost's ice, a colour for each page.
  const letterThemes = [...used].flatMap((name) => {
    const effect: TextEffect = TEXT_EFFECTS[name];
    return effect.kind === 'letters' ? [EditorView.baseTheme(effect.theme)] : [];
  });
  const theme = EditorView.baseTheme({
    '.cm-textEffect': {},
    '&dark .cm-effectFrostIce': { floodColor: '#cdeaff' },
    '&light .cm-effectFrostIce': { floodColor: '#5aa6da' },
  });
  return [plugin, theme, ...letterThemes];
}

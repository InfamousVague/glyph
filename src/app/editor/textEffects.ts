import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate } from '@codemirror/view';
import type { InlineFormat } from '../plugins/types.ts';

/**
 * Effects on words: moving looks a mark can give the text between its delimiters (plugins/types.ts `FormatLook`
 * 'effect'), written as an emoji twice either side (Matt: "Effects should be shown by double emoji wrapping them so
 * heat should be two fire emoji's wrapping either side"). `🔥🔥too hot to touch🔥🔥` is heat.
 *
 * An effect is an SVG filter over the words, and nothing else: the words stay words, in their places, kerned and
 * wrapped exactly as they would be without it, so the line never moves when an effect comes or goes. The delimiters
 * stay the dimmed marks every delimiter is (docs/DESIGN.md §3.2), which is also what the note reads as anywhere else -
 * two flames either side of some words.
 *
 * Unlike the spoiler's smoke (wispFormat.ts), an effect is meant to be read: it moves the letters, it does not hide
 * them. So the filter is one for the whole stretch, where smoke is a pool of filters round the letters: a heat haze is
 * one field of hot air the words sit behind, and a letter-by-letter one would be twelve small fires. While the caret is
 * in the words the effect lifts, so they can be edited as plain text, and it comes back when the caret leaves; a view
 * that cannot be edited never lifts it. With reduced motion an effect is drawn, and does not move.
 *
 * Each effect is sized to the type it is on (`TextEffect.build` is given the font's size), because a displacement is
 * in pixels: a bend that reads as heat on body text would tear small print apart and barely touch a title.
 * Adding an effect is an entry in `TEXT_EFFECTS` and a mark that names it (plugins/marks/index.tsx).
 */

export interface TextEffect {
  /**
   * Fills `filter` with its primitives, for type `fontPx` high. `still` is reduced motion: the effect is drawn as it
   * looks at rest and nothing in it animates.
   */
  build(filter: SVGFilterElement, fontPx: number, still: boolean): void;
  /** The room round the words the effect may draw into, as fractions of their box, so a bent letter is never clipped. */
  region: { x: number; y: number; width: number; height: number };
}

const SVG_NS = 'http://www.w3.org/2000/svg';

function element(name: string, attributes: Record<string, string | number>, ...children: Element[]): Element {
  const node = document.createElementNS(SVG_NS, name);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, String(value));
  node.append(...children);
  return node;
}

/** The type the haze is tuned on: a note's body text. */
const HEAT_TUNED_PX = 16;

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
  const k = Math.max(0.5, fontPx / HEAT_TUNED_PX);
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

/** The effects the editor can draw, by the name a mark's look gives. */
export const TEXT_EFFECTS = {
  heat: { build: heat, region: { x: -0.08, y: -0.45, width: 1.16, height: 1.9 } },
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
 * the selection touches while `atCaret`, which is an editable view with the focus.
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
      return false;
    },
  });
  return found;
}

const prefersStill = () => typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;

let instances = 0;

export function textEffects(formats: readonly InlineFormat[]): Extension {
  const looks = new Map<string, EffectLook>();
  for (const format of formats) {
    if (format.look.kind === 'effect' && format.look.effect in TEXT_EFFECTS) looks.set(format.name, { length: format.delimiter.length, effect: format.look.effect });
  }
  if (!looks.size) return [];
  const plugin = ViewPlugin.fromClass(
    class {
      decorations: DecorationSet = Decoration.none;
      private readonly svg: SVGSVGElement;
      private readonly defs: SVGDefsElement;
      private readonly prefix: string;
      /** The size the filters were last built for, so they are rebuilt only when the type changes size. */
      private builtFor = 0;
      private readonly marks = new Map<TextEffectName, Decoration>();

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

      /** Each effect's filter, built for the type the note is set in. */
      private build(fontPx: number) {
        if (fontPx === this.builtFor) return;
        this.builtFor = fontPx;
        this.defs.replaceChildren();
        const still = prefersStill();
        for (const name of new Set([...looks.values()].map((look) => look.effect))) {
          const effect: TextEffect = TEXT_EFFECTS[name];
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
          this.marks.set(name, Decoration.mark({ class: 'cm-textEffect', attributes: { 'data-effect': name, style: `filter:url(#${id})` } }));
        }
      }

      private redraw() {
        const { view } = this;
        const size = Number.parseFloat(getComputedStyle(view.contentDOM).fontSize);
        this.build(Number.isFinite(size) && size > 0 ? size : 17);
        const first = view.visibleRanges[0];
        const last = view.visibleRanges[view.visibleRanges.length - 1];
        const atCaret = view.state.facet(EditorView.editable) && view.hasFocus;
        const found = first && last ? effectRanges(view.state, looks, { from: first.from, to: last.to }, atCaret) : [];
        const builder = new RangeSetBuilder<Decoration>();
        for (const range of found) builder.add(range.from, range.to, this.marks.get(range.effect)!);
        this.decorations = builder.finish();
      }
    },
    { decorations: (plugin) => plugin.decorations },
  );
  // Plain inline spans, so the words wrap and kern as they would with no effect on them.
  const theme = EditorView.baseTheme({ '.cm-textEffect': {} });
  return [plugin, theme];
}

import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import { glyphMarkdown } from './language.ts';
import { effectLetters, effectRanges, TEXT_EFFECTS, textAbove, textEffects, type ProbeLine } from './textEffects.ts';
import type { InlineFormat } from '../plugins/types.ts';

const heat: InlineFormat = { name: 'Heat', delimiter: '🔥🔥', look: { kind: 'effect', effect: 'heat' } };
const wave: InlineFormat = { name: 'Wave', delimiter: '🌊🌊', look: { kind: 'effect', effect: 'wave' } };
const shimmer: InlineFormat = { name: 'Shimmer', delimiter: '✨✨', look: { kind: 'effect', effect: 'shimmer' } };
const looks = new Map([
  ['Heat', { length: '🔥🔥'.length, effect: 'heat' as const }],
  ['Shimmer', { length: '✨✨'.length, effect: 'shimmer' as const }],
]);

function state(doc: string, selection = 0) {
  return EditorState.create({ doc, extensions: [glyphMarkdown([heat, wave, shimmer])], selection: { anchor: selection } });
}

const words = (s: EditorState, atCaret: boolean) => effectRanges(s, looks, { from: 0, to: s.doc.length }, atCaret).map((r) => s.doc.sliceString(r.from, r.to));

describe('effects on words', () => {
  it('draws the words between the flames, and neither flame', () => {
    const s = state('It was 🔥🔥too hot to touch🔥🔥 all day, and 🔥🔥again🔥🔥.');
    expect(words(s, false)).toEqual(['too hot to touch', 'again']);
    expect(effectRanges(s, looks, { from: 0, to: s.doc.length }, false).every((r) => r.effect === 'heat')).toBe(true);
  });

  it('lifts while the caret is in the words, in a view that can be edited, and only then', () => {
    const doc = 'a 🔥🔥hot🔥🔥 and 🔥🔥warm🔥🔥';
    const inside = state(doc, doc.indexOf('hot') + 1);
    expect(words(inside, true)).toEqual(['warm']);
    // A view that cannot be edited never lifts it.
    expect(words(inside, false)).toEqual(['hot', 'warm']);
    // On a flame counts as in it, so the caret beside a mark shows the plain words to edit.
    expect(words(state(doc, doc.indexOf('🔥🔥hot')), true)).toEqual(['warm']);
  });

  it('draws nothing where a mark has no words, or no mark names an effect', () => {
    expect(words(state('🔥🔥🔥🔥'), false)).toEqual([]);
    expect(effectRanges(state('🔥🔥hot🔥🔥'), new Map(), { from: 0, to: 11 }, false)).toEqual([]);
    expect(textEffects([{ name: 'Shout', delimiter: '^^', look: { kind: 'style', css: '' } }])).toEqual([]);
  });

  it('draws an effect inside another, each its own stretch, the outer first', () => {
    const s = state('a 🔥🔥hot ✨✨and bright✨✨ day🔥🔥');
    expect(effectRanges(s, looks, { from: 0, to: s.doc.length }, false).map((r) => [r.effect, s.doc.sliceString(r.from, r.to)])).toEqual([
      ['heat', 'hot ✨✨and bright✨✨ day'],
      ['shimmer', 'and bright'],
    ]);
  });

  it('passes a letter effect along the letters: spaces aside, each a step behind, already under way', () => {
    const s = state('go 🌊🌊a b🙂🌊🌊');
    const from = s.doc.toString().indexOf('a b');
    const letters = effectLetters(s, { from, to: from + 'a b🙂'.length }, { cycleMs: 1000, stepMs: 300 });
    expect(letters.map((l) => s.doc.sliceString(l.from, l.to))).toEqual(['a', 'b', '🙂']);
    // Each a step behind the one before, wrapped round the cycle, and negative, so none waits to start.
    expect(letters.map((l) => l.delayMs)).toEqual([-1000, -700, -400]);
    const many = effectLetters(state('abcdefgh'), { from: 0, to: 8 }, { cycleMs: 1000, stepMs: 300 });
    expect(many.every((l) => l.delayMs < 0 && l.delayMs >= -1000)).toBe(true);
  });

  it('builds heat for the type it is on, the same haze at any size, and still under reduced motion', () => {
    const at = (px: number, still = false) => {
      const filter = document.createElementNS('http://www.w3.org/2000/svg', 'filter');
      TEXT_EFFECTS.heat.build(filter, px, still);
      return filter;
    };
    const body = at(16);
    expect(body.querySelector('feTurbulence')?.getAttribute('baseFrequency')).toBe('0.0200 0.0850');
    expect(body.querySelector('feDisplacementMap')?.getAttribute('scale')).toBe('5.50');
    expect(body.querySelector('feGaussianBlur')?.getAttribute('stdDeviation')).toBe('0.60');
    expect(body.querySelectorAll('animate')).toHaveLength(2);
    // Twice the type: twice the bend and blur, and waves half as fine, so it looks the same.
    const heading = at(32);
    expect(heading.querySelector('feDisplacementMap')?.getAttribute('scale')).toBe('11.00');
    expect(heading.querySelector('feTurbulence')?.getAttribute('baseFrequency')).toBe('0.0100 0.0425');
    expect(at(16, true).querySelectorAll('animate')).toHaveLength(0);
  });

  it('builds frost as a rime grown from the letters and coloured by the page, at rest under reduced motion', () => {
    const filter = document.createElementNS('http://www.w3.org/2000/svg', 'filter');
    TEXT_EFFECTS.frost.build(filter, 16, false);
    expect(filter.querySelector('feMorphology')?.getAttribute('operator')).toBe('dilate');
    expect(filter.querySelector('feFlood')?.getAttribute('class')).toBe('cm-effectFrostIce');
    expect(filter.querySelectorAll('animate')).toHaveLength(2);
    const still = document.createElementNS('http://www.w3.org/2000/svg', 'filter');
    TEXT_EFFECTS.frost.build(still, 16, true);
    expect(still.querySelectorAll('animate')).toHaveLength(0);
  });

  it('gives every letter effect a cycle its CSS runs for, a step, and a still rule for reduced motion', () => {
    for (const [name, effect] of Object.entries(TEXT_EFFECTS)) {
      if (effect.kind !== 'letters') continue;
      const css = JSON.stringify(effect.theme);
      expect(css, name).toContain(`${effect.cycleMs / 1000}s`);
      expect(css, name).toContain('prefers-reduced-motion');
      expect(effect.stepMs, name).toBeGreaterThan(0);
    }
  });
});

describe('the text above heated words', () => {
  /** A page of lines 20 px apart, each with its text as a range and blank or not: a stand-in for the layout. */
  const page = (lines: { from: number; to: number; empty?: boolean }[]): ProbeLine => (x, y) => {
    const index = Math.floor(y / 20);
    const line = lines[index];
    if (!line || y < 0) return null;
    // Across the line's width in characters of 10 px, from its start; past its end is its end.
    const pos = Math.min(line.to, line.from + Math.max(0, Math.floor(x / 10)));
    return { from: pos, to: pos, top: index * 20, empty: line.empty ?? false };
  };
  const strengths = [1, 0.5];

  it('is the line just above, under the words and a little either side, then the one above that, weaker', () => {
    const probe = page([{ from: 0, to: 40 }, { from: 41, to: 81 }, { from: 82, to: 122 }]);
    // Words on the third line, from 100 px to 160 px.
    const above = textAbove({ left: 100, right: 160, top: 40 }, 20, strengths, probe);
    expect(above).toEqual([
      { from: 41 + 9, to: 41 + 16, strength: 1 },
      { from: 0 + 9, to: 0 + 16, strength: 0.5 },
    ]);
  });

  it('carries over one blank line between paragraphs to the text above it, and no further', () => {
    const probe = page([{ from: 0, to: 30 }, { from: 31, to: 31, empty: true }, { from: 32, to: 60 }]);
    expect(textAbove({ left: 0, right: 50, top: 40 }, 20, strengths, probe).map((a) => a.strength)).toEqual([1]);
    // The weaker line stops at a blank line rather than jumping it.
    const gap = page([{ from: 0, to: 30 }, { from: 31, to: 31, empty: true }, { from: 32, to: 60 }, { from: 61, to: 90 }]);
    expect(textAbove({ left: 0, right: 50, top: 60 }, 20, strengths, gap)).toEqual([{ from: 32, to: 37, strength: 1 }]);
  });

  it('is nothing on the first line, or above a line too short to reach the words', () => {
    expect(textAbove({ left: 0, right: 50, top: 0 }, 20, strengths, page([{ from: 0, to: 30 }]))).toEqual([]);
    const short = page([{ from: 0, to: 3 }, { from: 4, to: 60 }]);
    expect(textAbove({ left: 200, right: 300, top: 20 }, 20, strengths, short)).toEqual([]);
  });
});

describe('the effects in an editor', () => {
  let view: EditorView | null = null;
  afterEach(() => {
    view?.destroy();
    view = null;
  });

  it('marks heated words bold and unfiltered, and hangs the haze for the lines above off the view', () => {
    const parent = document.createElement('div');
    document.body.append(parent);
    view = new EditorView({ parent, state: EditorState.create({ doc: 'so 🔥🔥hot🔥🔥 today', extensions: [glyphMarkdown([heat]), textEffects([heat])] }) });
    const marked = view.contentDOM.querySelector<HTMLElement>('.cm-textEffect');
    expect(marked?.textContent).toBe('hot');
    expect(marked?.dataset.effect).toBe('heat');
    expect(marked?.classList.contains('cm-effect-heat')).toBe(true);
    // The words carry no filter of their own: it is the text above them that is drawn through the haze.
    expect(marked?.getAttribute('style') ?? '').not.toContain('filter');
    // One haze per line above, nearest the strongest; jsdom drops a filter from a style, so they are found by id.
    expect(view.dom.querySelector('filter[id$="-heat-above-100"] feDisplacementMap')?.getAttribute('scale')).toBe('5.50');
    expect(view.dom.querySelector('filter[id$="-heat-above-55"] feDisplacementMap')?.getAttribute('scale')).toBe('3.03');
    view.destroy();
    view = null;
    expect(parent.querySelector('svg')).toBeNull();
    parent.remove();
  });

  it('marks each letter of a letter effect with its class and its delay', () => {
    const parent = document.createElement('div');
    document.body.append(parent);
    view = new EditorView({ parent, state: EditorState.create({ doc: 'we 🌊🌊sail on🌊🌊', extensions: [glyphMarkdown([wave]), textEffects([wave])] }) });
    const letters = [...view.contentDOM.querySelectorAll<HTMLElement>('.cm-effect-wave')];
    expect(letters.map((l) => l.textContent)).toEqual(['s', 'a', 'i', 'l', 'o', 'n']);
    expect(letters.every((l) => /animation-delay:\s*-\d+ms/.test(l.getAttribute('style') ?? ''))).toBe(true);
    parent.remove();
  });
});

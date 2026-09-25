import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { afterEach, describe, expect, it } from 'vitest';
import { glyphMarkdown } from './language.ts';
import { effectLetters, effectRanges, TEXT_EFFECTS, textEffects } from './textEffects.ts';
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

describe('the effects in an editor', () => {
  let view: EditorView | null = null;
  afterEach(() => {
    view?.destroy();
    view = null;
  });

  it('marks the words with the effect and hangs its filter off the view', () => {
    const parent = document.createElement('div');
    document.body.append(parent);
    view = new EditorView({ parent, state: EditorState.create({ doc: 'so 🔥🔥hot🔥🔥 today', extensions: [glyphMarkdown([heat]), textEffects([heat])] }) });
    const marked = view.contentDOM.querySelector<HTMLElement>('.cm-textEffect');
    expect(marked?.textContent).toBe('hot');
    expect(marked?.dataset.effect).toBe('heat');
    // jsdom drops a filter it cannot draw from the style, so the filter is found by its id, which the style names.
    expect(view.dom.querySelector('filter[id^="glyph-effect-"][id$="-heat"] feDisplacementMap')).toBeTruthy();
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

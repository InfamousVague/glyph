import { describe, expect, it, vi } from 'vitest';
import { rerender, show } from '../../test/render.tsx';

// The kit's icons reach matchMedia as the kit loads; jsdom has none.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

const { HotPhone } = await import('./HotPhone.tsx');

/**
 * The phone drawn: its pins are the cores and light by the busy figure, its rings wear their number, the column is
 * there, the mark is the step's, the case is the faint ink, and nothing but attributes changes as it warms and glows.
 */

const phone = (over: Partial<Parameters<typeof HotPhone>[0]> = {}) => <HotPhone warmth="cold" glowStep={0} litPins={0} pins={8} step="listen" still={false} {...over} />;

describe('the phone', () => {
  it('has a pin a core, lit by the busy figure, top and bottom in turn', () => {
    const el = show(phone({ pins: 8, litPins: 6 }));
    const pins = [...el.querySelectorAll('[data-pin]')];
    expect(pins.length).toBe(8);
    expect(pins.filter((pin) => pin.hasAttribute('data-lit')).length).toBe(6);
    // The unlit two are the last of each edge.
    const tops = pins.filter((pin) => pin.getAttribute('y') === '206');
    const bottoms = pins.filter((pin) => pin.getAttribute('y') === '282');
    expect(tops.length).toBe(4);
    expect(bottoms.length).toBe(4);
    expect(tops.filter((pin) => pin.hasAttribute('data-lit')).length).toBe(3);
    expect(bottoms.filter((pin) => pin.hasAttribute('data-lit')).length).toBe(3);
    expect(pins.find((pin) => pin.hasAttribute('data-lit'))?.getAttribute('fill')).toBe('currentColor');
    expect(pins.find((pin) => !pin.hasAttribute('data-lit'))?.getAttribute('fill')).toBe('var(--app-paper)');
  });

  it('draws five rings, each wearing its number, and the column above the case', () => {
    const el = show(phone());
    const rings = [...el.querySelectorAll<SVGGElement>('[data-ring]')];
    expect(rings.map((ring) => ring.dataset.ring)).toEqual(['1', '2', '3', '4', '5']);
    expect(rings.map((ring) => ring.style.getPropertyValue('--ring'))).toEqual(['1', '2', '3', '4', '5']);
    expect(rings.map((ring) => ring.querySelectorAll('circle').length)).toEqual([16, 20, 26, 32, 40]);
    const column = el.querySelector('[data-part="column"]');
    expect(column?.querySelectorAll('circle').length).toBe(22);
    // Above the phone: every dot's y is under the case's top.
    for (const dot of column?.querySelectorAll('circle') ?? []) expect(Number(dot.getAttribute('cy'))).toBeLessThan(6);
    expect(el.querySelector('svg')?.getAttribute('viewBox')).toBe('0 -64 240 544');
  });

  it('wears the glow step and the warmth as its own attributes', () => {
    const el = show(phone({ glowStep: 3, warmth: 'hot' }));
    const svg = el.querySelector<SVGSVGElement>('svg')!;
    expect(svg.style.getPropertyValue('--glow-step')).toBe('3');
    expect(svg.dataset.warmth).toBe('hot');
  });

  it('draws the working step’s mark large, and swaps it with the step as a new node, so its fade plays again', () => {
    const el = show(phone({ step: 'listen' }));
    const before = el.querySelector('[data-mark]');
    expect(before?.getAttribute('data-mark')).toBe('listen');
    expect(el.querySelector('[data-mark] svg')).not.toBeNull();
    rerender(phone({ step: 'think' }));
    const after = el.querySelector('[data-mark]');
    expect(after?.getAttribute('data-mark')).toBe('think');
    expect(after).not.toBe(before);
    rerender(phone({ step: null }));
    expect(el.querySelector('[data-mark]')).toBeNull();
  });

  it('draws the case and the rings in the third ink and the die in full ink over paper', () => {
    const el = show(phone());
    expect(el.querySelector('[data-part="case"]')?.getAttribute('stroke')).toBe('var(--app-ink-3)');
    expect(el.querySelector('[data-part="case"]')?.getAttribute('fill')).toBe('none');
    expect(el.querySelector('[data-part="rings"]')?.getAttribute('fill')).toBe('var(--app-ink-3)');
    const die = el.querySelector('[data-part="die"]');
    expect(die?.getAttribute('fill')).toBe('var(--app-paper)');
    expect(die?.getAttribute('stroke')).toBe('currentColor');
    expect(el.querySelector('[data-part="core"]')?.getAttribute('fill')).toMatch(/^url\(#[a-zA-Z0-9]+hatch\)$/);
  });

  it('changes nothing but attributes between glow steps and warmths', () => {
    const el = show(phone({ glowStep: 0, warmth: 'cold', litPins: 0 }));
    const count = () => el.querySelectorAll('*').length;
    const was = count();
    rerender(phone({ glowStep: 5, warmth: 'hot', litPins: 8 }));
    expect(count()).toBe(was);
    rerender(phone({ glowStep: 2, warmth: 'warm', litPins: 3, still: true }));
    expect(count()).toBe(was);
    expect(el.querySelector('svg')?.hasAttribute('data-still')).toBe(true);
  });

  it('gives two phones on one page their own hatch and clip', () => {
    const el = show(
      <>
        {phone()}
        {phone()}
      </>,
    );
    const ids = [...el.querySelectorAll('pattern')].map((p) => p.id);
    expect(ids.length).toBe(2);
    expect(ids[0]).not.toBe(ids[1]);
  });
});

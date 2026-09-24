import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { isCodingFace, isTypeface, TYPEFACES } from '../core/preferences.ts';
import { TypefaceCards } from './TypefaceCards.tsx';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

let root: Root | null = null;
let host: HTMLDivElement | null = null;
afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
});

describe('the typeface cards', () => {
  it('offer every face, each a scrap of a note in its own family, and choose one on a tap', () => {
    const onValueChange = vi.fn();
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);
    act(() => root!.render(<TypefaceCards value="inter" onValueChange={onValueChange} />));
    const cards = [...host.querySelectorAll('label')];
    expect(cards.map((card) => card.querySelector('strong')?.textContent)).toEqual(['Inter', 'Noto', 'Plex', 'Maple Mono', 'Fira Code']);
    // Each previews the same Markdown: a heading with its hash and an ampersand, bold between its stars, and the pairs
    // a coding face joins.
    for (const card of cards) expect(card.textContent).toContain('# Quick & Foxy**bold** -> != <=');
    const families = cards.map((card) => (card.querySelector('[aria-hidden="true"]') as HTMLElement).style.fontFamily);
    expect(families[3]).toContain('Maple Mono');
    expect(families[4]).toContain('Fira Code Variable');
    // The coding faces are marked so their ligatures are set on and their letters unspaced.
    expect(cards.map((card) => card.dataset.coding !== undefined)).toEqual([false, false, false, true, true]);
    expect(cards[0]!.dataset.selected).toBe('true');
    act(() => (cards[4]!.querySelector('input') as HTMLInputElement).click());
    expect(onValueChange).toHaveBeenCalledWith('fira');
  });

  it('know the faces, and which are the coding ones', () => {
    expect(TYPEFACES).toEqual(['inter', 'noto', 'plex', 'maple', 'fira']);
    expect(isTypeface('maple')).toBe(true);
    expect(isTypeface('comic-sans')).toBe(false);
    expect(TYPEFACES.filter(isCodingFace)).toEqual(['maple', 'fira']);
  });
});

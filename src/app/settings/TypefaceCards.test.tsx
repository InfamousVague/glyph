import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';
import { INTERFACE_FACES, isCodingFace, isInterfaceFace, isTypeface, TYPEFACES } from '../core/preferences.ts';
import { TypefaceCards } from './TypefaceCards.tsx';

describe('the typeface cards', () => {
  it('offer every face for a note, each a scrap of Markdown in its own family, and choose one on a tap', () => {
    const onValueChange = vi.fn();
    const page = show(<TypefaceCards label="Note font" kind="note" faces={TYPEFACES} value="maple" onValueChange={onValueChange} />);
    const cards = [...page.querySelectorAll('label')];
    expect(cards.map((card) => card.querySelector('strong')?.textContent)).toEqual(['Maple Mono', 'Fira Code', 'Inter', 'Noto', 'Plex']);
    for (const card of cards) expect(card.textContent).toContain('# Quick & Foxy**bold** -> != <=');
    const families = cards.map((card) => (card.querySelector('[aria-hidden="true"]') as HTMLElement).style.fontFamily);
    expect(families[0]).toContain('Maple Mono');
    expect(families[1]).toContain('Fira Code Variable');
    // The coding faces are marked so their ligatures are set on and their letters unspaced.
    expect(cards.map((card) => card.dataset.coding !== undefined)).toEqual([true, true, false, false, false]);
    expect(cards[0]!.dataset.selected).toBe('true');
    act(() => (cards[1]!.querySelector('input') as HTMLInputElement).click());
    expect(onValueChange).toHaveBeenCalledWith('fira');
  });

  it('offer the sans for the interface, each a scrap of the app’s own words', () => {
    const onValueChange = vi.fn();
    const page = show(<TypefaceCards label="Interface font" kind="interface" faces={INTERFACE_FACES} value="inter" onValueChange={onValueChange} />);
    const cards = [...page.querySelectorAll('label')];
    expect(cards.map((card) => card.querySelector('strong')?.textContent)).toEqual(['Inter', 'Noto', 'Plex']);
    expect(cards[0]!.textContent).toContain('Notes & Books');
    expect(cards[0]!.textContent).not.toContain('Quick');
    act(() => (cards[2]!.querySelector('input') as HTMLInputElement).click());
    expect(onValueChange).toHaveBeenCalledWith('plex');
  });

  it('know the faces, which are coding ones, and which the interface may use', () => {
    expect(TYPEFACES).toEqual(['maple', 'fira', 'inter', 'noto', 'plex']);
    expect(isTypeface('maple')).toBe(true);
    expect(isTypeface('comic-sans')).toBe(false);
    expect(TYPEFACES.filter(isCodingFace)).toEqual(['maple', 'fira']);
    expect(isInterfaceFace('inter')).toBe(true);
    expect(isInterfaceFace('maple')).toBe(false);
  });
});

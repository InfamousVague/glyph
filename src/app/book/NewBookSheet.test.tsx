import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { goBack } from '../core/back.ts';
import { button, buttonSaying, rerender, show, typeInto } from '../../test/render.tsx';
import { NewBookSheet } from './NewBookSheet.tsx';

/**
 * The New book sheet: a name, notes picked as pages in the order they are tapped, moved and left out, and one note
 * made with exactly that index. Closed without making it, nothing is written.
 */

/** The row that makes the book: its words, then a hint that says what it will make. */
const make = () => buttonSaying(document.body, 'Make the book')!;
/** Words typed into the field whose label says `label`. */
const type = (label: string, value: string) => {
  const field = [...document.querySelectorAll<HTMLInputElement>('input')].find((i) => i.closest('label')?.textContent?.includes(label));
  if (!field) throw new Error(`no field ${label}`);
  typeInto(field, value);
};
const pages = () => [...document.querySelectorAll('ol[aria-label="Pages in this book"] li')].map((li) => li.querySelector('[class*=pageTitle]')?.textContent);

describe('the New book sheet', () => {
  it('is nothing while closed, and makes nothing when closed', () => {
    const onCreate = vi.fn();
    const onClose = vi.fn();
    show(<NewBookSheet open={false} onClose={onClose} titles={['A']} onCreate={onCreate} />);
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(onCreate).not.toHaveBeenCalled();
  });

  it('marks a note that is a canvas with the canvas mark, in the list and among the pages', () => {
    show(<NewBookSheet open onClose={() => {}} titles={['Packing', 'Route map']} onCreate={() => {}} isCanvas={(t) => t === 'Route map'} />);
    const marked = () => [...document.querySelectorAll('[title="A canvas"]')].map((m) => m.parentElement?.textContent?.trim());
    expect(marked()).toEqual(['Route map']);
    act(() => button('Route map').click());
    expect(marked()).toEqual(['Route map', 'Route map']);
  });

  it('needs a name before it will make the book', () => {
    const onCreate = vi.fn();
    show(<NewBookSheet open onClose={() => {}} titles={[]} onCreate={onCreate} />);
    expect(make().disabled).toBe(true);
    type('Name', 'Trip');
    expect(make().disabled).toBe(false);
    act(() => make().click());
    expect(onCreate).toHaveBeenCalledWith('Trip', []);
  });

  it('picks pages in the order tapped, finds by name, moves and leaves out, and makes the book with that index', () => {
    const onCreate = vi.fn();
    const onClose = vi.fn();
    show(<NewBookSheet open onClose={onClose} titles={['Packing', 'Days', 'Who comes', 'Food']} onCreate={onCreate} />);
    type('Name', 'Cabin trip');
    act(() => button('Days').click());
    act(() => button('Packing').click());
    act(() => button('Food').click());
    expect(pages()).toEqual(['Days', 'Packing', 'Food']);
    // A second tap takes it out; a search narrows the list.
    act(() => button('Food').click());
    expect(pages()).toEqual(['Days', 'Packing']);
    type('Find a note', 'who');
    expect([...document.querySelectorAll('ul[aria-label="Notes"] button')].map((b) => b.textContent?.trim())).toEqual(['Who comes']);
    act(() => button('Move Packing up').click());
    expect(pages()).toEqual(['Packing', 'Days']);
    act(() => button('Move Packing up').click());
    expect(pages()).toEqual(['Packing', 'Days']);
    act(() => make().click());
    expect(onCreate).toHaveBeenCalledWith('Cabin trip', ['Packing', 'Days']);
    expect(onClose).toHaveBeenCalled();
  });

  it('closes on a back gesture while open, and holds none while closed', () => {
    const onClose = vi.fn();
    show(<NewBookSheet open onClose={onClose} titles={[]} onCreate={() => {}} />);
    expect(goBack()).toBe(true);
    expect(onClose).toHaveBeenCalledTimes(1);
    rerender(<NewBookSheet open={false} onClose={onClose} titles={[]} onCreate={() => {}} />);
    expect(goBack()).toBe(false);
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('moves a page dragged by its grip, and leaves one out by its cross', () => {
    const onCreate = vi.fn();
    show(<NewBookSheet open onClose={() => {}} titles={['Packing', 'Days', 'Food']} onCreate={onCreate} />);
    type('Name', 'Trip');
    for (const title of ['Packing', 'Days', 'Food']) act(() => button(title).click());
    const rows = [...document.querySelectorAll<HTMLElement>('ol[aria-label="Pages in this book"] li')];
    rows.forEach((li, i) => {
      li.getBoundingClientRect = () => ({ top: i * 40, bottom: i * 40 + 40, height: 40, left: 0, right: 300, width: 300, x: 0, y: i * 40, toJSON: () => ({}) }) as DOMRect;
    });
    const grip = rows[2]!.querySelector<HTMLElement>('[class*=grip]')!;
    const drag = (type: string, clientY: number) =>
      act(() => {
        grip.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, clientY, button: 0 }), { pointerId: 1, pointerType: 'mouse' }));
      });
    // Food, from the bottom to above Packing's middle: the first page.
    drag('pointerdown', 100);
    drag('pointermove', 10);
    drag('pointerup', 10);
    expect(pages()).toEqual(['Food', 'Packing', 'Days']);
    act(() => button('Leave Packing out').click());
    expect(pages()).toEqual(['Food', 'Days']);
    act(() => make().click());
    expect(onCreate).toHaveBeenCalledWith('Trip', ['Food', 'Days']);
  });
});

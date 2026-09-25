import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { button, press, show, typeInto } from '../../test/render.tsx';
import { CheatSheet } from './CheatSheet.tsx';
import { markGroups } from './marks.ts';

/**
 * The cheat sheet's find and its jumps. Each card's example is the note's own editor, built as the card comes near the
 * screen; this document never says a card is near, so the cards stay as their placeholders and the test is of the
 * sheet, not of fifty editors.
 */
const had = { io: globalThis.IntersectionObserver, scroll: Element.prototype.scrollIntoView };
const scrolled = vi.fn();
beforeAll(() => {
  globalThis.IntersectionObserver = class {
    observe(): void {}
    unobserve(): void {}
    disconnect(): void {}
    takeRecords(): IntersectionObserverEntry[] {
      return [];
    }
  } as unknown as typeof IntersectionObserver;
  Element.prototype.scrollIntoView = function (this: Element, options?: boolean | ScrollIntoViewOptions) {
    scrolled(this, options);
  };
});
afterAll(() => {
  globalThis.IntersectionObserver = had.io;
  Element.prototype.scrollIntoView = had.scroll;
});

const cards = (el: HTMLElement) => [...el.querySelectorAll('article h3')].map((h) => h.textContent);
const find = (el: HTMLElement) => el.querySelector<HTMLInputElement>('input[type="search"]')!;
const chips = (el: HTMLElement) => el.querySelector('nav[aria-label="The groups of marks"]');

describe('the cheat sheet', () => {
  it('shows every mark, under a chip for each group', () => {
    const el = show(<CheatSheet />);
    const groups = markGroups();
    expect(cards(el)).toEqual(groups.flatMap((group) => group.rows.map((row) => row.name)));
    expect([...chips(el)!.querySelectorAll('button')].map((b) => b.textContent)).toEqual(groups.map((group) => group.title));
  });

  it('finds a mark by its name, by its characters, or by the words of its example', () => {
    const el = show(<CheatSheet />);
    typeInto(find(el), 'BOLD');
    expect(cards(el)).toContain('Bold');
    expect(cards(el)).not.toContain('Italic');
    typeInto(find(el), '||');
    expect(cards(el)).toEqual(['Spoiler']);
    typeInto(find(el), 'cabin key');
    expect(cards(el)).toEqual(expect.arrayContaining(['Spoiler', 'A coloured highlight']));
  });

  it('puts the chips away while finding, says so when nothing matches, and clears', () => {
    const el = show(<CheatSheet />);
    typeInto(find(el), 'nothing like this');
    expect(chips(el)).toBeNull();
    expect(cards(el)).toEqual([]);
    expect(el.textContent).toContain('No mark by that name.');
    press(button('Clear', el));
    expect(find(el).value).toBe('');
    expect(chips(el)).not.toBeNull();
    expect(cards(el).length).toBe(markGroups().flatMap((group) => group.rows).length);
  });

  it('jumps to a group from its chip', () => {
    const el = show(<CheatSheet />);
    const title = markGroups()[2]!.title;
    press(button(title, chips(el)!));
    const [target, options] = scrolled.mock.calls.at(-1) ?? [];
    expect((target as HTMLElement).dataset.group).toBe(title);
    expect(options).toMatchObject({ block: 'start' });
  });
});

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';

vi.mock('../core/haptics.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/haptics.ts')>()), fireNativeHaptic: vi.fn() }));

import { fireNativeHaptic } from '../core/haptics.ts';
import { goBack } from '../core/back.ts';
import { button, buttonSaying, press, show, typeInto } from '../../test/render.tsx';
import { plugins } from '../plugins/registry.ts';
import { AcademyScreen } from './AcademyScreen.tsx';
import { LESSONS, lessonsIn, readProgress, writeProgress } from './lessons.ts';

/**
 * The Academy as a person takes it: a lesson, their own line typed under it, the tick the moment the mark is in, and
 * Next - with the page staying put until they press it - then the summary at the end.
 */

beforeEach(() => {
  localStorage.clear();
  plugins.setEnabled('marks', true);
  vi.mocked(fireNativeHaptic).mockClear();
});

function academy() {
  const calls = { onDone: vi.fn(), onCheatSheet: vi.fn() };
  const el = show(<AcademyScreen {...calls} />);
  return { el, ...calls };
}

const field = (el: HTMLElement) => el.querySelector<HTMLTextAreaElement>('textarea')!;
const title = (el: HTMLElement) => el.querySelector('h2')?.textContent;
const [first, second] = LESSONS;

describe('the Academy', () => {
  it('opens at the first lesson not passed yet', () => {
    writeProgress(new Set([first!.id]));
    const { el } = academy();
    expect(title(el)).toBe(second!.title);
    // Where it is in its chapter, and how much of the whole has been learned.
    expect(el.textContent).toContain(`Markdown basics · 2 of ${lessonsIn('Markdown basics').length}`);
    expect(el.querySelector('[aria-label$="learned"]')?.getAttribute('aria-label')).toBe(`1 of ${LESSONS.length} learned`);
  });

  it('goes on from the last lesson of a chapter to the first of the next, and draws that chapter’s bars', () => {
    const basics = lessonsIn('Markdown basics');
    const more = lessonsIn('More Markdown');
    writeProgress(new Set(basics.slice(0, -1).map((lesson) => lesson.id)));
    const { el } = academy();
    expect(title(el)).toBe(basics.at(-1)!.title);
    expect(el.querySelectorAll('ol[aria-hidden] > li')).toHaveLength(basics.length);
    press(button('Skip', el));
    expect(title(el)).toBe(more[0]!.title);
    expect(el.textContent).toContain(`More Markdown · 1 of ${more.length}`);
    expect(el.querySelectorAll('ol[aria-hidden] > li')).toHaveLength(more.length);
  });

  it('teaches an effect with the note’s own drawing of it underneath', () => {
    const heat = LESSONS.find((lesson) => lesson.id === 'heat')!;
    writeProgress(new Set(LESSONS.slice(0, LESSONS.indexOf(heat)).map((lesson) => lesson.id)));
    const { el } = academy();
    expect(title(el)).toBe('Heat');
    typeInto(field(el), '🔥🔥too hot🔥🔥');
    expect(el.textContent).toContain(heat.praise);
    expect(readProgress().has('heat')).toBe(true);
  });

  it('offers no lesson for a mark that is switched off, and counts without it', () => {
    plugins.setEnabled('marks', false);
    try {
      writeProgress(new Set(LESSONS.filter((lesson) => !lesson.needs).map((lesson) => lesson.id)));
      const { el } = academy();
      // Every lesson on offer is learned: the plugin's are not waiting to be taken.
      expect(title(el)).toBe('That is every mark.');
      const offered = LESSONS.filter((lesson) => !lesson.needs).length;
      expect(el.querySelector('[aria-label$="learned"]')?.getAttribute('aria-label')).toBe(`${offered} of ${offered} learned`);
      expect(el.textContent).not.toContain('Marks and effects');
      expect(buttonSaying(el, 'A spoiler')).toBeUndefined();
    } finally {
      plugins.setEnabled('marks', true);
    }
  });

  it('ticks a lesson the moment its mark is typed, once, and waits for Next', () => {
    const { el } = academy();
    expect(title(el)).toBe(first!.title);
    expect(button('Skip', el)).toBeTruthy();
    typeInto(field(el), 'weekend');
    expect(readProgress().has(first!.id)).toBe(false);
    typeInto(field(el), '# weekend');
    expect(el.textContent).toContain(first!.praise);
    expect(readProgress().has(first!.id)).toBe(true);
    expect(fireNativeHaptic).toHaveBeenCalledTimes(1);
    // Carrying on playing is not passing again.
    typeInto(field(el), '# weekend trip');
    expect(fireNativeHaptic).toHaveBeenCalledTimes(1);
    // Still on the lesson: passing it never moves the page on by itself.
    expect(title(el)).toBe(first!.title);
    press(button('Next', el));
    expect(title(el)).toBe(second!.title);
  });

  it('writes the example into the field on Show me, and passes it', () => {
    const { el } = academy();
    press(buttonSaying(el, 'Show me'));
    expect(field(el).value).toBe(first!.example);
    expect(el.textContent).toContain(first!.praise);
  });

  it('starts each lesson on a clean page, with its hint put away', () => {
    const { el } = academy();
    press(button('Show me a hint', el));
    expect(el.textContent).toContain(first!.hint);
    typeInto(field(el), 'not a title');
    press(button('Skip', el));
    expect(title(el)).toBe(second!.title);
    expect(field(el).value).toBe('');
    expect(el.textContent).not.toContain(first!.hint);
    expect(button('Show me a hint', el)).toBeTruthy();
    // Skipped is not learned.
    expect(readProgress().has(first!.id)).toBe(false);
  });

  it('ends at the summary, where any lesson can be taken again, or all of them from the start', () => {
    writeProgress(new Set(LESSONS.map((lesson) => lesson.id)));
    const { el, onCheatSheet } = academy();
    expect(title(el)).toBe('That is every mark.');
    press(buttonSaying(el, 'Cheat sheet'));
    expect(onCheatSheet).toHaveBeenCalledTimes(1);
    press(buttonSaying(el, second!.title));
    expect(title(el)).toBe(second!.title);
  });

  it('forgets every lesson on Start again, and opens the first', () => {
    writeProgress(new Set(LESSONS.map((lesson) => lesson.id)));
    const { el } = academy();
    press(buttonSaying(el, 'Start again'));
    expect(readProgress().size).toBe(0);
    expect(title(el)).toBe(first!.title);
  });

  it('says the Academy is over, not that every mark is learned, when lessons were skipped', () => {
    writeProgress(new Set([first!.id]));
    const { el } = academy();
    for (let i = 1; i < LESSONS.length; i += 1) press(button('Skip', el));
    expect(title(el)).toBe('That is the end of the Academy.');
  });

  it('closes on its arrow and on the back gesture', () => {
    const { el, onDone } = academy();
    press(button('Close the Academy', el));
    act(() => void goBack());
    expect(onDone).toHaveBeenCalledTimes(2);
  });
});

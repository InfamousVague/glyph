import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';

vi.mock('../core/haptics.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/haptics.ts')>()), fireNativeHaptic: vi.fn() }));

// The Glacier kit reads matchMedia as it loads; jsdom has none.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
import { fireNativeHaptic } from '../core/haptics.ts';
import { goBack } from '../core/back.ts';
import { button, buttonSaying, press, show, typeInto } from '../../test/render.tsx';
import { plugins } from '../plugins/registry.ts';
import { AcademyScreen } from './AcademyScreen.tsx';
import { LESSONS, lessonsIn, readProgress, readSkipStandard, writeProgress } from './lessons.ts';

/**
 * The Academy as a person takes it: its contents, a lesson, their own line typed under it, the tick the moment the
 * mark is in, and Next - with the page staying put until they press it - then the end of the chapter, and the next.
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

/** From the contents, Start or Continue: into the first lesson not learned. */
const carryOn = (el: HTMLElement) => press(buttonSaying(el, 'Continue') ?? button('Start', el));

describe('the Academy', () => {
  it('opens on its chapters, and carries on at the first lesson not passed yet', () => {
    writeProgress(new Set([first!.id]));
    const { el } = academy();
    expect(title(el)).toBe('Carry on learning');
    expect(el.querySelectorAll('[aria-label="Chapters"] > li')).toHaveLength(7);
    expect(el.textContent).toContain(`Continue: ${second!.title}`);
    carryOn(el);
    expect(title(el)).toBe(second!.title);
    // Where it is in its chapter, and how much of the whole has been learned.
    expect(el.textContent).toContain(`Chapter 1 · Markdown basics · 2 of ${lessonsIn('Markdown basics').length}`);
    expect(el.querySelector('[aria-label$="learned"]')?.getAttribute('aria-label')).toBe(`1 of ${LESSONS.length} learned`);
  });

  it('starts a chapter from the contents, at its first lesson not learned', () => {
    const boards = lessonsIn('Boards and to-dos');
    writeProgress(new Set([boards[0]!.id]));
    const { el } = academy();
    press(button('Chapter 5, Boards and to-dos', el));
    expect(title(el)).toBe(boards[1]!.title);
    expect(el.querySelectorAll('ol[aria-hidden] > li')).toHaveLength(boards.length);
    // Back is the contents, not out of the Academy.
    press(button('The Academy’s chapters', el));
    expect(title(el)).toBe('Carry on learning');
  });

  it('ends a chapter on a page of its own, then goes on to the next', () => {
    const basics = lessonsIn('Markdown basics');
    const more = lessonsIn('More Markdown');
    writeProgress(new Set(basics.slice(0, -1).map((lesson) => lesson.id)));
    const { el } = academy();
    carryOn(el);
    expect(title(el)).toBe(basics.at(-1)!.title);
    expect(el.querySelectorAll('ol[aria-hidden] > li')).toHaveLength(basics.length);
    press(button('Skip', el));
    expect(title(el)).toBe('The end of the chapter.');
    // The skipped lesson can be taken from here.
    expect(buttonSaying(el, basics.at(-1)!.title)).toBeTruthy();
    press(buttonSaying(el, 'Next: More Markdown')!);
    expect(title(el)).toBe(more[0]!.title);
    expect(el.textContent).toContain(`Chapter 2 · More Markdown · 1 of ${more.length}`);
    expect(el.querySelectorAll('ol[aria-hidden] > li')).toHaveLength(more.length);
  });

  it('says a chapter is learned when every lesson in it is', () => {
    const places = lessonsIn('Links and places');
    writeProgress(new Set(places.slice(0, -1).map((lesson) => lesson.id)));
    const { el } = academy();
    press(button('Chapter 4, Links and places', el));
    press(buttonSaying(el, 'Show me')!);
    press(button('Next', el));
    expect(title(el)).toBe('Chapter learned.');
  });

  it('leaves standard Markdown out for a person who knows it, and remembers that', () => {
    const { el } = academy();
    const all = LESSONS.length;
    press(el.querySelector<HTMLButtonElement>('[role="switch"]')!);
    expect(readSkipStandard()).toBe(true);
    const kept = LESSONS.filter((lesson) => !lesson.standard).length;
    expect(el.querySelector('[aria-label$="learned"]')?.getAttribute('aria-label')).toBe(`0 of ${kept} learned`);
    expect(kept).toBeLessThan(all);
    expect(button('Chapter 1, Markdown basics', el).disabled).toBe(true);
    expect(el.textContent).toContain('Skipped');
    // Start is the first lesson Ghost.md has of its own, past every standard one.
    carryOn(el);
    expect(title(el)).toBe(LESSONS.find((lesson) => !lesson.standard)!.title);
  });

  it('teaches an effect with the note’s own drawing of it underneath', () => {
    const heat = LESSONS.find((lesson) => lesson.id === 'heat')!;
    writeProgress(new Set(LESSONS.slice(0, LESSONS.indexOf(heat)).map((lesson) => lesson.id)));
    const { el } = academy();
    carryOn(el);
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
      expect(button('Chapter 7, Marks and effects', el).disabled).toBe(true);
      expect(buttonSaying(el, 'A spoiler')).toBeUndefined();
    } finally {
      plugins.setEnabled('marks', true);
    }
  });

  it('ticks a lesson the moment its mark is typed, once, and waits for Next', () => {
    const { el } = academy();
    carryOn(el);
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
    carryOn(el);
    press(buttonSaying(el, 'Show me')!);
    expect(field(el).value).toBe(first!.example);
    expect(el.textContent).toContain(first!.praise);
  });

  it('starts each lesson on a clean page, with its hint put away', () => {
    const { el } = academy();
    carryOn(el);
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

  it('is the summary once everything is learned, with the cheat sheet and every chapter to take again', () => {
    writeProgress(new Set(LESSONS.map((lesson) => lesson.id)));
    const { el, onCheatSheet } = academy();
    expect(title(el)).toBe('That is every mark.');
    press(buttonSaying(el, 'Cheat sheet')!);
    expect(onCheatSheet).toHaveBeenCalledTimes(1);
    press(button('Chapter 1, Markdown basics', el));
    expect(title(el)).toBe(first!.title);
  });

  it('forgets every lesson on Start again, and opens the first', () => {
    writeProgress(new Set(LESSONS.map((lesson) => lesson.id)));
    const { el } = academy();
    press(buttonSaying(el, 'Start again')!);
    expect(readProgress().size).toBe(0);
    expect(title(el)).toBe(first!.title);
  });

  it('closes on its arrow and on the back gesture from the contents', () => {
    const { el, onDone } = academy();
    press(button('Close the Academy', el));
    act(() => void goBack());
    expect(onDone).toHaveBeenCalledTimes(2);
  });
});

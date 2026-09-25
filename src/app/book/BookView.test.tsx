import { describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { canvasNoteBody } from '../canvas/jsonCanvas.ts';
import { makeNote } from '../../test/notes.ts';
import { button, show, typeInto, unmount } from '../../test/render.tsx';
import { bookNoteBody, bookOf, chaptersOf } from './book.ts';
import { BookBar, BookFoot, BookView } from './BookView.tsx';

/**
 * The index view: the chapters as rows that open their notes, a chapter not written yet said so, the three edits
 * written back to the body, and the two ways to add one. And the bar a chapter wears.
 */

const rows = () => [...document.querySelectorAll<HTMLElement>('ol[aria-label="Chapters"] li')].map((li) => li.querySelector('[class*=chapterTitle]')?.textContent);

const BOOK = bookNoteBody('Field guide', ['Introduction', 'Trees', 'Birds']);

describe('the index view', () => {
  it('lists the chapters numbered, opens one on a tap, and says which is not written yet', () => {
    const open = vi.fn();
    show(<BookView body={BOOK} title="Field guide" known={(t) => t !== 'Birds'} open={open} titles={() => []} onChange={() => {}} />);
    expect(rows()).toEqual(['Introduction', 'Trees', 'Birds']);
    expect([...document.querySelectorAll('[class*=number]')].map((n) => n.textContent)).toEqual(['1', '2', '3']);
    act(() => button('Trees').click());
    expect(open).toHaveBeenCalledWith('Trees');
    expect(document.querySelector('li[data-waiting]')?.textContent).toContain('Birds');
    expect(document.querySelector('li[data-waiting]')?.textContent).toContain('not written yet');
  });

  it('moves a chapter, takes one out, and writes each change into the body', () => {
    const onChange = vi.fn();
    show(<BookView body={BOOK} title="Field guide" known={() => true} open={() => {}} titles={() => []} onChange={onChange} />);
    act(() => button('Move Birds up').click());
    expect(chaptersOf(onChange.mock.calls[0]![0] as string).map((c) => c.title)).toEqual(['Introduction', 'Birds', 'Trees']);
    act(() => button('Take Trees out of the book').click());
    expect(chaptersOf(onChange.mock.calls[1]![0] as string).map((c) => c.title)).toEqual(['Introduction', 'Birds']);
    // The first cannot go up, the last cannot go down.
    expect(button('Move Introduction up').disabled).toBe(true);
    expect(button('Move Birds down').disabled).toBe(true);
  });

  it('writes a chapter dragged by its grip to where it is let go', () => {
    const onChange = vi.fn();
    show(<BookView body={BOOK} title="Field guide" known={() => true} open={() => {}} titles={() => []} onChange={onChange} />);
    const rowEls = [...document.querySelectorAll<HTMLElement>('ol[aria-label="Chapters"] li')];
    // jsdom lays nothing out: each row 40px tall, one under another.
    rowEls.forEach((li, i) => {
      li.getBoundingClientRect = () => ({ top: i * 40, bottom: i * 40 + 40, height: 40, left: 0, right: 300, width: 300, x: 0, y: i * 40, toJSON: () => ({}) }) as DOMRect;
    });
    const grip = rowEls[0]!.querySelector<HTMLElement>('[class*=grip]')!;
    const drag = (type: string, clientY: number) =>
      act(() => {
        grip.dispatchEvent(Object.assign(new MouseEvent(type, { bubbles: true, clientY, button: 0 }), { pointerId: 1, pointerType: 'mouse' }));
      });
    drag('pointerdown', 20);
    drag('pointermove', 110);
    drag('pointerup', 110);
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(chaptersOf(onChange.mock.calls[0]![0] as string).map((c) => c.title)).toEqual(['Trees', 'Birds', 'Introduction']);
  });

  it('adds a new chapter as a canvas when asked, opening it as one, and offers that only where a canvas can be made', () => {
    const onChange = vi.fn();
    const open = vi.fn();
    const openCanvas = vi.fn();
    show(<BookView body={BOOK} title="Field guide" known={() => true} open={open} titles={() => []} onChange={onChange} openCanvas={openCanvas} />);
    act(() => button('Add a chapter').click());
    typeInto(document.querySelector<HTMLInputElement>('input[aria-label="New chapter\'s title"]')!, 'Trail map');
    act(() => button('Add as a canvas').click());
    expect(chaptersOf(onChange.mock.calls[0]![0] as string).map((c) => c.title)).toEqual(['Introduction', 'Trees', 'Birds', 'Trail map']);
    expect(openCanvas).toHaveBeenCalledWith('Trail map');
    expect(open).not.toHaveBeenCalled();
  });

  it('adds a new chapter by name and opens it, and adds a note already written from the library', () => {
    const onChange = vi.fn();
    const open = vi.fn();
    show(<BookView body={BOOK} title="Field guide" known={() => true} open={open} titles={() => ['Field guide', 'Trees', 'Rivers', 'Mountains']} onChange={onChange} />);
    act(() => button('Add a chapter').click());
    typeInto(document.querySelector<HTMLInputElement>('input[aria-label="New chapter\'s title"]')!, 'Rivers');
    act(() => button('Add and open').click());
    expect(chaptersOf(onChange.mock.calls[0]![0] as string).map((c) => c.title)).toEqual(['Introduction', 'Trees', 'Birds', 'Rivers']);
    expect(open).toHaveBeenCalledWith('Rivers');

    act(() => button('Add a note you have').click());
    // The book itself and the chapters already in it are not offered; several can be ticked and added at once.
    const offered = [...document.querySelectorAll('ul[aria-label="Notes to add"] button')].map((b) => b.textContent?.trim());
    expect(offered).toEqual(['Rivers', 'Mountains']);
    act(() => button('Mountains').click());
    act(() => button('Rivers').click());
    expect(button('Add 2 notes')).toBeTruthy();
    act(() => button('Add 2 notes').click());
    expect(chaptersOf(onChange.mock.calls[1]![0] as string).map((c) => c.title).slice(-2)).toEqual(['Mountains', 'Rivers']);
  });

  it('marks a chapter that is a canvas, and a canvas it offers to add, with the canvas mark', () => {
    const bodies: Record<string, string> = {
      Trees: '# Trees\n\nWords.',
      Birds: canvasNoteBody('Birds', { nodes: [], edges: [] }),
      Rivers: canvasNoteBody('Rivers', { nodes: [], edges: [] }),
      Mountains: '# Mountains',
    };
    show(
      <BookView
        body={BOOK}
        title="Field guide"
        known={(t) => t in bodies}
        open={() => {}}
        titles={() => ['Rivers', 'Mountains']}
        onChange={() => {}}
        bodyOf={(t) => bodies[t] ?? null}
      />,
    );
    const marked = [...document.querySelectorAll('ol[aria-label="Chapters"] li')].map((li) => [li.querySelector('[class*=chapterTitle]')?.textContent, !!li.querySelector('[class*=canvasMark]')]);
    // Introduction has no note yet, so nothing says what it is; Birds is a canvas.
    expect(marked).toEqual([
      ['Introduction', false],
      ['Trees', false],
      ['Birds', true],
    ]);
    expect(button('Birds, a canvas')).toBeTruthy();
    act(() => button('Add a note you have').click());
    const offered = [...document.querySelectorAll('ul[aria-label="Notes to add"] button')].map((b) => [b.textContent?.trim(), !!b.querySelector('[class*=canvasMark]')]);
    expect(offered).toEqual([
      ['Rivers', true],
      ['Mountains', false],
    ]);
  });

  it('read-only, draws the same numbered index with nothing to move, take out or add, and still reads straight through', () => {
    const open = vi.fn();
    show(<BookView body={BOOK} title="Field guide" known={(t) => t !== 'Birds'} open={open} titles={() => []} onChange={() => {}} readOnly />);
    expect(rows()).toEqual(['Introduction', 'Trees', 'Birds']);
    for (const label of ['Move Birds up', 'Take Trees out of the book', 'Add a chapter', 'Add a note you have']) {
      expect(document.querySelector(`button[aria-label="${label}"]`) ?? [...document.querySelectorAll('button')].find((b) => b.textContent?.trim() === label)).toBeFalsy();
    }
    expect(document.querySelector('[class*=grip]')).toBeNull();
    act(() => button('Trees').click());
    expect(open).toHaveBeenCalledWith('Trees');
    expect(button('Read straight through')).toBeTruthy();
  });

  it('says so when the book has no chapters', () => {
    show(<BookView body={bookNoteBody('Trip')} title="Trip" known={() => true} open={() => {}} titles={() => []} onChange={() => {}} />);
    expect(document.body.textContent).toContain('No chapters yet');
  });
});

describe('reading straight through', () => {
  it('draws the chapters one after another, says which is a canvas or not written, and goes back to the index', () => {
    const bodies: Record<string, string> = {
      Introduction: '# Introduction\n\nStart here.',
      Trees: '{"nodes":[{"id":"a","type":"text","text":"a","x":0,"y":0,"width":10,"height":10}],"edges":[]}',
    };
    show(<BookView body={BOOK} title="Field guide" known={(t) => t !== 'Birds'} open={() => {}} titles={() => []} onChange={() => {}} bodyOf={(t) => bodies[t] ?? null} />);
    act(() => button('Read straight through').click());
    const sections = [...document.querySelectorAll('section[id^="book-chapter-"]')];
    expect(sections.map((s) => s.getAttribute('aria-label'))).toEqual(['Introduction', 'Trees', 'Birds']);
    expect(sections[0]?.querySelector('.cm-content')?.textContent).toContain('Start here.');
    expect(sections[0]?.textContent).not.toContain('# Introduction');
    expect(sections[1]?.textContent).toContain('A canvas');
    expect(sections[2]?.textContent).toContain('Not written yet');
    // The rail names every chapter; Index goes back to the rows.
    expect([...document.querySelectorAll('nav[aria-label="Chapters"] button')].map((b) => b.textContent?.trim())).toEqual(['1 Introduction', '2 Trees', '3 Birds']);
    act(() => button('Index').click());
    expect(rows()).toEqual(['Introduction', 'Trees', 'Birds']);
  });
});

describe('the bar a chapter wears', () => {
  it('names the book and the place, and opens the neighbours and the book', () => {
    const place = bookOf([makeNote('b', BOOK)], 'Trees')!;
    const open = vi.fn();
    show(<BookBar place={place} open={open} />);
    expect(document.body.textContent).toContain('Field guide');
    expect(document.body.textContent).toContain('2 of 3');
    act(() => button('Previous chapter: Introduction').click());
    act(() => button('Next chapter: Birds').click());
    act(() => button('Open the book Field guide').click());
    expect(open.mock.calls.map((c) => c[0])).toEqual(['Introduction', 'Birds', 'Field guide']);
  });

  it('has no way past the ends', () => {
    const place = bookOf([makeNote('b', BOOK)], 'Introduction')!;
    show(<BookBar place={place} open={() => {}} />);
    expect(button('First chapter').disabled).toBe(true);
    expect(button('Next chapter: Trees').disabled).toBe(false);
  });
});

describe('the foot a chapter wears', () => {
  it('names the chapters either side under the page and opens them', () => {
    const open = vi.fn();
    show(<BookFoot place={bookOf([makeNote('b', BOOK)], 'Trees')!} open={open} />);
    expect(document.querySelector('nav[aria-label="Previous and next chapter"]')?.textContent).toBe('PreviousIntroductionNextBirds');
    act(() => button('Previous: Introduction').click());
    act(() => button('Next: Birds').click());
    expect(open.mock.calls.map((c) => c[0])).toEqual(['Introduction', 'Birds']);
  });

  it('has only Next on the first chapter, only Previous on the last, and nothing for a book of one', () => {
    show(<BookFoot place={bookOf([makeNote('b', BOOK)], 'Introduction')!} open={() => {}} />);
    expect([...document.querySelectorAll('[data-book-foot] button')].map((b) => b.getAttribute('aria-label'))).toEqual(['Next: Trees']);
    unmount();
    show(<BookFoot place={bookOf([makeNote('b', BOOK)], 'Birds')!} open={() => {}} />);
    expect([...document.querySelectorAll('[data-book-foot] button')].map((b) => b.getAttribute('aria-label'))).toEqual(['Previous: Trees']);
    unmount();
    show(<BookFoot place={bookOf([makeNote('b', bookNoteBody('Short', ['Only']))], 'Only')!} open={() => {}} />);
    expect(document.querySelector('[data-book-foot]')).toBeNull();
  });
});

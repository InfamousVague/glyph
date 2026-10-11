import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { button, buttonSaying, show, typeInto } from '../../test/render.tsx';
import { readComments } from '../core/comments/format.ts';
import { CommentList, CommentThread, NewComment } from './CommentCard.tsx';
import { ago, type CardPeople } from './commentWords.ts';

await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

/**
 * A thread's card, a new comment's field and the threads' list (editor/CommentCard.tsx; docs/SHARED.md, S8), drawn
 * from parsed threads alone - the note's, here read from a fence, and a canvas's in time - and saying what was pressed.
 */

const FENCE = [
  '```comments',
  'c1 sam 2026-10-04T19:00:12Z',
  'The venue needs confirming - the hall or the barn?',
  '  matt 2026-10-04T19:05:40Z',
  '  The hall.',
  '  Confirmed this morning.',
  'c2 matt 2026-10-04T19:10:00Z',
  'Which band?',
  '  resolved sam 2026-10-04T19:12:00Z',
  '```',
].join('\n');

const [VENUE, BAND] = readComments(FENCE).threads;
const PEOPLE: CardPeople = { colour: (handle) => (handle === 'sam' ? 'sea' : 'rose'), me: 'matt' };
const NOW = Date.parse('2026-10-04T21:30:00Z');

afterEach(() => vi.useRealTimers());

function thread(over: Partial<Parameters<typeof CommentThread>[0]> = {}) {
  const props = { thread: VENUE!, people: PEOPLE, onReply: vi.fn(), onResolve: vi.fn(), onReopen: vi.fn(), onDelete: vi.fn(), now: NOW, ...over };
  show(<CommentThread {...props} />);
  return props;
}

describe('a thread’s card', () => {
  it('shows each comment’s author in their colour, how long ago, and its words over several lines', () => {
    thread({ quote: 'venue' });
    const items = [...document.querySelectorAll('li')];
    expect(items).toHaveLength(2);
    expect(items[0]!.textContent).toContain('sam');
    expect(items[0]!.textContent).toContain('2 hr ago');
    expect(items[0]!.querySelector('[data-hue]')?.getAttribute('data-hue')).toBe('sea');
    // Your own comment says You, and its reply sits in by a step.
    expect(items[1]!.textContent).toContain('You');
    expect(items[1]!.hasAttribute('data-reply')).toBe(true);
    expect(items[1]!.querySelector('p:last-child')?.textContent).toBe('The hall.\nConfirmed this morning.');
    expect(document.querySelector('blockquote')?.textContent).toBe('venue');
  });

  it('sends a reply on Enter, and keeps Shift+Enter for a new line', () => {
    const props = thread();
    const field = document.querySelector('textarea')!;
    typeInto(field, 'Booked ');
    act(() => {
      field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', shiftKey: true, bubbles: true }));
    });
    expect(props.onReply).not.toHaveBeenCalled();
    act(() => {
      field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    });
    expect(props.onReply).toHaveBeenCalledWith('Booked');
    expect(field.value).toBe('');
    expect(button('Send reply').disabled).toBe(true);
  });

  it('offers Resolve on an open thread and Reopen on a resolved one, saying who closed it', () => {
    const open = thread();
    act(() => buttonSaying(document.body, 'Resolve')!.click());
    expect(open.onResolve).toHaveBeenCalled();
    const closed = thread({ thread: BAND! });
    expect(document.body.textContent).toContain('Resolved by sam, 2 hr ago.');
    act(() => buttonSaying(document.body, 'Reopen')!.click());
    expect(closed.onReopen).toHaveBeenCalled();
  });

  it('deletes only on a second press, and forgets the first after four seconds', () => {
    vi.useFakeTimers();
    const props = thread();
    act(() => buttonSaying(document.body, 'Delete thread')!.click());
    expect(props.onDelete).not.toHaveBeenCalled();
    act(() => {
      vi.advanceTimersByTime(4000);
    });
    expect(buttonSaying(document.body, 'Delete thread')).toBeDefined();
    act(() => buttonSaying(document.body, 'Delete thread')!.click());
    act(() => buttonSaying(document.body, 'Delete it?')!.click());
    expect(props.onDelete).toHaveBeenCalledTimes(1);
  });
});

describe('a new comment and the list', () => {
  it('focuses the new comment’s field, and adds only words', () => {
    const onSave = vi.fn();
    show(<NewComment quote="the barn" onSave={onSave} />);
    const field = document.querySelector('textarea')!;
    expect(document.activeElement).toBe(field);
    expect(button('Add comment').disabled).toBe(true);
    typeInto(field, '   ');
    expect(button('Add comment').disabled).toBe(true);
    typeInto(field, ' Which barn? ');
    act(() => button('Add comment').click());
    expect(onSave).toHaveBeenCalledWith('Which barn?');
  });

  it('lists the open threads first, with their replies, and opens the one pressed', () => {
    const onOpen = vi.fn();
    show(<CommentList threads={[BAND!, VENUE!]} people={PEOPLE} onOpen={onOpen} now={NOW} />);
    const rows = [...document.querySelectorAll<HTMLButtonElement>('li > button')];
    expect(rows[0]!.textContent).toContain('The venue needs confirming');
    expect(rows[0]!.textContent).toContain('1 reply');
    expect(rows[1]!.textContent).toContain('Resolved');
    expect(rows[1]!.hasAttribute('data-resolved')).toBe(true);
    act(() => rows[1]!.click());
    expect(onOpen).toHaveBeenCalledWith('c2');
  });

  it('says a time it cannot read as it was written', () => {
    expect(ago('yesterday')).toBe('yesterday');
    expect(ago('2026-10-04T21:29:30Z', NOW)).toBe('Just now');
  });
});

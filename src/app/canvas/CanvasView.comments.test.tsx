import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { show, typeInto, unmount, waitUntil } from '../../test/render.tsx';
import { setPreferences } from '../core/preferences.ts';
import { CanvasView } from './CanvasView.tsx';
import { parseCanvas, type Canvas } from './jsonCanvas.ts';

vi.mock('mermaid', () => ({ default: { initialize: () => undefined, render: async (id: string) => ({ svg: `<svg id="${id}"></svg>` }) } }));
vi.mock('../core/account/account.ts', () => ({
  accountState: () => ({ session: { token: 't', handle: 'matt', accountId: 7 }, unlocked: true }),
  onAccount: () => () => undefined,
  useAccount: () => ({ session: { token: 't', handle: 'matt', accountId: 7 }, unlocked: true }),
}));

/**
 * A canvas's comments in the view (docs/SHARED.md, S9; canvas/useCanvasComments.tsx): a round on a card's corner
 * for its threads, in the colour of who started the first open one, with how many are open; the round opens the
 * thread's card, where a reply, Resolve and Delete thread change the canvas; Comment on the picked card's bar starts
 * a thread; and a canvas that cannot change draws no rounds.
 */

const WITH = `{
  "nodes": [
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin" },
    { "id": "site", "type": "link", "x": 0, "y": 160, "width": 260, "height": 100, "url": "https://attack.fm/glyph" }
  ],
  "edges": [],
  "comments": [
    { "id": "c1", "node": "book", "by": "sam", "at": "2026-10-05T14:00:00Z", "text": "Which Friday?", "replies": [] },
    { "id": "c2", "node": "book", "by": "lee", "at": "2026-10-05T14:01:00Z", "text": "And where?", "replies": [], "resolved": { "by": "matt", "at": "2026-10-05T14:02:00Z" } }
  ]
}`;
const canvas = parseCanvas(WITH) as Canvas;
const tap = (el: Element, x = 10, y = 10) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: x, clientY: y })));
const round = (root: HTMLElement, id: string) => root.querySelector<HTMLButtonElement>(`[data-comment-round="${id}"]`);
const sheet = () => document.querySelector<HTMLElement>('[role="dialog"]');
const press = (label: string) => act(() => (document.querySelector(`button[aria-label="${label}"]`) as HTMLElement).click());
/** A row of the thread's card, by its words: Resolve, Reopen, Delete thread. */
const row = (words: string) => act(() => [...document.querySelectorAll<HTMLElement>('[role="dialog"] button')].find((b) => b.textContent?.includes(words))!.click());
const last = (onChange: ReturnType<typeof vi.fn>) => onChange.mock.calls.at(-1)![0] as Canvas;

beforeEach(() => setPreferences({ canvasSnap: false }));
afterEach(() => unmount());

describe('a canvas’s comments', () => {
  it('marks a card with its open threads, in the first open one’s colour, and opens its threads from the round', async () => {
    const onChange = vi.fn();
    const shown = show(<CanvasView canvas={canvas} dark={false} onChange={onChange} />);
    const mark = round(shown, 'book')!;
    expect(mark).not.toBeNull();
    expect(mark.textContent).toBe('1');
    expect(mark.getAttribute('aria-label')).toBe('2 comments on this card, 1 open');
    expect(mark.dataset.hue).toBe('ink');
    expect(round(shown, 'site')).toBeNull();
    tap(mark);
    await waitUntil(() => expect(sheet()).not.toBeNull());
    // Two threads: the list first, open ones first; the thread's card from a row.
    expect(sheet()?.textContent).toContain('Which Friday?');
    expect(sheet()?.textContent).toContain('And where?');
    act(() => [...document.querySelectorAll<HTMLElement>('[role="dialog"] button')].find((b) => b.textContent?.includes('Which Friday?'))!.click());
    await waitUntil(() => expect(document.querySelector('[role="dialog"] textarea')).not.toBeNull());
    typeInto(document.querySelector('[role="dialog"] textarea') as HTMLTextAreaElement, 'The 10th.');
    press('Send reply');
    const replied = last(onChange);
    expect(replied.comments?.find((thread) => thread.id === 'c1')?.replies).toEqual([expect.objectContaining({ by: 'matt', text: 'The 10th.' })]);
  });

  it('resolves and deletes a thread from its card, and starts one from the picked card’s bar', async () => {
    const onChange = vi.fn();
    const one = { ...canvas, comments: [canvas.comments![0]!] };
    const shown = show(<CanvasView canvas={one} dark={false} onChange={onChange} />);
    tap(round(shown, 'book')!);
    await waitUntil(() => expect(sheet()?.textContent).toContain('Which Friday?'));
    row('Resolve');
    expect(last(onChange).comments?.[0]?.resolved).toEqual(expect.objectContaining({ by: 'matt' }));
    // The canvas comes back changed, as the note would hand it: the card shows the thread resolved, and Delete asks twice.
    shown.remove();
    const again = show(<CanvasView canvas={last(onChange)} dark={false} onChange={onChange} />);
    expect(round(again, 'book')?.textContent).toBe('✓');
    tap(round(again, 'book')!);
    await waitUntil(() => expect(sheet()?.textContent).toContain('Resolved by You'));
    row('Delete thread');
    row('Delete it? Press again');
    await waitUntil(() => expect(last(onChange).comments).toBeUndefined());
    // A tap picks the card, and Comment on its bar opens a new comment, which goes into the canvas on the card.
    await waitUntil(() => expect(sheet()).toBeNull());
    tap(again.querySelector('[data-card="site"]')!);
    await waitUntil(() => expect(again.querySelector('[data-card-bar="site"]')).not.toBeNull());
    press('Comment on this card');
    await waitUntil(() => expect(document.querySelector('[role="dialog"] textarea')).not.toBeNull());
    expect(sheet()?.textContent).toContain('https://attack.fm/glyph');
    typeInto(document.querySelector('[role="dialog"] textarea') as HTMLTextAreaElement, 'Is this the right link?');
    press('Add comment');
    const added = last(onChange);
    expect(added.comments).toHaveLength(1);
    expect(added.comments![0]).toEqual(expect.objectContaining({ node: 'site', by: 'matt', text: 'Is this the right link?', replies: [] }));
    expect(added.comments![0]!.id).toMatch(/^c[0-9a-z]{4,}$/);
    await waitUntil(() => expect(sheet()).toBeNull());
  });

  it('draws no rounds, and no Comment, on a canvas that cannot change', () => {
    const shown = show(<CanvasView canvas={canvas} dark={false} />);
    expect(round(shown, 'book')).toBeNull();
  });
});

import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { Archive, Bookmark, History, Mic, Pin, Share2 } from '@glacier/icons';
import { stubResizeObserver } from '../../test/stubs.ts';
import { NoteTools, type ToolAction } from './NoteTools.tsx';

/**
 * The bar's actions come out of More as the row has room for them, in their order (Matt: "I'd like the top toolbar to
 * automatically adapt to show more or less icons if there is real estate on the screen for it"; editor/toolRoom.ts).
 * jsdom lays nothing out, so each element is given a width: every ring 36px, the tools as wide as their rings, and the
 * row as wide as the test says.
 */

stubResizeObserver();

const RING = 36;
const ACTIONS: ToolAction[] = [
  { id: 'share', label: 'Share', icon: Share2, onPress: () => {} },
  { id: 'history', label: 'Version history', icon: History, onPress: () => {} },
  { id: 'bookmark', label: 'Bookmark this line', icon: Bookmark, onPress: () => {} },
  { id: 'pin', label: 'Pin to the top', icon: Pin, onPress: () => {} },
  { id: 'archive', label: 'Archive', icon: Archive, onPress: () => {} },
  { id: 'speak', label: 'Talk into this note', icon: Mic, onPress: () => {} },
];

let root: Root | null = null;
let host: HTMLElement | null = null;

afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
  root = null;
  host = null;
  vi.restoreAllMocks();
});

/** The tools in a row of `rowWidth`, beside `others` px of other controls; answers the actions drawn, in order. */
function drawn(rowWidth: number, others = 0): string[] {
  const rect = (width: number) => ({ width, height: RING, top: 0, left: 0, right: width, bottom: RING, x: 0, y: 0, toJSON: () => ({}) }) as DOMRect;
  vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function (this: Element) {
    if (this.tagName === 'BUTTON') return rect(RING);
    if (this.hasAttribute('data-other')) return rect(others);
    // The tools and the slot they are in: as wide as the rings drawn in them.
    return rect(this.querySelectorAll('button').length * RING);
  });
  host = document.createElement('div');
  host.setAttribute('data-tool-row', '');
  Object.defineProperty(host, 'clientWidth', { value: rowWidth });
  document.body.append(host);
  const other = document.createElement('div');
  other.setAttribute('data-other', '');
  const slot = document.createElement('div');
  host.append(other, slot);
  root = createRoot(slot);
  act(() => root!.render(<NoteTools kind="words" page={false} switchable onSwitch={() => {}} onMore={() => {}} actions={ACTIONS} />));
  return [...host.querySelectorAll('[data-tool]')].map((button) => button.getAttribute('data-tool')!);
}

describe('the note’s tools in the bar', () => {
  it('bring out as many actions as the row has room for, first first, and leave the rest in More', () => {
    // The view switch and More always: 72px. Room for two more beside them.
    expect(drawn(72 + 2 * RING + 10)).toEqual(['share', 'history']);
  });

  it('bring out every one on a wide row, and none on a narrow one', () => {
    expect(drawn(1200)).toEqual(['share', 'history', 'bookmark', 'pin', 'archive', 'speak']);
    act(() => root?.unmount());
    host?.remove();
    expect(drawn(80)).toEqual([]);
  });

  it('count the row’s other controls as taken', () => {
    expect(drawn(72 + 4 * RING + 10, 3 * RING)).toEqual(['share']);
  });
});

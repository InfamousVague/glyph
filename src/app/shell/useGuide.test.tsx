import { beforeEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';
import { useGuide, type GuideState } from './useGuide.ts';

/**
 * When the walkthrough opens by itself, what it keeps while it is up, and what closing it does - the three things a
 * relaunch reads to tell a first launch from someone who held the side key too soon (guide/tooSoon.ts).
 */

let guide: GuideState;
function Probe({ launchedByKey = false }: { launchedByKey?: boolean }) {
  guide = useGuide(launchedByKey);
  return null;
}

beforeEach(() => localStorage.clear());

describe('the guide', () => {
  it('opens by itself on a first launch, keeping the page it is on', () => {
    show(<Probe />);
    expect(guide.open).toBe(true);
    expect(guide.page).toBe(0);
    expect(localStorage.getItem('glyph-guide-started')).toBe('1');
    act(() => guide.turn(2));
    expect(localStorage.getItem('glyph-guide-page')).toBe('2');
  });

  it('waits on a launch by the side key: the person holding it is mid-sentence', () => {
    show(<Probe launchedByKey />);
    expect(guide.open).toBe(false);
    expect(guide.tooSoonAtBoot).toBe(false);
  });

  it('comes back with its line on a relaunch that finds it left on a page still to be read', () => {
    localStorage.setItem('glyph-guide-started', '1');
    localStorage.setItem('glyph-guide-page', '0');
    show(<Probe />);
    expect(guide.open).toBe(true);
    expect(guide.tooSoon).toBe(true);
  });

  it('comes back with its line, and holds the recording, when the side key was held on a page still to be read', () => {
    localStorage.setItem('glyph-guide-started', '1');
    localStorage.setItem('glyph-guide-page', '0');
    show(<Probe launchedByKey />);
    expect(guide.open).toBe(true);
    expect(guide.tooSoon).toBe(true);
    expect(guide.tooSoonAtBoot).toBe(true);
  });

  it('does not open by itself once seen, and is seen for good when it is closed', () => {
    show(<Probe />);
    act(() => guide.close());
    expect(guide.open).toBe(false);
    expect(localStorage.getItem('glyph-guide-seen')).toBe('1');
    expect(localStorage.getItem('glyph-guide-started')).toBeNull();
    expect(localStorage.getItem('glyph-guide-page')).toBeNull();
    show(<Probe />);
    expect(guide.open).toBe(false);
  });

  it('knows a reading page from the page that asks for the side key, and says "not yet" when told', () => {
    show(<Probe />);
    expect(guide.onReadingPage()).toBe(true);
    act(() => guide.sayTooSoon());
    expect(guide.tooSoon).toBe(true);
    // Turning the page is the line read.
    act(() => guide.turn(1));
    expect(guide.tooSoon).toBe(false);
    act(() => guide.hide());
    expect(guide.onReadingPage()).toBe(false);
    // Hidden for a recording is not seen: it opens again from Settings, at the page asked for.
    expect(localStorage.getItem('glyph-guide-seen')).toBeNull();
    act(() => guide.show(3));
    expect(guide.open).toBe(true);
    expect(guide.page).toBe(3);
  });
});

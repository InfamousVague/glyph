import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { act } from 'react';
import { show } from '../../test/render.tsx';
import { MarkExample } from './MarkExample.tsx';
import { MarksTable } from './MarksTable.tsx';
import { markGroups, type MarkRow } from './marks.ts';

/**
 * A mark's example is the note's own editor, and an editor is a real thing to build, so a row builds one only when it
 * comes near the screen. This document's observer is the test's: it says a row is near when the test says so.
 */
const near = new Set<(entries: IntersectionObserverEntry[]) => void>();
const had = globalThis.IntersectionObserver;
beforeAll(() => {
  globalThis.IntersectionObserver = class {
    private readonly callback: (entries: IntersectionObserverEntry[]) => void;
    constructor(callback: IntersectionObserverCallback) {
      this.callback = (entries) => callback(entries, this as unknown as IntersectionObserver);
    }
    observe(): void {
      near.add(this.callback);
    }
    unobserve(): void {}
    disconnect(): void {
      near.delete(this.callback);
    }
    takeRecords(): IntersectionObserverEntry[] {
      return [];
    }
  } as unknown as typeof IntersectionObserver;
});
afterAll(() => {
  globalThis.IntersectionObserver = had;
});

const bold: MarkRow = markGroups()[0]!.rows.find((row) => row.name === 'Bold')!;

describe('a mark’s example', () => {
  it('holds the line’s room with its words until it comes near, then is drawn by the note’s editor', () => {
    const el = show(<MarkExample row={bold} />);
    expect(el.querySelector('.cm-editor')).toBeNull();
    expect(el.textContent).toBe(bold.words);
    act(() => near.forEach((tell) => tell([{ isIntersecting: true } as IntersectionObserverEntry])));
    const editor = el.querySelector('.cm-editor');
    expect(editor).not.toBeNull();
    expect(editor?.textContent).toContain('Friday at noon');
  });

  it('is drawn at once where the page cannot watch the screen', () => {
    // The test's own observer goes back afterwards: without one, every row on a page builds its editor at once.
    const watching = globalThis.IntersectionObserver;
    globalThis.IntersectionObserver = undefined as unknown as typeof IntersectionObserver;
    try {
      const el = show(<MarkExample row={bold} />);
      expect(el.querySelector('.cm-editor')).not.toBeNull();
    } finally {
      globalThis.IntersectionObserver = watching;
    }
  });
});

describe('the guide’s table of marks', () => {
  it('has a row for every mark, with what to type, its name, and how to say it', () => {
    const el = show(<MarksTable />);
    const rows = [...el.querySelectorAll('[role="row"][data-looks]')];
    const all = markGroups().flatMap((group) => group.rows);
    expect(rows.length).toBe(all.length);
    const first = rows[0]!;
    expect(first.querySelector('code')?.textContent).toBe(all[0]!.symbol);
    expect(first.querySelector('pre')?.textContent).toBe(all[0]!.typed);
    expect(first.textContent).toContain(all[0]!.name);
    expect(first.textContent).toContain(all[0]!.say);
  });
});

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { markDetailsChanged, provideMarkDetails, type MarkDetailsProvider, type MarkEntry } from '../core/markDetails.ts';
import { glyphMarkdown } from './language.ts';
import { linkedRows } from './linkedRows.ts';
import { shortLinks } from './links.ts';
import { detailsArrived } from './markReads.ts';

const TASK = `https://app.notion.com/p/Buy-milk-${'a'.repeat(32)}`;
const doc = `- [ ] Buy milk [notion](${TASK})\n\nplain words\n`;

/** What the plugin knows about the task now, and every read the note asked it for. */
let known: MarkEntry | null = null;
const want = vi.fn<(url: string, fresh?: boolean) => void>();
const reader: MarkDetailsProvider = { peek: () => known, want: (url, fresh) => want(url, fresh), open: async () => undefined };
provideMarkDetails('notion', () => reader);

const ready: MarkEntry = {
  state: 'ready',
  loading: false,
  details: { url: TASK, title: 'Buy milk', status: { label: 'In progress', stage: 'doing' }, brief: ['P1'], fields: [], editedAt: 1, readAt: 1 },
};

/** The page's visibility as the reads see it, and the event the page sends when it changes. */
let shown: DocumentVisibilityState = 'visible';
function showPage(state: DocumentVisibilityState): void {
  shown = state;
  document.dispatchEvent(new Event('visibilitychange'));
}

let view: EditorView | null = null;
/** How many transactions have passed an answer on to the note. */
let arrivals = 0;

function open(still = false): EditorView {
  arrivals = 0;
  const count = EditorView.updateListener.of((update) => {
    for (const tr of update.transactions) if (tr.effects.some((effect) => effect.is(detailsArrived))) arrivals += 1;
  });
  view = new EditorView({ state: EditorState.create({ doc, extensions: [glyphMarkdown(), shortLinks({ still }), linkedRows(null), count] }), parent: document.body });
  return view;
}

beforeEach(() => {
  vi.useFakeTimers();
  known = null;
  want.mockClear();
  shown = 'visible';
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => shown });
});

afterEach(() => {
  view?.destroy();
  view = null;
  vi.useRealTimers();
  delete (document as Partial<Document> & { visibilityState?: DocumentVisibilityState }).visibilityState;
});

describe('asking what a note’s links are doing', () => {
  it('asks for every linked thing in view on opening, and again each minute the note is open', () => {
    open();
    expect(want.mock.calls).toEqual([[TASK, false]]);
    vi.advanceTimersByTime(59_000);
    expect(want).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(1_000);
    expect(want).toHaveBeenCalledTimes(2);
  });

  it('asks nothing while the app is in the background, and asks again when it comes back', () => {
    open();
    want.mockClear();
    showPage('hidden');
    vi.advanceTimersByTime(60_000);
    expect(want).not.toHaveBeenCalled();
    showPage('visible');
    expect(want.mock.calls).toEqual([[TASK, false]]);
  });

  it('asks about a mark as soon as it is written', () => {
    const on = open();
    want.mockClear();
    const other = `https://app.notion.com/p/Call-${'b'.repeat(32)}`;
    on.dispatch({ changes: { from: on.state.doc.length, insert: `- [ ] Call Sam [notion](${other})\n` } });
    expect(want.mock.calls.map(([url]) => url)).toContain(other);
  });

  it('stops asking when the note closes', () => {
    open().destroy();
    view = null;
    want.mockClear();
    vi.advanceTimersByTime(120_000);
    showPage('visible');
    expect(want).not.toHaveBeenCalled();
  });

  it('asks nothing on a note drawn still, on a card', () => {
    open(true);
    vi.advanceTimersByTime(120_000);
    showPage('visible');
    expect(want).not.toHaveBeenCalled();
  });
});

describe('an answer arriving', () => {
  const row = (on: EditorView) => [...on.dom.querySelectorAll('.cm-linkRow .cm-linkPill')].map((pill) => pill.textContent);

  it('is drawn in the row under the line, however many answers came in the same frame', () => {
    const on = open();
    expect(row(on)).toEqual(['Notion']);
    known = ready;
    markDetailsChanged();
    markDetailsChanged();
    markDetailsChanged();
    // Passed on at the next frame, once.
    expect(arrivals).toBe(0);
    vi.advanceTimersToNextFrame();
    expect(arrivals).toBe(1);
    expect(row(on)).toEqual(['Notion', 'In progress', 'P1']);
  });

  it('is drawn on a note drawn still too, which only never asks', () => {
    const on = open(true);
    known = ready;
    markDetailsChanged();
    vi.advanceTimersToNextFrame();
    expect(row(on)).toEqual(['Notion', 'In progress', 'P1']);
  });
});

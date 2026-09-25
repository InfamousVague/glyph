import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useRef } from 'react';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { show, unmount } from '../../test/render.tsx';
import { useLandAt } from './useLandAt.ts';

/**
 * A note opened at an item (`[[Groceries#^eggs]]`): the caret goes to the end of the item's words, before its anchor,
 * and the page is scrolled to it - and when the words arrive after the editor, the item is looked for again, a few
 * times, and then left.
 */

let view: EditorView;

function Landing({ at }: { at?: string }) {
  const page = useRef<HTMLDivElement>(null);
  const header = useRef<HTMLElement>(null);
  useLandAt(at, view, page, header);
  return (
    <div ref={page}>
      <header ref={header} />
    </div>
  );
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
});

afterEach(() => {
  // Down before the real clock is back, so the landing's timers are cleared on the clock that set them.
  unmount();
  view?.destroy();
  vi.useRealTimers();
});

function editor(doc: string): EditorView {
  view = new EditorView({ state: EditorState.create({ doc }), parent: document.body });
  return view;
}

describe('landing on an item', () => {
  it('puts the caret at the end of the item’s words, before its anchor', () => {
    const doc = '# Groceries\n- [ ] milk\n- [ ] eggs ^eggs\n- [ ] bread';
    editor(doc);
    show(<Landing at="^eggs" />);
    act(() => vi.advanceTimersByTime(0));
    expect(view.state.selection.main.head).toBe(doc.indexOf('eggs ^') + 'eggs'.length);
  });

  it('lands once the words arrive after the editor', () => {
    editor('');
    show(<Landing at="eggs" />);
    act(() => vi.advanceTimersByTime(300));
    const doc = '- [ ] milk\n- [ ] eggs ^eggs';
    act(() => view.dispatch({ changes: { from: 0, insert: doc } }));
    act(() => vi.advanceTimersByTime(100));
    expect(view.state.selection.main.head).toBe(doc.indexOf(' ^eggs'));
  });

  it('gives up on an item that never comes, rather than looking for ever', () => {
    editor('- [ ] milk');
    show(<Landing at="^eggs" />);
    // The first look, then twenty-four more at 100 ms: the last is at 2.4 s.
    act(() => vi.advanceTimersByTime(23 * 100));
    expect(vi.getTimerCount()).toBe(1);
    act(() => vi.advanceTimersByTime(100));
    expect(vi.getTimerCount()).toBe(0);
    expect(view.state.selection.main.head).toBe(0);
  });

  it('does nothing for a note opened without an item', () => {
    editor('- [ ] eggs ^eggs');
    show(<Landing />);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('stops looking when the note is left', () => {
    editor('- [ ] milk');
    show(<Landing at="^eggs" />);
    act(() => vi.advanceTimersByTime(250));
    unmount();
    expect(vi.getTimerCount()).toBe(0);
  });
});

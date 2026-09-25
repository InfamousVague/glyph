import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { button, show } from '../../test/render.tsx';
import { markDetailsChanged, provideMarkDetails, type MarkAction, type MarkEntry } from '../core/markDetails.ts';
import { goBack } from '../core/back.ts';
import { mountMarkMenu } from './markMenuMount.tsx';
import { MarkMenu, type MarkMenuProps } from './MarkMenu.tsx';

/**
 * A linked line's drawer: the task read through its plugin's provider (core/markDetails.ts), then Open, the board's
 * own actions, Refresh and Unlink. It is a React root of its own inside a CodeMirror widget (editor/markMenuMount.tsx),
 * so it speaks only through the `say` it is handed. A provider named for this file stands in for a plugin.
 */

const URL = 'https://example.test/task/1';

/** What the stand-in provider knows, and what it can do: changed by each test. */
const known: { entry: MarkEntry | null; actions: MarkAction[]; wanted: number } = { entry: null, actions: [], wanted: 0 };

provideMarkDetails('testboard', () => ({
  peek: () => known.entry,
  want: () => {
    known.wanted += 1;
  },
  open: async () => undefined,
  actions: () => known.actions,
}));

const ready = (title: string): MarkEntry => ({
  state: 'ready',
  loading: false,
  details: { url: URL, title, status: { label: 'In progress', stage: 'doing' }, brief: ['P1'], fields: [{ label: 'Due', value: 'Sep 20' }], editedAt: null, readAt: Date.now() },
});

function drawer(over: Partial<MarkMenuProps> = {}) {
  const props = { name: 'testboard', url: URL, words: 'Buy milk', say: vi.fn(), close: vi.fn(), unlink: vi.fn(), ...over };
  show(<MarkMenu {...props} />);
  return props;
}

afterEach(() => {
  known.entry = null;
  known.actions = [];
  known.wanted = 0;
});

describe('a linked line’s drawer', () => {
  it('reads the task afresh as it opens, and draws what the provider knows', () => {
    known.entry = ready('Buy oat milk');
    drawer();
    expect(known.wanted).toBe(1);
    const sheet = document.querySelector('[role="dialog"]')!;
    expect(sheet.getAttribute('aria-label')).toBe('Testboard Buy oat milk');
    expect(sheet.textContent).toContain('In progress');
    expect(sheet.textContent).toContain('Sep 20');
    expect(button('Open in Testboard')).toBeTruthy();
  });

  it('says it cannot read the task when the provider has nothing', () => {
    drawer();
    expect(document.body.textContent).toContain('Ghost.md can’t read Testboard right now.');
    // The item's own words stand in for the task's title.
    expect(document.body.textContent).toContain('Buy milk');
  });

  it('keeps the row under the finger when the task is read again, rather than drawing a new one', () => {
    known.entry = ready('Buy oat milk');
    drawer();
    const unlink = button('Unlink');
    known.entry = ready('Buy oat milk, two');
    act(() => markDetailsChanged());
    expect(document.body.textContent).toContain('Buy oat milk, two');
    expect(button('Unlink')).toBe(unlink);
  });

  it('shows an action’s busy words while it runs, stills the rows, and says what it did', async () => {
    let finish: (said: string) => void = () => undefined;
    known.entry = ready('Buy oat milk');
    known.actions = [{ id: 'done', label: 'Mark done', icon: 'done', busyLabel: 'Marking done…', run: () => new Promise<string>((resolve) => (finish = resolve)) }];
    const { say } = drawer();
    act(() => button('Mark done').click());
    expect(button('Marking done…').disabled).toBe(true);
    expect(button('Unlink').disabled).toBe(true);
    await act(async () => finish('Marked done in Testboard.'));
    expect(say).toHaveBeenCalledWith('Marked done in Testboard.');
    expect(button('Mark done').disabled).toBe(false);
  });

  it('says why an action failed, in its own words', async () => {
    known.entry = ready('Buy oat milk');
    known.actions = [{ id: 'done', label: 'Mark done', icon: 'done', busyLabel: 'Marking done…', run: () => Promise.reject(new Error('Testboard said no.')) }];
    const { say } = drawer();
    await act(async () => button('Mark done').click());
    expect(say).toHaveBeenCalledWith('Testboard said no.');
  });

  it('unlinks, keeping the words, and closes on the back gesture', async () => {
    const { unlink, say, close } = drawer();
    await act(async () => button('Unlink').click());
    expect(unlink).toHaveBeenCalledTimes(1);
    expect(say).toHaveBeenCalledWith('Unlinked. The words stay.');
    act(() => {
      goBack();
    });
    expect(close).toHaveBeenCalledTimes(1);
  });

  it('closes on a tap on the dimmed note, and not on a tap inside it', () => {
    const { close } = drawer();
    act(() => (document.querySelector('[role="dialog"]') as HTMLElement).click());
    expect(close).not.toHaveBeenCalled();
    act(() => (document.querySelector('[role="dialog"]')!.parentElement as HTMLElement).click());
    expect(close).toHaveBeenCalledTimes(1);
  });
});

describe('the drawer’s own root', () => {
  it('mounts into the widget’s host and comes down a microtask after it is asked to, not inside the asking', async () => {
    const host = document.createElement('div');
    document.body.appendChild(host);
    let down = () => {};
    act(() => {
      down = mountMarkMenu(host, { name: 'testboard', url: URL, words: 'Buy milk', say: () => {}, close: () => {}, unlink: () => {} });
    });
    expect(host.querySelector('[role="dialog"]')).not.toBeNull();
    down();
    // Still up: CodeMirror asks from inside its own update, and the root must not come down there.
    expect(host.querySelector('[role="dialog"]')).not.toBeNull();
    await act(async () => {
      await Promise.resolve();
    });
    expect(host.querySelector('[role="dialog"]')).toBeNull();
    host.remove();
  });
});

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, type ReactNode } from 'react';
import type { Output, Progress, RunOptions } from '../core/ai.ts';
import type { ReviewStage } from '../ai/useNoteReview.ts';
import { button, press, rerender, show, unmount } from '../../test/render.tsx';

// The kit reads matchMedia as it loads, and the haze watches the list's size; jsdom has neither.
await vi.hoisted(async () => {
  const stubs = await import('../../test/stubs.ts');
  stubs.stubMatchMedia();
  stubs.stubResizeObserver();
});

/** A model that answers when the test says so (`generate` is the seam, as in AiStrip.test.tsx). */
const fakes = vi.hoisted(() => [] as { options: RunOptions; report: (progress: Partial<Progress>) => void; finish: (text: string, extra?: Partial<Output>) => void; cancel: () => void }[]);
vi.mock('../core/ai.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../core/ai.ts')>();
  return {
    ...real,
    generate: (options: RunOptions) => {
      let resolve: (output: Output) => void = () => undefined;
      let reject: (failure: Error) => void = () => undefined;
      const done = new Promise<Output>((res, rej) => {
        resolve = res;
        reject = rej;
      });
      const fake = {
        options,
        report: (progress: Partial<Progress>) => options.onProgress({ id: 'x', phase: 'generating', promptTokens: 100, promptTokensDone: 100, outputTokens: 10, tokensPerSecond: 12, elapsedMs: 1000, partial: '', ...progress }),
        finish: (text: string, extra: Partial<Output> = {}) => resolve({ text, promptTokens: 100, outputTokens: 20, ms: 72_000, cachedTokens: 0, prefillMs: 100, loadMs: 100, tokensPerSecond: 12, truncated: false, ...extra }),
        cancel: () => reject(new Error('cancelled')),
      };
      fakes.push(fake);
      return { done, cancel: fake.cancel };
    },
  };
});

const haptics = vi.hoisted(() => [] as string[]);
vi.mock('../core/haptics.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/haptics.ts')>()),
  fireNativeHaptic: (kind = 'light') => {
    haptics.push(kind);
  },
}));

const refining = vi.hoisted(() => ({ download: null as { received: number; total: number } | null }));
vi.mock('../capture/refine.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../capture/refine.ts')>()),
  useRefining: () => ({ pending: new Set<string>(), download: refining.download }),
}));
/** The summary queue: which notes have a summary on the way, so a run of it may follow the review's. */
const summaries = vi.hoisted(() => ({ pending: new Set<string>() }));
vi.mock('../ai/summaries.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../ai/summaries.ts')>()),
  useSummaries: () => ({ pending: summaries.pending, native: new Set<string>(), failed: new Set<string>(), needsModel: new Set<string>() }),
}));

const { AtWork } = await import('./AtWork.tsx');
const { forgetAllRuns, runFor, startRun } = await import('../ai/runs.ts');
const { goBack, useBack } = await import('../core/back.ts');
const { setPreferences } = await import('../core/preferences.ts');
const { GRACE_MS, HOLD_MS, LEAVE_MS, OPEN_GRACE_MS } = await import('./steps.ts');
const { stubMatchMedia } = await import('../../test/stubs.ts');

/**
 * The scene over the note: it is there in the first frame a review key gives it, says what the review is doing,
 * follows the run through its phases and the phone's readings, leaves once the run ends, and never keeps a timer
 * after it is gone.
 */

const heard = 'Groceries for the week. Milk, eggs and coffee. Then the garden.';
const body = '# Groceries\n- Milk, eggs and coffee\nThen the garden.';
const listening = (percent: number): ReviewStage => ({ what: 'Listening again', detail: 'The slower speech model is listening to the recording again.', percent });
const comparing: ReviewStage = { what: 'Comparing', detail: '3 places where the two models heard different words.', percent: null };

type Props = Partial<Parameters<typeof AtWork>[0]>;
const atWork = (over: Props = {}) => <AtWork noteId="n" opening={1} heard={heard} body={body} hasJob stage={null} {...over} />;

const scene = () => document.querySelector<HTMLElement>('[aria-label="The models at work on this note"]');
const title = () => scene()?.querySelector('h2')?.textContent ?? null;
const working = () => scene()?.querySelector('[data-state="working"]')?.textContent ?? null;
const tile = (label: string) => [...(scene()?.querySelectorAll('dt') ?? [])].find((dt) => dt.textContent === label)?.nextElementSibling?.textContent ?? null;
const list = () => scene()?.querySelector<HTMLElement>('ol[data-streaming], ol:not([aria-label])') ?? null;

const later = (ms: number) => act(() => vi.advanceTimersByTime(ms));

function hide(hidden: boolean): void {
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (hidden ? 'hidden' : 'visible') });
  act(() => {
    document.dispatchEvent(new Event('visibilitychange'));
  });
}

/** The run started for note `n` on a fake that has not been told what to do yet. */
async function start(kind: 'review' | 'ask' | 'summarize' = 'review') {
  let handle!: ReturnType<typeof startRun>;
  await act(async () => {
    handle = startRun({ noteId: 'n', kind, model: 'qwen3.5-4b', system: 's', prompt: 'p', maxTokens: 1900, think: true });
  });
  return { handle, fake: fakes[fakes.length - 1]! };
}

beforeEach(() => {
  vi.useFakeTimers();
  localStorage.clear();
  fakes.length = 0;
  haptics.length = 0;
  refining.download = null;
  summaries.pending.clear();
  setPreferences({ wispEdge: true });
});

afterEach(async () => {
  unmount();
  // Whatever the fake engine still holds ends now, on the fake clock that set it, before the clock is real again.
  for (const fake of fakes) fake.cancel();
  await act(async () => {
    forgetAllRuns();
  });
  vi.useRealTimers();
  Reflect.deleteProperty(document, 'visibilityState');
  stubMatchMedia(false);
});

describe('opening', () => {
  it('renders nothing with no review', () => {
    show(atWork({ opening: null }));
    expect(scene()).toBeNull();
  });

  it('has the scene in the first render a key gives it, with the opening words', () => {
    show(atWork());
    expect(scene()).not.toBeNull();
    expect(title()).toBe('Checking what was heard.');
    expect(scene()?.textContent).toContain('The recording is saved.');
    expect(working()).toBe('Listening again');
    expect(scene()?.querySelector('[data-mark="listen"]')).not.toBeNull();
    // The transcript, through the phone.
    expect(scene()?.textContent).toContain('Groceries for the week.');
    expect(tile('Since Done')).toBe('0:00');
    expect(tile('CPU')).toBe('');
  });

  it('says the stage’s words and percent, and the download’s words while the better model comes down', () => {
    show(atWork({ stage: listening(40) }));
    expect(title()).toBe('Listening again, 40%.');
    expect(scene()?.querySelector('h2 [aria-hidden="true"]')?.textContent).toBe(', 40%');
    expect(scene()?.querySelector('[aria-live="polite"]')?.textContent).toBe('Listening again.');
    refining.download = { received: 12e6, total: 190e6 };
    rerender(atWork({ stage: listening(0) }));
    expect(title()).toBe('Getting the better voice model, 12 of 190 MB.');
    expect(working()).toContain('Getting the better voice model, 12 of 190 MB.');
    expect(scene()?.textContent).toContain('Once, then it stays on the phone.');
  });

  it('ignores an ended run the note already had, and follows a live one', async () => {
    const first = await start();
    await act(async () => {
      first.fake.finish('[]\n');
      await first.handle.done;
    });
    show(atWork({ opening: 1 }));
    expect(title()).toBe('Checking what was heard.');
    unmount();
    await start();
    show(atWork({ opening: 2 }));
    expect(title()).toBe('Loading Qwen3.5 4B.');
  });
});

describe('following the run', () => {
  it('goes through loading, reading, thinking and writing to done, with the phone’s readings, then leaves', async () => {
    show(atWork({ stage: comparing }));
    expect(scene()?.querySelector('[data-state="done"]')?.textContent).toContain('3 places where the two models heard different words.');
    rerender(atWork({ stage: null }));
    const { handle, fake } = await start();
    expect(title()).toBe('Loading Qwen3.5 4B.');
    expect(scene()?.textContent).toContain('2.7 GB on this phone.');
    expect(working()).toBe('Loading the model');
    expect(scene()?.querySelector('[data-turn]')).not.toBeNull();
    expect(tile('CPU')).toBe('');
    expect(tile('Heat')).toBe('');
    expect(tile('Pace')).toBe('');
    expect(scene()?.dataset.warmth).toBe('warm');
    // The listen step keeps what Comparing said after the stage has cleared.
    expect(scene()?.querySelector('[data-state="done"]')?.textContent).toContain('3 places where the two models heard different words.');

    await act(async () => fake.report({ phase: 'prefill', promptTokens: 1040, promptTokensDone: 312, tokensPerSecond: 430 }));
    expect(title()).toBe('Reading the note, 312 of 1040.');
    expect(working()).toBe('Reading the note');
    expect(scene()?.dataset.warmth).toBe('hot');
    // A report past loading without hardware: the phone gives no reading.
    expect(tile('CPU')).toBe('No reading');
    expect(tile('Heat')).toBe('No reading');
    expect(tile('Pace')).toBe('430');
    expect(scene()?.querySelectorAll('[data-lit]').length).toBe(0);

    await act(async () => fake.report({ phase: 'generating', partial: '<think>Is seat right?', thinking: true, tokensPerSecond: 9.4, hardware: { rssBytes: 3e9, freeBytes: 4e9, totalBytes: 12e9, cpuPercent: 640, threads: 6, cores: 8, tempC: 41 } }));
    expect(title()).toBe('Qwen3.5 4B is thinking it through.');
    expect(working()).toBe('Thinking it through');
    expect(scene()?.querySelector('[data-mark="think"]')).not.toBeNull();
    expect(tile('Heat')).toBe('41 °C');
    expect(tile('CPU')).toBe('640%');
    expect(tile('Pace')).toBe('9.4');
    expect(scene()?.textContent).toContain('Is seat right?');
    expect(scene()?.querySelectorAll('[data-pin]').length).toBe(8);
    expect(scene()?.querySelectorAll('[data-lit]').length).toBe(6);
    // Busy 640 of 600 is full; heat 41 is a little over half: the glow reaches the fourth ring.
    expect(scene()?.querySelector<SVGSVGElement>('svg[data-warmth]')?.style.getPropertyValue('--glow-step')).toBe('4');

    await act(async () => fake.report({ phase: 'generating', partial: '<think>Is seat right?</think>\n[{"what": "“seek”, not “seat”", "why": "x"}, {"what": "The garden li', thinking: true, hardware: { rssBytes: 3e9, freeBytes: 4e9, totalBytes: 12e9, cpuPercent: 640, threads: 6, cores: 8, tempC: 41 } }));
    expect(title()).toBe('Qwen3.5 4B is writing what it found.');
    expect(working()).toBe('Writing what it found');
    expect(scene()?.textContent).toContain('“seek”, not “seat”');
    expect(scene()?.textContent).toContain('The garden li');
    expect(scene()?.textContent).not.toContain('"what"');

    await act(async () => {
      fake.finish('<think>Is seat right?</think>\n[]\n', { thinking: true });
      await handle.done;
    });
    expect(title()).toBe('Reviewed by Qwen3.5 4B in 1:12.');
    expect(working()).toBeNull();
    expect(scene()?.querySelectorAll('[data-state="done"]').length).toBe(6);
    expect(scene()?.dataset.warmth).toBe('cold');
    // The settle: the words go to the quiet ink with the die.
    expect(scene()?.hasAttribute('data-ended')).toBe(true);
    expect(scene()?.querySelectorAll('[data-lit]').length).toBe(0);
    expect(scene()?.hasAttribute('data-leaving')).toBe(false);
    expect(scene()?.querySelector('[aria-live="polite"]')?.textContent).toBe('Reviewed by Qwen3.5 4B in 1:12.');
    await later(HOLD_MS);
    expect(scene()?.hasAttribute('data-leaving')).toBe(true);
    await later(LEAVE_MS);
    expect(scene()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('does not leave while a stage is up, whatever an earlier ask’s run did', async () => {
    const { handle, fake } = await start('ask');
    await act(async () => {
      fake.cancel();
      await handle.done;
    });
    expect(runFor('n')?.phase).toBe('stopped');
    show(atWork({ opening: 2, stage: listening(20) }));
    expect(title()).toBe('Listening again, 20%.');
    // In steps, so React commits between the timers: a leave chain a missing guard started would be flushed and seen.
    await later(GRACE_MS);
    await later(HOLD_MS);
    await later(LEAVE_MS + 1000);
    expect(scene()).not.toBeNull();
    expect(title()).toBe('Listening again, 20%.');
  });

  it('waits while the document is hidden, and settles and leaves once it is seen again', async () => {
    show(atWork({ stage: comparing }));
    rerender(atWork({ stage: null }));
    const { handle, fake } = await start();
    hide(true);
    await act(async () => {
      fake.finish('[]\n');
      await handle.done;
    });
    await later(HOLD_MS);
    await later(LEAVE_MS + 1000);
    expect(scene()).not.toBeNull();
    expect(scene()?.hasAttribute('data-leaving')).toBe(false);
    hide(false);
    expect(title()).toBe('Reviewed by Qwen3.5 4B in 1:12.');
    await later(HOLD_MS);
    expect(scene()?.hasAttribute('data-leaving')).toBe(true);
    await later(LEAVE_MS);
    expect(scene()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('cancels a pending leave when a new run appears', async () => {
    show(atWork({ stage: comparing }));
    rerender(atWork({ stage: null }));
    const first = await start();
    await act(async () => {
      first.fake.finish('[]\n');
      await first.handle.done;
    });
    await later(HOLD_MS - 50);
    await start();
    await later(5000);
    expect(scene()).not.toBeNull();
    expect(title()).toBe('Loading Qwen3.5 4B.');
  });

  it('waits the grace for a summary run after the review’s while the queue holds one for the note, and follows it', async () => {
    summaries.pending.add('n');
    show(atWork({ stage: comparing }));
    rerender(atWork({ stage: null }));
    const first = await start();
    await act(async () => {
      first.fake.finish('[]\n');
      await first.handle.done;
    });
    // Past the settle the scene is still there: a summary may follow.
    await later(HOLD_MS + LEAVE_MS);
    expect(scene()).not.toBeNull();
    expect(scene()?.hasAttribute('data-leaving')).toBe(false);
    const second = await start('summarize');
    await act(async () => second.fake.report({ phase: 'prefill', promptTokens: 400, promptTokensDone: 100 }));
    expect(working()).toBe('Reading the recording');
    expect([...(scene()?.querySelectorAll('[data-state]') ?? [])].map((li) => li.textContent)).toContain('Writing the summary');
    await act(async () => {
      second.fake.finish('## Summary\nA line.\n');
      await second.handle.done;
    });
    summaries.pending.clear();
    rerender(atWork({ stage: null }));
    await later(HOLD_MS + LEAVE_MS);
    expect(scene()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('leaves after the grace when no summary run comes, and after the settle alone when none is queued', async () => {
    summaries.pending.add('n');
    show(atWork({ stage: comparing }));
    rerender(atWork({ stage: null }));
    const { handle, fake } = await start();
    await act(async () => {
      fake.finish('[]\n');
      await handle.done;
    });
    await later(GRACE_MS - 1);
    expect(scene()?.hasAttribute('data-leaving')).toBe(false);
    await later(1);
    expect(scene()?.hasAttribute('data-leaving')).toBe(true);
    await later(LEAVE_MS);
    expect(scene()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('takes the review as over when no run comes after the stage clears, says so, and leaves', async () => {
    show(atWork({ stage: comparing }));
    rerender(atWork({ stage: null }));
    await later(GRACE_MS);
    expect(title()).toBe('Done.');
    expect(scene()?.querySelectorAll('[data-state="done"]').length).toBe(6);
    await later(HOLD_MS + LEAVE_MS);
    expect(scene()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('leaves quietly when it has seen nothing at all', async () => {
    show(atWork());
    await later(OPEN_GRACE_MS - 1);
    expect(scene()).not.toBeNull();
    expect(title()).toBe('Checking what was heard.');
    await later(1 + LEAVE_MS);
    expect(scene()).toBeNull();
    expect(vi.getTimerCount()).toBe(0);
  });
});

describe('the words', () => {
  it('stops the run from the scene', async () => {
    show(atWork());
    const { handle } = await start();
    press(button('Stop', scene()!));
    await act(async () => {
      await handle.done;
    });
    expect(haptics).toContain('warning');
    expect(title()).toBe('Stopped.');
    expect(working()).toBeNull();
    expect(button('Back to the note', scene()!)).toBeTruthy();
    expect(scene()?.querySelector('button')?.textContent).toBe('Back to the note');
  });

  it('shows Stop only while a run is live, never for a stage, even with an earlier ask’s run live under it', async () => {
    show(atWork({ stage: listening(10) }));
    expect([...scene()!.querySelectorAll('button')].map((b) => b.textContent)).toEqual(['Back to the note']);
    // CaptureScreen hands the review and an ask together; the ask's run is live while the stage is up, and has no Stop here.
    await start('ask');
    rerender(atWork({ stage: listening(20) }));
    expect(runFor('n')?.phase).toBe('loading');
    expect([...scene()!.querySelectorAll('button')].map((b) => b.textContent)).toEqual(['Back to the note']);
  });

  it('goes behind the note at once on Back to the note, and holds no timer after', () => {
    show(atWork());
    press(button('Back to the note', scene()!));
    expect(scene()).toBeNull();
    expect(haptics).toContain('selection');
    unmount();
    // A millisecond lets React's own zero-delay tasks go; the scene's timers are all longer, so one left would count.
    act(() => vi.advanceTimersByTime(1));
    expect(vi.getTimerCount()).toBe(0);
  });

  it('takes the first back gesture, and leaves the second to the note', () => {
    const onBack = vi.fn();
    function Note({ children }: { children: ReactNode }) {
      useBack(true, onBack);
      return children;
    }
    show(<Note>{atWork()}</Note>);
    act(() => {
      goBack();
    });
    expect(scene()).toBeNull();
    expect(onBack).not.toHaveBeenCalled();
    act(() => {
      goBack();
    });
    expect(onBack).toHaveBeenCalledOnce();
  });
});

describe('motion and the haze', () => {
  it('keeps still under reduced motion: no filter on the pane at all', () => {
    stubMatchMedia(true);
    show(atWork({ stage: listening(10) }));
    expect(scene()?.hasAttribute('data-still')).toBe(true);
    // The phone is told too: no fade on its mark, no transitions.
    expect(scene()?.querySelector('svg[data-warmth]')?.hasAttribute('data-still')).toBe(true);
    expect(scene()?.querySelector('filter')).toBeNull();
    expect(list()?.style.filter).toBe('');
  });

  it('bends the words by the warmth: half while a model listens or loads, whole while it reads and writes, none after', async () => {
    show(atWork({ stage: listening(10) }));
    const bend = () => scene()?.querySelector('feDisplacementMap')?.getAttribute('scale');
    expect(bend()).toBe('0.72');
    rerender(atWork({ stage: null }));
    const { handle, fake } = await start();
    await act(async () => fake.report({ phase: 'prefill', promptTokens: 1040, promptTokensDone: 312 }));
    expect(bend()).toBe('1.44');
    await act(async () => {
      fake.finish('[]\n');
      await handle.done;
    });
    expect(bend()).toBe('0.00');
  });

  it('wears the haze only with the smoke at the edges on', () => {
    setPreferences({ wispEdge: false });
    show(atWork({ stage: listening(10) }));
    expect(scene()?.querySelector('filter')).not.toBeNull();
    expect(list()?.style.filter).toBe('');
    act(() => setPreferences({ wispEdge: true }));
    expect(list()?.style.filter).toMatch(/^url\("?#[a-zA-Z0-9]+"?\)$/);
    // And never while the die is cold.
    rerender(atWork({ stage: null }));
    expect(list()?.style.filter).toBe('');
  });

  it('steps the noise once a report, no faster than eight a second, and not while hidden', () => {
    show(atWork({ stage: listening(10) }));
    const noise = scene()!.querySelector('feTurbulence')!;
    const first = noise.getAttribute('baseFrequency');
    expect(first).toMatch(/^0\.0\d{3} 0\.\d{4}$/);
    const writes = vi.spyOn(noise, 'setAttribute');
    // A report a moment later: one write.
    act(() => vi.advanceTimersByTime(200));
    rerender(atWork({ stage: listening(20) }));
    expect(writes).toHaveBeenCalledTimes(1);
    // The same report drawn again: nothing.
    rerender(atWork({ stage: listening(20) }));
    expect(writes).toHaveBeenCalledTimes(1);
    // Two reports inside an eighth of a second: the second is skipped.
    act(() => vi.advanceTimersByTime(200));
    rerender(atWork({ stage: listening(30) }));
    act(() => vi.advanceTimersByTime(20));
    rerender(atWork({ stage: listening(40) }));
    expect(writes).toHaveBeenCalledTimes(2);
    // Hidden: nothing, and the filter comes off.
    hide(true);
    act(() => vi.advanceTimersByTime(500));
    rerender(atWork({ stage: listening(50) }));
    expect(writes).toHaveBeenCalledTimes(2);
    expect(list()?.style.filter).toBe('');
    hide(false);
  });

  it('holds the feed and the picture while hidden, and reads them again on return', () => {
    show(atWork({ stage: listening(10) }));
    const head = () => scene()?.querySelector('[data-place="current"]')?.getAttribute('data-at');
    expect(head()).toBe('0');
    expect(scene()?.dataset.warmth).toBe('warm');
    hide(true);
    // The stage clears off screen: the head would move to the last phrase and the die would cool, but nothing is redrawn.
    rerender(atWork({ stage: null }));
    expect(head()).toBe('0');
    expect(scene()?.dataset.warmth).toBe('warm');
    hide(false);
    expect(head()).toBe('2');
    expect(scene()?.dataset.warmth).toBe('cold');
  });

  it('pauses the clock while hidden and jumps to the truth on return', () => {
    show(atWork({ stage: listening(10) }));
    expect(tile('Since Done')).toBe('0:00');
    act(() => vi.advanceTimersByTime(3000));
    expect(tile('Since Done')).toBe('0:03');
    hide(true);
    act(() => vi.advanceTimersByTime(5000));
    expect(tile('Since Done')).toBe('0:03');
    hide(false);
    expect(tile('Since Done')).toBe('0:08');
  });
});

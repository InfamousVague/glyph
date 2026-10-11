import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { startCapture } from './engine.ts';

/**
 * The two engines for a desk rather than a phone (capture/engine.ts, capture/simulated.ts): the browser's own
 * recogniser, and the scripted voice `?simulate` asks for. jsdom is not a Tauri webview, so `startCapture` takes one of
 * these, which is what a laptop running `npm run dev` does too.
 */

const handlers = () => ({ onPartial: vi.fn(), onSegment: vi.fn(), onError: vi.fn() });

describe('the browser’s own recogniser', () => {
  /** A stand-in for Chrome's webkitSpeechRecognition that the test drives. */
  class FakeRecognition {
    static last: FakeRecognition | null = null;
    continuous = false;
    interimResults = false;
    lang = '';
    onresult: ((event: { resultIndex: number; results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }> }) => void) | null = null;
    onerror: ((event: { error: string }) => void) | null = null;
    onend: (() => void) | null = null;
    starts = 0;
    stops = 0;
    constructor() {
      FakeRecognition.last = this;
    }
    start() {
      this.starts += 1;
    }
    stop() {
      this.stops += 1;
      // Chrome ends the session after a stop, as it does after a silence.
      this.onend?.();
    }
    /** Chrome's results, from `resultIndex` on: the final ones committed, the rest a guess. */
    say(results: { transcript: string; isFinal: boolean }[], resultIndex = 0) {
      this.onresult?.({ resultIndex, results: results.map((r) => Object.assign([{ transcript: r.transcript }], { isFinal: r.isFinal })) });
    }
  }

  let clock = 0;
  beforeEach(() => {
    clock = 1000;
    vi.spyOn(performance, 'now').mockImplementation(() => clock);
    (window as unknown as { webkitSpeechRecognition?: unknown }).webkitSpeechRecognition = FakeRecognition;
  });
  afterEach(() => {
    vi.restoreAllMocks();
    delete (window as unknown as { webkitSpeechRecognition?: unknown }).webkitSpeechRecognition;
  });

  it('commits each final result as a phrase timed from the last, and guesses the rest', async () => {
    const on = handlers();
    const session = await startCapture(on);
    const recognition = FakeRecognition.last!;
    expect(recognition).toMatchObject({ continuous: true, interimResults: true, lang: 'en-US', starts: 1 });
    clock = 2200;
    recognition.say([{ transcript: ' Oat milk ', isFinal: true }, { transcript: 'and eg', isFinal: false }]);
    clock = 3500;
    recognition.say([{ transcript: 'Oat milk', isFinal: true }, { transcript: ' and eggs', isFinal: true }], 1);
    expect(on.onSegment.mock.calls).toEqual([[{ text: 'Oat milk', startMs: 0, endMs: 1200 }], [{ text: 'and eggs', startMs: 1200, endMs: 2500 }]]);
    expect(on.onPartial.mock.calls).toEqual([['and eg'], ['']]);
    expect(session.positionMs()).toBe(2500);
    expect(session).toMatchObject({ kind: 'browser', wantsSamples: false, keepsAudio: false });
  });

  it('starts again when Chrome ends the session on a silence, until the person stops, and keeps nothing', async () => {
    const session = await startCapture(handlers());
    const recognition = FakeRecognition.last!;
    recognition.onend?.();
    expect(recognition.starts).toBe(2);
    await expect(session.stop()).resolves.toEqual({ recordedMs: null, transcript: null });
    expect(recognition.starts).toBe(2);
    expect(recognition.stops).toBe(1);
  });

  it('hands on an error, and stops for good on cancel', async () => {
    const on = handlers();
    const session = await startCapture(on);
    const recognition = FakeRecognition.last!;
    recognition.onerror?.({ error: 'not-allowed' });
    expect(on.onError).toHaveBeenCalledWith('not-allowed');
    await session.cancel();
    expect(recognition.starts).toBe(1);
  });

  it('says what is needed in a browser without one', async () => {
    delete (window as unknown as { webkitSpeechRecognition?: unknown }).webkitSpeechRecognition;
    await expect(startCapture(handlers())).rejects.toThrow('Voice notes need the Ghost.md app; this browser has no speech recognition.');
  });
});

describe('the scripted voice', () => {
  beforeEach(() => vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval', 'setTimeout', 'clearTimeout', 'performance'] }));
  afterEach(() => {
    vi.useRealTimers();
    window.history.replaceState(null, '', '/');
  });

  it('speaks the phrases given, each a growing guess and then a phrase, and stops with the length it spoke', async () => {
    window.history.replaceState(null, '', '/?simulate=say&say=Grocery run.|Oat milk and eggs.');
    const on = handlers();
    const session = await startCapture(on);
    expect(session).toMatchObject({ kind: 'simulated', wantsSamples: false, keepsAudio: true });
    await vi.advanceTimersByTimeAsync(3000);
    expect(on.onPartial.mock.calls.map(([text]) => text)).toEqual(['Grocery', 'Grocery run.', '', 'Oat', 'Oat milk', 'Oat milk and', 'Oat milk and eggs.', '']);
    expect(on.onSegment.mock.calls.map(([segment]) => segment)).toEqual([
      { text: 'Grocery run.', startMs: 0, endMs: 710 },
      { text: 'Oat milk and eggs.', startMs: 1010, endMs: 2080 },
    ]);
    const stopped = session.stop();
    await vi.advanceTimersByTimeAsync(0);
    await expect(stopped).resolves.toEqual({ recordedMs: session.positionMs(), transcript: null });
    expect(session.positionMs()).toBeGreaterThanOrEqual(2080);
  });

  it('pauses long after the fourth phrase of its note, so a paragraph break can be seen', async () => {
    window.history.replaceState(null, '', '/?simulate');
    const on = handlers();
    await startCapture(on);
    await vi.advanceTimersByTimeAsync(20_000);
    const segments = on.onSegment.mock.calls.map(([segment]) => segment as { text: string; startMs: number; endMs: number });
    expect(segments.map((segment) => segment.text)[0]).toBe('Weekend trip.');
    expect(segments).toHaveLength(5);
    expect(segments[4]!.startMs - segments[3]!.endMs).toBe(2600);
    expect(segments[1]!.startMs - segments[0]!.endMs).toBe(300);
  });
});

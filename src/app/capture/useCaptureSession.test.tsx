import { act, StrictMode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { show, unmount, waitUntil } from '../../test/render.tsx';
import type { Microphone, MicrophoneHandlers } from './audio.ts';
import type { CaptureHandlers, CaptureSession } from './engine.ts';

/**
 * The recorder's microphone and transcriber as they open (capture/useCaptureSession.ts), on a phone: the microphone
 * first, and what it hears while the model loads held and handed over once the engine is up, because the first words
 * of a voice note are usually its subject. And a start called off halfway lets go of what it opened, rather than
 * leaving a second microphone feeding the next start's session.
 */

vi.mock('../core/tauri.ts', () => ({ isTauri: () => true, invoke: vi.fn() }));
vi.mock('../core/haptics.ts', () => ({ fireNativeHaptic: vi.fn() }));

/** A promise and the hands that settle it, for a start held open until the test lets it go on. */
function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

const opening = vi.hoisted(() => ({
  /** The newest microphone asked for; `microphones` has every one, in order. */
  microphone: null as null | { handlers: MicrophoneHandlers; opened: ReturnType<typeof deferred<Microphone>> },
  microphones: [] as { handlers: MicrophoneHandlers; opened: ReturnType<typeof deferred<Microphone>> }[],
  engine: null as null | { handlers: CaptureHandlers; started: ReturnType<typeof deferred<CaptureSession>> },
}));

vi.mock('./audio.ts', () => ({
  openMicrophone: vi.fn((handlers: MicrophoneHandlers) => {
    const opened = deferred<Microphone>();
    opening.microphone = { handlers, opened };
    opening.microphones.push(opening.microphone);
    return opened.promise;
  }),
}));
vi.mock('./engine.ts', () => ({
  startCapture: vi.fn((handlers: CaptureHandlers) => {
    const started = deferred<CaptureSession>();
    opening.engine = { handlers, started };
    return started.promise;
  }),
}));

const { startCapture } = await import('./engine.ts');
const { useCaptureSession } = await import('./useCaptureSession.ts');

type State = ReturnType<typeof useCaptureSession>;
let latest: State | null = null;
let finished = false;
function Probe() {
  latest = useCaptureSession({
    fromAssistant: true,
    isFinished: () => finished,
    events: { onPartial: () => undefined, onSegment: () => undefined, onLevel: () => undefined },
  });
  return <p>{latest.phase}</p>;
}

function microphone() {
  return { stop: vi.fn<() => void>(), deviceRate: 48_000, state: (): AudioContextState => 'running' } satisfies Microphone;
}

function session(wantsSamples = true) {
  return { kind: 'whisper', wantsSamples, keepsAudio: true, push: vi.fn(), positionMs: () => 0, stop: vi.fn(), cancel: vi.fn() } satisfies CaptureSession;
}

const chunk = (value: number) => new Float32Array([value, value]);
const hear = (samples: Float32Array) => opening.microphone!.handlers.onChunk(samples);

beforeEach(() => {
  opening.microphone = null;
  opening.microphones = [];
  opening.engine = null;
  latest = null;
  finished = false;
  vi.mocked(startCapture).mockClear();
  vi.spyOn(console, 'info').mockImplementation(() => undefined);
});

describe('opening the recorder on a phone', () => {
  it('hands the engine everything the microphone heard while it started, in order, then each chunk as it comes', async () => {
    show(<Probe />);
    await waitUntil(() => expect(opening.microphone).not.toBeNull());
    const mic = microphone();
    // Heard while the microphone was still being opened, and then while the model loaded.
    hear(chunk(1));
    await act(async () => opening.microphone!.opened.resolve(mic));
    await waitUntil(() => expect(opening.engine).not.toBeNull());
    hear(chunk(2));
    hear(chunk(3));
    const started = session();
    await act(async () => opening.engine!.started.resolve(started));
    await waitUntil(() => expect(latest?.phase).toBe('listening'));

    expect(started.push.mock.calls.map(([samples]) => samples[0])).toEqual([1, 2, 3]);
    hear(chunk(4));
    expect(started.push.mock.calls.map(([samples]) => samples[0])).toEqual([1, 2, 3, 4]);
    expect(latest?.counts.current.heardSamples).toBe(8);
    expect(latest?.counts.current.deviceRate).toBe(48_000);
    expect(latest?.engine).toBe('whisper');
    expect(mic.stop).not.toHaveBeenCalled();
  });

  it('lets the microphone go when the engine wants none of its samples', async () => {
    show(<Probe />);
    await waitUntil(() => expect(opening.microphone).not.toBeNull());
    const mic = microphone();
    await act(async () => opening.microphone!.opened.resolve(mic));
    await waitUntil(() => expect(opening.engine).not.toBeNull());
    await act(async () => opening.engine!.started.resolve(session(false)));
    await waitUntil(() => expect(latest?.phase).toBe('listening'));
    expect(mic.stop).toHaveBeenCalledOnce();
  });

  it('stops a microphone that opens after the screen has gone, and never starts an engine to feed it', async () => {
    show(<Probe />);
    await waitUntil(() => expect(opening.microphone).not.toBeNull());
    unmount();
    const mic = microphone();
    await act(async () => opening.microphone!.opened.resolve(mic));
    expect(mic.stop).toHaveBeenCalledOnce();
    expect(startCapture).not.toHaveBeenCalled();
  });

  it('feeds the take from one microphone when React starts it twice, the first start called off before it opened', async () => {
    show(
      <StrictMode>
        <Probe />
      </StrictMode>,
    );
    await waitUntil(() => expect(opening.microphones).toHaveLength(2));
    const [first, second] = opening.microphones;
    const live = microphone();
    await act(async () => second!.opened.resolve(live));
    await waitUntil(() => expect(opening.engine).not.toBeNull());
    const started = session();
    await act(async () => opening.engine!.started.resolve(started));
    await waitUntil(() => expect(latest?.phase).toBe('listening'));

    // The called-off start's microphone opens late: it is stopped, and nothing it hears reaches the take.
    const orphan = microphone();
    await act(async () => first!.opened.resolve(orphan));
    expect(orphan.stop).toHaveBeenCalledOnce();
    first!.handlers.onChunk(chunk(9));
    second!.handlers.onChunk(chunk(1));
    expect(started.push.mock.calls.map(([samples]) => samples[0])).toEqual([1]);
    expect(live.stop).not.toHaveBeenCalled();
  });

  it('cancels an engine that starts after the screen has gone, and stops its microphone', async () => {
    show(<Probe />);
    await waitUntil(() => expect(opening.microphone).not.toBeNull());
    const mic = microphone();
    await act(async () => opening.microphone!.opened.resolve(mic));
    await waitUntil(() => expect(opening.engine).not.toBeNull());
    unmount();
    const started = session();
    await act(async () => opening.engine!.started.resolve(started));
    expect(started.cancel).toHaveBeenCalledOnce();
    expect(mic.stop).toHaveBeenCalled();
    expect(started.push).not.toHaveBeenCalled();
  });

  it('says why when the engine could not start, and lets the microphone go', async () => {
    show(<Probe />);
    await waitUntil(() => expect(opening.microphone).not.toBeNull());
    const mic = microphone();
    await act(async () => opening.microphone!.opened.resolve(mic));
    await waitUntil(() => expect(opening.engine).not.toBeNull());
    await act(async () => opening.engine!.started.reject(new Error('The voice model is still downloading.')));
    await waitUntil(() => expect(latest?.phase).toBe('failed'));
    expect(latest?.error).toBe('The voice model is still downloading.');
    expect(mic.stop).toHaveBeenCalledOnce();
  });
});

describe('closing the recorder', () => {
  async function listening() {
    show(<Probe />);
    await waitUntil(() => expect(opening.microphone).not.toBeNull());
    const mic = microphone();
    await act(async () => opening.microphone!.opened.resolve(mic));
    await waitUntil(() => expect(opening.engine).not.toBeNull());
    const started = session();
    await act(async () => opening.engine!.started.resolve(started));
    await waitUntil(() => expect(latest?.phase).toBe('listening'));
    return { mic, started };
  }

  it('cancels the take and the microphone when the screen goes without Done or Discard', async () => {
    const { mic, started } = await listening();
    unmount();
    expect(started.cancel).toHaveBeenCalledOnce();
    expect(mic.stop).toHaveBeenCalledOnce();
  });

  it('leaves them to Done or Discard once either has begun', async () => {
    const { mic, started } = await listening();
    finished = true;
    unmount();
    expect(started.cancel).not.toHaveBeenCalled();
    expect(mic.stop).not.toHaveBeenCalled();
  });
});

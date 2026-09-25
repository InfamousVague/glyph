import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { openMicrophone } from './audio.ts';

/**
 * The microphone as the page opens it (capture/audio.ts `openMicrophone`), against stand-ins for the Web Audio parts
 * jsdom does not have: what it asks the platform for, what it hands on per chunk, what it does with a context the
 * platform left suspended, and what it lets go of at the end.
 */

interface FakeContext {
  sampleRate: number;
  state: AudioContextState;
  resume: ReturnType<typeof vi.fn>;
  close: ReturnType<typeof vi.fn>;
  connected: string[];
}

let contexts: FakeContext[] = [];
let taps: { port: { onmessage: ((event: MessageEvent<Float32Array>) => void) | null }; disconnect: ReturnType<typeof vi.fn> }[] = [];
let asked: MediaStreamConstraints[] = [];
let tracks: { stop: ReturnType<typeof vi.fn> }[] = [];
/** The gain nodes the microphone made: the sink the tap feeds, which must play nothing. */
let sinks: { gain: { value: number } }[] = [];
let rate = 16_000;
let startsSuspended = false;
let resumeSettles = true;

function node(context: FakeContext, name: string) {
  return {
    connect(next: { name?: string } & object) {
      context.connected.push(`${name}->${(next as { name?: string }).name ?? 'destination'}`);
      return next;
    },
    disconnect: vi.fn(),
    name,
  };
}

beforeEach(() => {
  contexts = [];
  taps = [];
  asked = [];
  tracks = [{ stop: vi.fn() }];
  sinks = [];
  rate = 16_000;
  startsSuspended = false;
  resumeSettles = true;
  Object.defineProperty(navigator, 'mediaDevices', {
    configurable: true,
    value: {
      getUserMedia: vi.fn(async (constraints: MediaStreamConstraints) => {
        asked.push(constraints);
        return { getTracks: () => tracks };
      }),
    },
  });
  vi.stubGlobal(
    'AudioContext',
    class {
      sampleRate = rate;
      state: AudioContextState = startsSuspended ? 'suspended' : 'running';
      resume = vi.fn(() => (resumeSettles ? Promise.resolve().then(() => void (this.state = 'running')) : new Promise(() => undefined)));
      close = vi.fn(async () => undefined);
      connected: string[] = [];
      destination = { name: 'destination' };
      audioWorklet = { addModule: vi.fn(async () => undefined) };
      constructor() {
        contexts.push(this as unknown as FakeContext);
      }
      createMediaStreamSource() {
        return node(this as unknown as FakeContext, 'source');
      }
      createGain() {
        const sink = { ...node(this as unknown as FakeContext, 'sink'), gain: { value: 1 } };
        sinks.push(sink);
        return sink;
      }
    },
  );
  vi.stubGlobal(
    'AudioWorkletNode',
    class {
      port = { onmessage: null };
      disconnect = vi.fn();
      name = 'tap';
      constructor(context: FakeContext) {
        taps.push(this);
        Object.assign(this, { connect: node(context, 'tap').connect });
      }
    },
  );
  URL.createObjectURL = vi.fn(() => 'blob:tap');
  URL.revokeObjectURL = vi.fn();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe('the microphone', () => {
  it('asks for one channel with noise suppressed and no echo cancelling, and feeds a silent sink', async () => {
    await openMicrophone({ onChunk: vi.fn(), onLevel: vi.fn() });
    expect(asked).toEqual([{ audio: { channelCount: 1, noiseSuppression: true, autoGainControl: true, echoCancellation: false } }]);
    expect(contexts[0]?.connected).toEqual(['source->tap', 'tap->sink', 'sink->destination']);
    // Silent: whoever is speaking must not hear themselves back.
    expect(sinks.map((sink) => sink.gain.value)).toEqual([0]);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:tap');
  });

  it('hands on each chunk with its level, as the context gives it at 16 kHz', async () => {
    const onChunk = vi.fn();
    const onLevel = vi.fn();
    const microphone = await openMicrophone({ onChunk, onLevel });
    expect(microphone.deviceRate).toBe(16_000);
    taps[0]!.port.onmessage?.({ data: new Float32Array([0.5, -0.5, 0.5, -0.5]) } as MessageEvent<Float32Array>);
    expect(onChunk.mock.calls[0]?.[0]).toEqual(new Float32Array([0.5, -0.5, 0.5, -0.5]));
    expect(onLevel).toHaveBeenCalledWith(0.5);
  });

  it('brings a WebView’s 48 kHz down to 16 kHz when it ignored the rate asked for', async () => {
    rate = 48_000;
    const onChunk = vi.fn();
    const microphone = await openMicrophone({ onChunk, onLevel: vi.fn() });
    expect(microphone.deviceRate).toBe(48_000);
    taps[0]!.port.onmessage?.({ data: new Float32Array(4800).fill(0.25) } as MessageEvent<Float32Array>);
    const samples = onChunk.mock.calls[0]?.[0] as Float32Array;
    expect(samples).toHaveLength(1600);
    expect(samples.every((sample) => Math.abs(sample - 0.25) < 1e-6)).toBe(true);
  });

  it('wakes a context the platform left suspended, and gives up waiting on a resume that never answers', async () => {
    startsSuspended = true;
    const woken = await openMicrophone({ onChunk: vi.fn(), onLevel: vi.fn() });
    expect(contexts[0]?.resume).toHaveBeenCalledOnce();
    expect(woken.state()).toBe('running');

    vi.useFakeTimers({ toFake: ['setTimeout'] });
    resumeSettles = false;
    const opening = openMicrophone({ onChunk: vi.fn(), onLevel: vi.fn() });
    await vi.advanceTimersByTimeAsync(1500);
    const stuck = await opening;
    expect(stuck.state()).toBe('suspended');
  });

  it('lets go of everything when stopped, and hands on nothing after', async () => {
    const onChunk = vi.fn();
    const microphone = await openMicrophone({ onChunk, onLevel: vi.fn() });
    microphone.stop();
    expect(tracks[0]?.stop).toHaveBeenCalledOnce();
    expect(contexts[0]?.close).toHaveBeenCalledOnce();
    expect(taps[0]?.port.onmessage).toBeNull();
    expect(taps[0]?.disconnect).toHaveBeenCalledOnce();
  });

  it('rejects when the person declines the microphone, for the recorder to say why', async () => {
    (navigator.mediaDevices.getUserMedia as ReturnType<typeof vi.fn>).mockRejectedValueOnce(new DOMException('Permission denied', 'NotAllowedError'));
    await expect(openMicrophone({ onChunk: vi.fn(), onLevel: vi.fn() })).rejects.toThrow('Permission denied');
    expect(contexts).toEqual([]);
  });
});

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The transcriber's engines (capture/engine.ts): Whisper over the Tauri bridge, as the phone runs it - the one native
 * capture and who owns it, the recording kept or not by the binary's generation, the voice model fetched - and the
 * base64 envelope every chunk crosses in. The bridge is a stand-in: `invoke` answers what the test says Rust would, and
 * `listenTo` (core/events.ts) hands the test each handler so it can speak as Rust.
 */

let native = true;
const answers = new Map<string, (args?: Record<string, unknown>) => unknown>();
const invoked: { command: string; args?: Record<string, unknown> }[] = [];
const invoke = vi.fn(async (command: string, args?: Record<string, unknown>) => {
  invoked.push({ command, args });
  const answer = answers.get(command);
  if (!answer) throw new Error(`no answer for ${command}`);
  return answer(args);
});
const heard = new Map<string, (payload: unknown) => void>();
const unlistened: string[] = [];
const listenTo = vi.fn(async (event: string, handler: (payload: unknown) => void) => {
  heard.set(event, handler);
  return () => void unlistened.push(event);
});

/** The binary's generation, which the page asks once per load (core/nativeGeneration.ts): here, per test. */
let generation = 7;

vi.mock('../core/tauri.ts', () => ({ isTauri: () => native, invoke }));
vi.mock('../core/events.ts', () => ({ listenTo }));
vi.mock('../core/nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => native && generation >= wanted }));

const { setPreferences } = await import('../core/preferences.ts');
const engineModule = await import('./engine.ts');

/** The engine, on a binary of `generation`. */
async function engine(on = 7) {
  generation = on;
  return engineModule;
}

const handlers = () => ({ onPartial: vi.fn(), onSegment: vi.fn(), onError: vi.fn(), onModelProgress: vi.fn() });
const pushes = () => invoked.filter((call) => call.command === 'capture_push');

beforeEach(() => {
  native = true;
  answers.clear();
  invoked.length = 0;
  heard.clear();
  unlistened.length = 0;
  answers.set('capture_model_status', () => ({ present: true, name: 'base.en', path: '/models/base.en', bytes: 1 }));
  answers.set('capture_start', () => null);
  answers.set('capture_push', () => null);
  answers.set('capture_cancel', () => null);
});

afterEach(() => setPreferences({ localOnly: false }));

describe('Whisper on the phone', () => {
  it('hands on what Rust hears: guesses, phrases and errors', async () => {
    const { startCapture } = await engine();
    const on = handlers();
    await startCapture(on);
    heard.get('capture://partial')?.({ text: 'Oat mi' });
    heard.get('capture://segment')?.({ text: 'Oat milk.', startMs: 0, endMs: 900 });
    heard.get('capture://error')?.({ message: 'decoder stalled' });
    expect(on.onPartial).toHaveBeenCalledWith('Oat mi');
    expect(on.onSegment).toHaveBeenCalledWith({ text: 'Oat milk.', startMs: 0, endMs: 900 });
    expect(on.onError).toHaveBeenCalledWith('decoder stalled');
  });

  it('sends every chunk as base64, in order, and counts the recording by what it sent', async () => {
    const { startCapture, toBase64 } = await engine();
    const session = await startCapture(handlers());
    const first = new Float32Array(16_000).fill(0.25);
    const second = new Float32Array(8_000).fill(-0.5);
    session.push(first);
    session.push(second);
    answers.set('capture_stop', () => ({ transcript: '', recordedMs: 1500 }));
    await session.stop();
    expect(pushes().map((call) => call.args?.pcm)).toEqual([toBase64(new Uint8Array(first.buffer)), toBase64(new Uint8Array(second.buffer))]);
    expect(session.positionMs()).toBe(1500);
  });

  it('keeps the recording under the note’s id on a binary that can, and gives back its final words', async () => {
    const { startCapture } = await engine(6);
    const session = await startCapture(handlers());
    expect(session.keepsAudio).toBe(true);
    answers.set('capture_stop', () => ({ transcript: '  Pack sunscreen.  ', recordedMs: 4200 }));
    await expect(session.stop({ recordAs: 'n1', append: true })).resolves.toEqual({ recordedMs: 4200, transcript: 'Pack sunscreen.' });
    expect(invoked.at(-1)).toEqual({ command: 'capture_stop', args: { recordAs: 'n1', append: true } });
    expect(unlistened.sort()).toEqual(['capture://error', 'capture://partial', 'capture://segment']);
  });

  it('asks an older binary to stop with nothing, and keeps nothing', async () => {
    const { startCapture } = await engine(5);
    const session = await startCapture(handlers());
    expect(session.keepsAudio).toBe(false);
    answers.set('capture_stop', () => null);
    await expect(session.stop({ recordAs: 'n1' })).resolves.toEqual({ recordedMs: null, transcript: null });
    expect(invoked.at(-1)).toEqual({ command: 'capture_stop', args: undefined });
  });

  it('answers an empty final decode as none', async () => {
    const { startCapture } = await engine();
    const session = await startCapture(handlers());
    answers.set('capture_stop', () => ({ transcript: '   ', recordedMs: 900 }));
    await expect(session.stop()).resolves.toEqual({ recordedMs: 900, transcript: null });
    expect(invoked.at(-1)?.args).toEqual({ recordAs: null, append: false });
  });

  it('lets a replaced session neither push into the new one’s capture nor cancel it', async () => {
    const { startCapture } = await engine();
    const old = await startCapture(handlers());
    const current = await startCapture(handlers());
    old.push(new Float32Array(160));
    await old.cancel();
    expect(pushes()).toEqual([]);
    expect(invoked.some((call) => call.command === 'capture_cancel')).toBe(false);
    current.push(new Float32Array(160));
    answers.set('capture_stop', () => ({ transcript: '', recordedMs: 10 }));
    await current.stop();
    expect(pushes()).toHaveLength(1);
    const again = await startCapture(handlers());
    await again.cancel();
    expect(invoked.at(-1)?.command).toBe('capture_cancel');
  });

  it('stops listening when the native capture will not start, and says why', async () => {
    const { startCapture } = await engine();
    answers.set('capture_start', () => {
      throw new Error('microphone busy');
    });
    await expect(startCapture(handlers())).rejects.toThrow('microphone busy');
    expect(unlistened.sort()).toEqual(['capture://error', 'capture://partial', 'capture://segment']);
  });

  it('reports a push Rust refused as an error, and keeps sending the rest', async () => {
    const { startCapture } = await engine();
    const on = handlers();
    const session = await startCapture(on);
    let tries = 0;
    answers.set('capture_push', () => {
      tries += 1;
      if (tries === 1) throw 'capture_push rejected';
      return null;
    });
    session.push(new Float32Array(160));
    session.push(new Float32Array(160));
    answers.set('capture_stop', () => ({ transcript: '', recordedMs: 20 }));
    await session.stop();
    expect(on.onError).toHaveBeenCalledWith('capture_push rejected');
    expect(pushes()).toHaveLength(2);
  });
});

describe('the voice model', () => {
  it('is left alone when it is on the phone', async () => {
    const { ensureModel } = await engine();
    await expect(ensureModel()).resolves.toMatchObject({ present: true });
    expect(invoked.some((call) => call.command === 'capture_fetch_model')).toBe(false);
  });

  it('is fetched when it is not, with its progress told as it comes', async () => {
    const { ensureModel } = await engine();
    answers.set('capture_model_status', () => ({ present: false, name: 'base.en', path: '', bytes: 60_000_000 }));
    answers.set('capture_fetch_model', () => {
      heard.get('capture://model-progress')?.({ receivedBytes: 30_000_000, totalBytes: 60_000_000 });
      return { present: true, name: 'base.en', path: '/models/base.en', bytes: 60_000_000 };
    });
    const progress = vi.fn();
    await expect(ensureModel(progress)).resolves.toMatchObject({ present: true });
    expect(progress).toHaveBeenCalledWith(30_000_000, 60_000_000);
    expect(unlistened).toEqual(['capture://model-progress']);
  });

  it('is not downloaded with Local only on, and the recorder is told why', async () => {
    const { ensureModel } = await engine();
    answers.set('capture_model_status', () => ({ present: false, name: 'base.en', path: '', bytes: 60_000_000 }));
    setPreferences({ localOnly: true });
    await expect(ensureModel()).rejects.toThrow('Local only is on, so the voice model was not downloaded. Turn it off in Settings to get it.');
    expect(invoked.some((call) => call.command === 'capture_fetch_model')).toBe(false);
  });

  it('is nothing to ask about in a browser', async () => {
    const { ensureModel } = await engine();
    native = false;
    await expect(ensureModel()).resolves.toBeNull();
    expect(invoked).toEqual([]);
  });
});

describe('a recording a command did not keep', () => {
  it('goes to the note the command was confirmed for, or is thrown away', async () => {
    const { reassignRecording, discardRecording } = await engine();
    answers.set('capture_reassign_recording', () => 5400);
    answers.set('capture_discard_recording', () => null);
    await expect(reassignRecording('tmp', 'n1', true)).resolves.toBe(5400);
    await discardRecording('tmp');
    expect(invoked).toEqual([
      { command: 'capture_reassign_recording', args: { fromId: 'tmp', toId: 'n1', append: true } },
      { command: 'capture_discard_recording', args: { id: 'tmp' } },
    ]);
    native = false;
    await expect(reassignRecording('tmp', 'n1', false)).resolves.toBeNull();
  });
});

/**
 * The audio envelope. Rust decodes exactly what this produces back into f32
 * samples, so a byte out of place here is noise in every transcription.
 */
describe('toBase64', () => {
  it('matches the platform encoder on float PCM bytes', async () => {
    const { toBase64 } = await engine();
    const samples = new Float32Array([0, 0.5, -0.5, 1, -1, 0.123456]);
    const bytes = new Uint8Array(samples.buffer);
    expect(toBase64(bytes)).toBe(Buffer.from(bytes).toString('base64'));
  });

  /*
   * A 200 ms chunk is 12,800 bytes, and spreading that many arguments into
   * String.fromCharCode in one call is what the slicing exists to avoid.
   */
  it('round-trips a chunk far larger than one slice', async () => {
    const { toBase64 } = await engine();
    const samples = new Float32Array(16_000 * 3).map((_, i) => Math.sin(i / 40));
    const bytes = new Uint8Array(samples.buffer);
    const decoded = new Float32Array(new Uint8Array(Buffer.from(toBase64(bytes), 'base64')).buffer);
    expect(decoded).toEqual(samples);
  });
});

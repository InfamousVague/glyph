import { listenTo } from '../core/events.ts';
import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { invoke, isTauri } from '../core/tauri.ts';
import { preferences } from '../core/preferences.ts';
import type { Segment } from './markdown.ts';
import { simulated } from './simulated.ts';

/**
 * The transcriber, behind one interface, whichever one is running.
 *
 * Three engines answer it. On the phone it is Whisper in the Rust core: the page
 * streams microphone samples in and gets partial and committed text back as
 * events, and the recording is kept as the note's tape. In a desktop browser,
 * where there is no Rust, it is the browser's own speech recognition when it
 * has one - good enough to develop the capture screen against with a real
 * voice. And with `?simulate` in the URL it is a script that speaks a fixed
 * note on a timer (simulated.ts), which is what makes the screen testable with
 * no microphone.
 *
 * The page never learns which one it got beyond `kind`, which is shown so a
 * person can tell a real on-device transcription from a browser fallback.
 */

export type EngineKind = 'whisper' | 'browser' | 'simulated';

export interface CaptureHandlers {
  /** Best guess for speech not yet committed; replaces the previous one. */
  onPartial: (text: string) => void;
  /** Committed text, appended. */
  onSegment: (segment: Segment) => void;
  onError: (message: string) => void;
  /** Model download progress, only ever reported by the Whisper engine. */
  onModelProgress?: (receivedBytes: number, totalBytes: number) => void;
}

export interface StopOptions {
  /** Keep the audio as this note's tape. */
  recordAs?: string;
  /** Add to the note's existing tape rather than start it over. */
  append?: boolean;
}

export interface Stopped {
  /** The kept tape's whole length, or null when nothing was kept. */
  recordedMs: number | null;
  /**
   * The final decoder result, when the engine has one. Whisper produces this
   * from `capture_stop` after it has drained the last audio; phrase events can
   * still be in flight when the page removes its listeners. Browser, simulated,
   * and older native hosts do not have an authoritative final result.
   */
  transcript: string | null;
}

export interface CaptureSession {
  kind: EngineKind;
  /** Whether this engine wants the page's microphone samples. */
  wantsSamples: boolean;
  /** Whether `stop` can keep the recording (Whisper on a generation-6 binary). */
  keepsAudio: boolean;
  push: (samples: Float32Array) => void;
  /** How much has been recorded, in ms, on the timeline segment times use. */
  positionMs: () => number;
  /** Commit what remains and return the authoritative final transcript where the engine has one. */
  stop: (options?: StopOptions) => Promise<Stopped>;
  /** Drop it; resolves once the engine has let go (the Whisper session is gone), where that takes a trip to Rust. */
  cancel: () => void | Promise<void>;
}

/** Transfer a stopped temporary recording only after final confirmation. */
export async function reassignRecording(fromId: string, toId: string, append: boolean): Promise<number | null> {
  if (!isTauri()) return null;
  return await invoke<number | null>('capture_reassign_recording', { fromId, toId, append });
}

/** A cancelled/rejected command has no note to own its temporary recording. */
export async function discardRecording(id: string): Promise<void> {
  if (isTauri()) await invoke('capture_discard_recording', { id });
}

// ---- the model ----------------------------------------------------------------

export interface ModelStatus {
  present: boolean;
  name: string;
  path: string;
  bytes: number;
}

async function modelStatus(): Promise<ModelStatus | null> {
  if (!isTauri()) return null;
  return invoke<ModelStatus>('capture_model_status');
}

/**
 * Make sure the model is on the phone, downloading it if not.
 *
 * Called when the app opens as well as when a capture starts, so the download -
 * about 60 MB - happens the first time Glyph is opened rather than the first
 * time the side key is held. A note started on a whim that has to wait for a
 * download is a note that does not get started.
 */
export async function ensureModel(onProgress?: (received: number, total: number) => void): Promise<ModelStatus | null> {
  if (!isTauri()) return null;
  const status = await modelStatus();
  if (status?.present) return status;
  // Local only: nothing is downloaded, and the recorder says why.
  if (preferences().localOnly) throw new Error('Local only is on, so the voice model was not downloaded. Turn it off in Settings to get it.');

  const unlisten = await listenTo<{ receivedBytes: number; totalBytes: number }>('capture://model-progress', (progress) =>
    onProgress?.(progress.receivedBytes, progress.totalBytes),
  );
  try {
    return await invoke<ModelStatus>('capture_fetch_model');
  } finally {
    unlisten();
  }
}

// ---- engines ----------------------------------------------------------------------

export async function startCapture(handlers: CaptureHandlers): Promise<CaptureSession> {
  if (new URLSearchParams(window.location.search).has('simulate')) return simulated(handlers);
  if (isTauri()) return whisper(handlers);
  return browser(handlers);
}

/** The binary generation whose `capture_stop` keeps the recording. */
const RECORDING_GENERATION = 6;

/**
 * The Whisper session that owns the native capture, which there is only one of: every session's pushes land in the same
 * recording. A session that has been replaced (a start that was called off - React's development double start, or the
 * recorder closed at once, useCaptureSession.ts) must not keep pushing, or its audio is interleaved chunk by chunk with
 * the live session's, and the tape plays back as a stutter of two copies a few milliseconds apart that Whisper can't
 * make sense of.
 */
let owner: symbol | null = null;

async function whisper(handlers: CaptureHandlers): Promise<CaptureSession> {
  const unlisteners = await Promise.all([
    listenTo<{ text: string }>('capture://partial', (partial) => handlers.onPartial(partial.text)),
    listenTo<Segment>('capture://segment', (segment) => handlers.onSegment(segment)),
    listenTo<{ message: string }>('capture://error', (error) => handlers.onError(error.message)),
  ]);
  const unlistenAll = () => unlisteners.forEach((off) => off());

  await ensureModel(handlers.onModelProgress);

  /*
   * No sample can arrive before `capture_start` resolves: the session is only handed back after it. Starting loads the
   * model on the first press after launch, which takes long enough to swallow the first words - and the first words of
   * a note are usually its subject - so the recorder holds what the microphone hears until then and hands it all over
   * at once (useCaptureSession.ts).
   */
  /** Samples handed over, which is exactly the recording Rust holds once the chain drains. */
  let recorded = 0;
  // Pushes are chained so they reach Rust in order; two in-flight invokes are
  // not guaranteed to land in the order they were sent.
  let chain: Promise<unknown> = Promise.resolve();
  const me = Symbol('capture');
  const send = (samples: Float32Array) => {
    if (owner !== me) return;
    recorded += samples.length;
    const pcm = toBase64(new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength));
    chain = chain.then(() => invoke('capture_push', { pcm })).catch((error: unknown) => handlers.onError(String(error)));
  };

  // Asked rather than assumed: a bundle carrying this page can run on a binary
  // from before recordings were kept, whose capture_stop takes no arguments.
  const keepsAudio = await hasNativeGeneration(RECORDING_GENERATION);

  try {
    await invoke('capture_start');
  } catch (error) {
    unlistenAll();
    throw error;
  }
  // The native capture is this session's from here; any earlier session's pushes stop landing in it.
  owner = me;

  return {
    kind: 'whisper',
    wantsSamples: true,
    keepsAudio,
    push: send,
    positionMs: () => (recorded * 1000) / 16_000,
    stop: async (options = {}) => {
      await chain;
      if (owner === me) owner = null;
      try {
        if (!keepsAudio) {
          await invoke<unknown>('capture_stop');
          return { recordedMs: null, transcript: null };
        }
        const finished = await invoke<{ transcript: string; recordedMs: number | null }>('capture_stop', {
          recordAs: options.recordAs ?? null,
          append: options.append ?? false,
        });
        return { recordedMs: finished.recordedMs, transcript: finished.transcript?.trim() || null };
      } finally {
        unlistenAll();
      }
    },
    cancel: () => {
      unlistenAll();
      // A session that no longer owns the native capture leaves it alone: cancelling would end the newer session's.
      if (owner !== me) return Promise.resolve();
      owner = null;
      return invoke('capture_cancel').then(
        () => undefined,
        () => undefined,
      );
    },
  };
}

/**
 * Bytes as base64, for the trip across the IPC bridge.
 *
 * NOT a raw `Uint8Array` handed straight to `invoke`, although that is the
 * natural shape and works on the desktop. Android's WebView cannot give native
 * code a request's body, so Tauri carries every payload there as JSON, and raw
 * bytes arrive in Rust as a JSON value that `capture_push` rejected - on the
 * Fold, every chunk of every capture, which is a capture screen that never
 * transcribes a word. Base64 is the same bytes in a string both bridges carry,
 * at a cost of about 17 KB per 200 ms chunk.
 *
 * Built in slices because `String.fromCharCode(...bytes)` on a large array
 * overruns the engine's argument limit; 0x8000 is comfortably under it.
 */
export function toBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

/** The browser's own recogniser, for developing on a laptop. Chrome only. */
function browser(handlers: CaptureHandlers): CaptureSession {
  type Recognition = {
    continuous: boolean;
    interimResults: boolean;
    lang: string;
    onresult: ((event: { resultIndex: number; results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }> }) => void) | null;
    onerror: ((event: { error: string }) => void) | null;
    onend: (() => void) | null;
    start: () => void;
    stop: () => void;
  };
  const Ctor = (window as unknown as { webkitSpeechRecognition?: new () => Recognition }).webkitSpeechRecognition;
  if (!Ctor) throw new Error('Voice notes need the Ghost.md app; this browser has no speech recognition.');

  const recognition = new Ctor();
  recognition.continuous = true;
  recognition.interimResults = true;
  recognition.lang = 'en-US';
  const startedAt = performance.now();
  let lastEnd = 0;
  let running = true;
  let settle: (() => void) | null = null;
  const now = () => performance.now() - startedAt;

  recognition.onresult = (event) => {
    let interim = '';
    for (let i = event.resultIndex; i < event.results.length; i += 1) {
      const result = event.results[i];
      const text = result?.[0]?.transcript ?? '';
      if (result?.isFinal) {
        const at = now();
        handlers.onSegment({ text: text.trim(), startMs: lastEnd, endMs: at });
        lastEnd = at;
      } else {
        interim += text;
      }
    }
    handlers.onPartial(interim.trim());
  };
  recognition.onerror = (event) => handlers.onError(event.error);
  // Chrome ends a "continuous" session on its own after a silence; restart it
  // until the person actually stops.
  recognition.onend = () => {
    if (running) recognition.start();
    else settle?.();
  };
  recognition.start();

  return {
    kind: 'browser',
    wantsSamples: false,
    keepsAudio: false,
    push: () => undefined,
    positionMs: now,
    stop: () =>
      new Promise<Stopped>((resolve) => {
        running = false;
        settle = () => resolve({ recordedMs: null, transcript: null });
        recognition.stop();
      }),
    cancel: () => {
      running = false;
      recognition.stop();
    },
  };
}

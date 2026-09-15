import { findKeyword } from './command.ts';
import { openMicrophone, type Microphone, type MicrophoneHandlers } from './audio.ts';
import { modelStatus, startCapture, type CaptureSession } from './engine.ts';

/**
 * "Glyph", heard while Glyph is open.
 *
 * Matt: "While Glyph is open I should be able to say the AIs wake word in order
 * to make it start transcribing and updating notes as requested." So while the
 * list or a note is on screen (App.tsx), the microphone listens for the word
 * the recorder's commands already start with (capture/command.ts), and saying
 * it opens the recorder with what was just said, so "Glyph, add buy milk to the
 * HelloTrade note" goes straight on to the command and its "shall I?".
 *
 * Nothing leaves the phone, and speech that isn't for Glyph is not kept:
 *
 * - **Quiet costs nothing.** The microphone's level is watched in the page, and
 *   the last 1.2 seconds are held in a ring (`pace`); no model runs.
 * - **Speech is heard by the voice model**, only while it lasts: a Whisper
 *   session starts on the held second and follows the voice, and each partial
 *   is looked through for the keyword. Speech that ends (1.2 s of quiet) or runs
 *   past 7 seconds without it is dropped, samples and all.
 * - **The keyword hands over.** The session is cancelled and the open
 *   microphone, with everything since the speech began, goes to the recorder
 *   (`takeWakeHandoff`), which transcribes it again from the start as its own
 *   first words. The recorder drops what came before the keyword in that first
 *   phrase: talk that wasn't for Glyph doesn't land in a note.
 *
 * It needs the voice model already on the phone (it never starts a download)
 * and the keyword switched on. Android shows its microphone dot while it
 * listens. Pure pacing in `WakePacer`, so the thresholds are tests.
 */

/** Level (rms × 8, as the recorder's meter reads it) that counts as voice. */
export const VOICE = 0.15;
/** Chunks (200 ms each) of voice in a row before it is speech worth hearing. */
const VOICE_CHUNKS = 2;
/** Chunks of quiet that end the speech. */
const QUIET_CHUNKS = 6;
/** Chunks held before speech, so its first syllable is heard. */
const PREROLL_CHUNKS = 6;
/** The longest a stretch of speech is heard without the keyword. */
const LONGEST_CHUNKS = 35;

export type WakeStep = 'idle' | 'start' | 'hearing' | 'drop';

/** Where the listener is, chunk by chunk: waiting for voice, or hearing a stretch of speech. */
export class WakePacer {
  private voiced = 0;
  private quiet = 0;
  private heard = 0;
  hearing = false;

  /** One 200 ms chunk at `level`: what to do now. */
  step(level: number): WakeStep {
    const voice = level >= VOICE;
    if (!this.hearing) {
      this.voiced = voice ? this.voiced + 1 : 0;
      if (this.voiced < VOICE_CHUNKS) return 'idle';
      this.hearing = true;
      this.quiet = 0;
      this.heard = this.voiced;
      return 'start';
    }
    this.heard += 1;
    this.quiet = voice ? 0 : this.quiet + 1;
    if (this.quiet >= QUIET_CHUNKS || this.heard >= LONGEST_CHUNKS) {
      this.reset();
      return 'drop';
    }
    return 'hearing';
  }

  reset(): void {
    this.hearing = false;
    this.voiced = 0;
    this.quiet = 0;
    this.heard = 0;
  }
}

export interface WakeHandoff {
  mic: Microphone;
  /** Points the open microphone at the recorder's own handlers. */
  rebind(handlers: MicrophoneHandlers): void;
  /** Everything since the speech began, keyword included, to transcribe first. */
  preroll: Float32Array[];
}

let handoff: WakeHandoff | null = null;

/**
 * The listener letting go of the voice model. Whisper runs one session at a
 * time, and a listener stopped while its session was still starting cancels it
 * when it arrives, which could be after the recorder has started its own and
 * take that one down instead. So the recorder waits for this first.
 */
let settled: Promise<void> = Promise.resolve();

/** Resolves once no listener holds or is starting a voice model session. */
export function wakeSettled(): Promise<void> {
  return settled;
}

/** The microphone and words the keyword left for the recorder, once. */
export function takeWakeHandoff(): WakeHandoff | null {
  const taken = handoff;
  handoff = null;
  return taken;
}

export interface WakeListener {
  stop(): void;
}

/**
 * Listens until stopped or until the keyword, which calls `onWake` with the
 * hand-over waiting. Resolves null, doing nothing, when there is no voice model
 * on the phone or no microphone.
 */
export async function listenForWakeWord(onWake: () => void): Promise<WakeListener | null> {
  const model = await modelStatus().catch(() => null);
  if (!model?.present) return null;

  let stopped = false;
  let woke = false;
  const pacer = new WakePacer();
  const ring: Float32Array[] = [];
  let speech: Float32Array[] = [];
  let session: CaptureSession | null = null;
  let starting = false;
  let current: MicrophoneHandlers | null = null;

  /** The session being opened, while it is, so a stop can wait for it and cancel it. */
  let opening: Promise<CaptureSession> | null = null;

  const drop = (): Promise<void> => {
    const was = session;
    session = null;
    speech = [];
    return Promise.resolve(was?.cancel());
  };

  const wake = async (mic: Microphone) => {
    if (woke || stopped) return;
    woke = true;
    const heard = speech;
    const was = session;
    session = null;
    // The session is let go before the recorder starts its own: one Whisper session at a time.
    const starting = opening;
    const letGo = Promise.all([Promise.resolve(was?.cancel()), starting ? starting.then((opened) => opened.cancel()).catch(() => undefined) : undefined]).then(() => undefined);
    settled = letGo;
    await letGo;
    handoff = {
      mic,
      rebind: (handlers) => {
        current = handlers;
      },
      preroll: heard,
    };
    onWake();
  };

  const heardLevel = { value: 0 };
  let mic: Microphone;
  try {
    mic = await openMicrophone({
      onLevel: (rms) => {
        if (current) current.onLevel(rms);
        else heardLevel.value = Math.min(1, rms * 8);
      },
      onChunk: (samples) => {
        if (current) {
          current.onChunk(samples);
          return;
        }
        if (stopped || woke) return;
        const step = pacer.step(heardLevel.value);
        if (step === 'idle') {
          ring.push(samples);
          if (ring.length > PREROLL_CHUNKS) ring.shift();
          return;
        }
        if (step === 'drop') {
          drop();
          return;
        }
        speech.push(samples);
        if (step === 'start') {
          speech = [...ring.splice(0), samples];
          if (starting || session) return;
          starting = true;
          opening = startCapture({
            onPartial: (text) => {
              if (text && findKeyword(text)) void wake(mic);
            },
            onSegment: (segment) => {
              if (findKeyword(segment.text)) void wake(mic);
            },
            onError: () => drop(),
          });
          void opening
            .then((opened) => {
              starting = false;
              opening = null;
              // Stopped or woken meanwhile: whoever did that cancels it, and waits for it (settled).
              if (stopped || woke) return;
              if (!pacer.hearing) return opened.cancel();
              session = opened;
              speech.forEach((held) => opened.push(held));
            })
            .catch(() => {
              starting = false;
              opening = null;
              pacer.reset();
            });
          return;
        }
        session?.push(samples);
      },
    });
  } catch {
    return null;
  }

  return {
    stop: () => {
      if (stopped) return;
      stopped = true;
      // A microphone handed to the recorder is the recorder's to stop.
      if (woke) return;
      mic.stop();
      const starting = opening;
      settled = Promise.all([drop(), starting ? starting.then((opened) => opened.cancel()).catch(() => undefined) : undefined]).then(() => undefined);
    },
  };
}

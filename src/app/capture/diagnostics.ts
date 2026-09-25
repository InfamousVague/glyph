import type { EngineKind } from './engine.ts';

/**
 * What the recorder's pipeline has actually done, counted where it happens (useCaptureSession.ts) and copied to the
 * screen a few times a second.
 *
 * The line it makes is essential: the first real capture on the Fold transcribed nothing and said "Listening" the
 * whole time, because an error during listening was stored and never shown. "Heard 8.2 s · 0 phrases" and "heard
 * 0.0 s" point at different halves of the chain - the microphone, or the model - which is the whole diagnosis without
 * a debugger attached. A tap on the top line shows it; a capture that has heard a while and made nothing of it, or has
 * had an error, shows it without being asked.
 */

export interface Diagnostics {
  /** Samples the microphone handed over, at 16 kHz. */
  heardSamples: number;
  /** The rate the microphone really ran at, before resampling; null until it opened. */
  deviceRate: number | null;
  /** Guesses at words not yet committed. */
  partials: number;
  /** Phrases committed. */
  segments: number;
  errors: number;
  lastError: string | null;
}

export const EMPTY_DIAGNOSTICS: Diagnostics = {
  heardSamples: 0,
  deviceRate: null,
  partials: 0,
  segments: 0,
  errors: 0,
  lastError: null,
};

/** Which engine is listening, in words a person can tell apart: a real on-device transcription from a fallback. */
export const ENGINE_LABEL: Record<EngineKind, string> = {
  whisper: 'On-device Whisper',
  browser: 'Browser speech recognition',
  simulated: 'Simulated voice',
};

/** "heard 8.2 s at 48 kHz · 3 guesses · 1 phrase", plus the last error if there is one. */
export function countsLine(d: Diagnostics): string {
  const parts = [`heard ${(d.heardSamples / 16_000).toFixed(1)} s${d.deviceRate ? ` at ${Math.round(d.deviceRate / 1000)} kHz` : ''}`];
  parts.push(`${d.partials} ${d.partials === 1 ? 'guess' : 'guesses'}`);
  parts.push(`${d.segments} ${d.segments === 1 ? 'phrase' : 'phrases'}`);
  if (d.errors) parts.push(`${d.errors} ${d.errors === 1 ? 'error' : 'errors'}: ${d.lastError ?? ''}`);
  return parts.join(' · ');
}

/** Whisper has heard more than eight seconds and made no guess and no phrase of it: the capture worth explaining unasked. */
export function soundsSilent(engine: EngineKind | null, d: Diagnostics): boolean {
  return engine === 'whisper' && d.heardSamples > 8 * 16_000 && !d.partials && !d.segments;
}

/** The whole line: the engine, then what the pipeline has done. */
export function diagnosticsLine(engine: EngineKind | null, d: Diagnostics): string {
  return [engine ? ENGINE_LABEL[engine] : null, countsLine(d)].filter(Boolean).join(' · ');
}

import { useEffect, useRef, useState, type RefObject } from 'react';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { isTauri } from '../core/tauri.ts';
import { openMicrophone, type Microphone, type MicrophoneHandlers } from './audio.ts';
import { EMPTY_DIAGNOSTICS, type Diagnostics } from './diagnostics.ts';
import { startCapture, type CaptureSession, type EngineKind } from './engine.ts';
import type { Segment } from './markdown.ts';

/**
 * The recorder's microphone and transcriber, opened once per mount in the order that keeps a voice note's first
 * words.
 *
 * Opened by a held side key, so everything here is ordered around one promise: the microphone is listening before
 * anything else is ready. It is opened first, the model loads while it listens, and samples captured in the meantime
 * are held and replayed rather than dropped - the first words of a voice note are usually its subject, and a recorder
 * that needs a second to warm up loses exactly them. A start that is called off (React's development double start, or
 * the screen closed at once) stops its own microphone rather than leaving it feeding the next start's session.
 *
 * What was heard goes to `events`, always the newest render's; what the pipeline did is counted in `counts` for the
 * diagnostics line (diagnostics.ts). The screen stops or cancels the session itself at Done and Discard, after which
 * `isFinished` answers true; a screen unmounted without either cancels it here.
 */

export type Phase = 'starting' | 'listening' | 'finishing' | 'failed';

export interface SessionEvents {
  /** A guess at the words not yet committed; '' when it clears. */
  onPartial(text: string): void;
  /** A committed phrase. */
  onSegment(segment: Segment): void;
  /** The microphone's level for a chunk: `level` 0 to 1 for drawing, and the `rms` it came from. */
  onLevel(level: number, rms: number): void;
}

export interface CaptureSessionState {
  phase: Phase;
  setPhase(phase: Phase): void;
  /** Which engine is listening, once one is. */
  engine: EngineKind | null;
  /** The voice model's download, while one is under way. */
  download: { received: number; total: number } | null;
  error: string | null;
  setError(error: string | null): void;
  session: RefObject<CaptureSession | null>;
  microphone: RefObject<Microphone | null>;
  counts: RefObject<Diagnostics>;
}

export function useCaptureSession({
  fromAssistant,
  isFinished,
  events,
}: {
  /** Opened by the side key, where the OS has already buzzed: no buzz of its own as it starts. */
  fromAssistant: boolean;
  /** Whether Done or Discard has begun, and so owns stopping the session. */
  isFinished: () => boolean;
  events: SessionEvents;
}): CaptureSessionState {
  const [phase, setPhase] = useState<Phase>('starting');
  const [engine, setEngine] = useState<EngineKind | null>(null);
  const [download, setDownload] = useState<{ received: number; total: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const session = useRef<CaptureSession | null>(null);
  const microphone = useRef<Microphone | null>(null);
  const counts = useRef<Diagnostics>({ ...EMPTY_DIAGNOSTICS });
  const latest = useRef({ events, isFinished });
  latest.current = { events, isFinished };

  useEffect(() => {
    let cancelled = false;
    const held: Float32Array[] = [];

    async function start() {
      const simulate = new URLSearchParams(window.location.search).has('simulate');
      try {
        if (isTauri() && !simulate) {
          const handlers: MicrophoneHandlers = {
            onChunk: (samples) => {
              // A start that was called off keeps nothing it hears (see the microphone opening below).
              if (cancelled) return;
              counts.current.heardSamples += samples.length;
              if (session.current) session.current.push(samples);
              else held.push(samples);
            },
            // Five a second, straight to the screen: too many for React renders of a meter nobody reads precisely.
            onLevel: (rms) => latest.current.events.onLevel(Math.min(1, rms * 8), rms),
          };
          const opened = await openMicrophone(handlers);
          // Called off while the microphone was opening (React's development double start, or the screen closed at
          // once): this start's microphone goes, rather than living on unowned and feeding the next start's session
          // a second copy of every chunk, interleaved - a take that plays back choppy at half speed, and that the
          // voice model hears as nonsense.
          if (cancelled) {
            opened.stop();
            return;
          }
          microphone.current = opened;
          counts.current.deviceRate = opened.deviceRate;
          console.info(`[glyph] microphone open at ${opened.deviceRate} Hz, context ${opened.state()}`);
        }
        const started = await startCapture({
          onPartial: (text) => {
            if (text) counts.current.partials += 1;
            latest.current.events.onPartial(text);
          },
          onSegment: (segment) => {
            counts.current.segments += 1;
            counts.current.lastError = null;
            latest.current.events.onSegment(segment);
          },
          onError: (message) => {
            counts.current.errors += 1;
            counts.current.lastError = message;
            console.warn('[glyph] capture error:', message);
            setError(message);
          },
          onModelProgress: (received, total) => setDownload({ received, total }),
        });
        if (cancelled) {
          started.cancel();
          microphone.current?.stop();
          return;
        }
        session.current = started;
        if (started.wantsSamples) held.splice(0).forEach((samples) => started.push(samples));
        else microphone.current?.stop();
        setEngine(started.kind);
        setDownload(null);
        setPhase('listening');
        console.info(`[glyph] capture started with ${started.kind}`);
        if (!fromAssistant) fireNativeHaptic('medium');
      } catch (failure) {
        if (cancelled) return;
        microphone.current?.stop();
        setError(failureText(failure));
        setPhase('failed');
        fireNativeHaptic('error');
      }
    }
    void start();

    return () => {
      cancelled = true;
      if (!latest.current.isFinished()) {
        session.current?.cancel();
        microphone.current?.stop();
      }
    };
    // Started once per mount; a new capture is a new mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return { phase, setPhase, engine, download, error, setError, session, microphone, counts };
}

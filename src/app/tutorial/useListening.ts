import { useCallback, useEffect, useState } from 'react';
import { openMicrophone, type Microphone } from '../capture/audio.ts';
import { startCapture, type CaptureSession } from '../capture/engine.ts';
import type { Segment } from '../capture/markdown.ts';
import { publishVoiceLevel } from '../capture/voiceLevel.ts';
import { wakeSettled } from '../capture/wakeWord.ts';

/**
 * The tutorial's ear: the recorder's own speech engine and microphone (capture/engine.ts, capture/audio.ts), kept
 * open for the whole tutorial so each lesson starts listening at once, and writing nothing. Its session is cancelled,
 * never stopped, so no recording is kept and no note is made. `clear` forgets what was heard, for the next lesson or
 * another try.
 */

export type Hearing = 'starting' | 'listening' | 'failed';

export function useListening() {
  const [state, setState] = useState<Hearing>('starting');
  const [segments, setSegments] = useState<Segment[]>([]);
  const [partial, setPartial] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [download, setDownload] = useState<{ received: number; total: number } | null>(null);

  useEffect(() => {
    let cancelled = false;
    let session: CaptureSession | null = null;
    let mic: Microphone | null = null;
    void (async () => {
      try {
        // The "Glyph" listener lets go of the voice model first: one Whisper session at a time.
        await wakeSettled();
        const started = await startCapture({
          onPartial: (text) => !cancelled && setPartial(text),
          onSegment: (segment) => {
            if (cancelled) return;
            setPartial('');
            setSegments((was) => [...was, segment]);
          },
          onError: (message) => !cancelled && setError(message),
          onModelProgress: (received, total) => !cancelled && setDownload({ received, total }),
        });
        if (cancelled) {
          void started.cancel();
          return;
        }
        session = started;
        setDownload(null);
        if (started.wantsSamples) {
          const opened = await openMicrophone({
            onChunk: (samples) => !cancelled && session?.push(samples),
            onLevel: (rms) => publishVoiceLevel(Math.min(1, rms * 8)),
          });
          if (cancelled) {
            opened.stop();
            return;
          }
          mic = opened;
        }
        setState('listening');
      } catch (failure) {
        if (cancelled) return;
        setError(failure instanceof Error ? failure.message : String(failure));
        setState('failed');
      }
    })();
    return () => {
      cancelled = true;
      mic?.stop();
      void session?.cancel();
    };
  }, []);

  const clear = useCallback(() => {
    setSegments([]);
    setPartial('');
  }, []);

  return { state, segments, partial, error, download, clear };
}

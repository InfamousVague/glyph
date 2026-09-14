import { useCallback, useEffect, useRef, useState } from 'react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { getNote, type Note } from '../core/store.ts';
import { isTauri } from '../core/tauri.ts';
import type { Segment } from '../capture/markdown.ts';

/**
 * A note's tape, playing: where the playhead is, whether it is moving, and the
 * phrases as they were spoken, for the tape at the top of a note and its
 * Transcript view (NoteTape.tsx).
 *
 * The audio is the WAV the capture kept, served by the app's own `rec` scheme
 * with byte ranges so the WebView's player can seek; the page renders the
 * `<audio>` element and hands this hook its ref. In a browser there is no Rust
 * and no file, so a clock stands in for the audio and the words follow it, so
 * the screen can be built and judged without a phone.
 */

export interface Tape {
  /** Milliseconds recorded, 0 when the note was not spoken. */
  length: number;
  at: number;
  playing: boolean;
  /** The phrases as spoken, null until they have been fetched. */
  segments: Segment[] | null;
  /** The phrase under the playhead, or -1. */
  current: number;
  problem: string | null;
  toggle: () => void;
  seek: (ms: number) => void;
  /** For the page's `<audio>`: attach it, and wire its events. */
  audio: {
    ref: React.RefObject<HTMLAudioElement | null>;
    onPlay: () => void;
    onPause: () => void;
    onEnded: () => void;
    onTimeUpdate: (event: React.SyntheticEvent<HTMLAudioElement>) => void;
    onError: () => void;
  };
  /** Only the phone has a file to play. */
  web: boolean;
}

export function useTape(note: Note): Tape {
  const length = note.recordingMs ?? 0;
  const web = !isTauri();
  const [segments, setSegments] = useState<Segment[] | null>(note.segments ?? null);
  const [playing, setPlaying] = useState(false);
  const [at, setAt] = useState(0);
  const [problem, setProblem] = useState<string | null>(null);
  const ref = useRef<HTMLAudioElement | null>(null);

  // The list leaves the phrases out of the notes it loads, so fetch them by id.
  useEffect(() => {
    if (segments || !length) return;
    let live = true;
    void getNote(note.id).then((full) => {
      if (live) setSegments(full?.segments ?? []);
    });
    return () => {
      live = false;
    };
  }, [note.id, segments, length]);

  // The browser's stand-in for the audio: a clock.
  useEffect(() => {
    if (!web || !playing) return undefined;
    const started = performance.now() - at;
    const timer = window.setInterval(() => {
      const now = performance.now() - started;
      if (now >= length) {
        setAt(0);
        setPlaying(false);
      } else setAt(now);
    }, 100);
    return () => window.clearInterval(timer);
    // The clock starts from where the playhead was when Play was pressed.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [web, playing, length]);

  // Leaving the note stops the tape.
  useEffect(() => () => ref.current?.pause(), []);

  const toggle = useCallback(() => {
    fireNativeHaptic('selection');
    setProblem(null);
    if (web) {
      setPlaying((p) => !p);
      return;
    }
    const el = ref.current;
    if (!el) return;
    if (el.paused) void el.play().catch((e: unknown) => setProblem(e instanceof Error ? e.message : String(e)));
    else el.pause();
  }, [web]);

  const seek = useCallback(
    (ms: number) => {
      setAt(ms);
      if (!web && ref.current) ref.current.currentTime = ms / 1000;
    },
    [web],
  );

  const current = segments?.findIndex((s) => at >= s.startMs && at < s.endMs) ?? -1;

  return {
    length,
    at,
    playing,
    segments,
    current,
    problem,
    toggle,
    seek,
    web,
    audio: {
      ref,
      onPlay: () => setPlaying(true),
      onPause: () => setPlaying(false),
      onEnded: () => {
        setPlaying(false);
        setAt(0);
      },
      onTimeUpdate: (event) => setAt(event.currentTarget.currentTime * 1000),
      onError: () => setProblem('This tape couldn’t be played.'),
    },
  };
}

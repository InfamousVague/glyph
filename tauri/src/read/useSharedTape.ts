import { useCallback, useEffect, useRef, useState } from 'react';
import { SharedRecording } from './shareAudio.ts';
import { wantsMore, type SharedAudio } from './meeting.ts';

/**
 * The shared meeting's tape, playing (MeetingRead.tsx): an `<audio>` over the recording as it arrives
 * (shareAudio.ts), where the playhead is, whether it plays, and how fast. The page's own copy of what the app's tape
 * is (lib/tapes/player.dart `Tape`): nothing is fetched until the first Play, or a phrase tapped, so a reader who only
 * reads the summary costs the service nothing; played to its end it rests at its start again.
 *
 * The recording plays from the first half minute that has come. The element is given the sound so far, and given more
 * while it plays within a couple of seconds of the end of what it has (`wantsMore`), or at once when it is paused, at
 * the same moment; a seek past what has come waits for it, and says so.
 */

export interface SharedTape {
  /** Where the playhead is, in ms. */
  at: number;
  playing: boolean;
  /** Whether the tape has moved since it rested at its start (lib/tapes/player.dart `Tape.started`). */
  started: boolean;
  /** Whether the reader asked for sound that has not come yet. */
  waiting: boolean;
  /** How much of the recording has come, 0 to 1, and how many ms of it can play. */
  progress: number;
  loadedMs: number;
  /** Whether a fetch of the recording has begun. */
  loading: boolean;
  failed: string | null;
  rate: number;
  toggle: () => void;
  /** Takes the tape to `ms`, and with `play` plays from there. */
  seek: (ms: number, play?: boolean) => void;
  setRate: (rate: number) => void;
}

export function useSharedTape(id: string, key: string, audio: SharedAudio, lengthMs: number, fetcher?: typeof fetch): SharedTape {
  const element = useRef<HTMLAudioElement | null>(null);
  const recording = useRef<SharedRecording | null>(null);
  /** The sound the element was last given: its address and how long it is. */
  const given = useRef<{ url: string; ms: number }>({ url: '', ms: 0 });
  /** Where the tape is to be once the sound for it has come; null where it is there. */
  const pending = useRef<number | null>(null);
  /** Whether the reader wants it playing: what a stall resumes into. */
  const wanted = useRef(false);
  const rateRef = useRef(1);
  const atRef = useRef(0);
  const [at, setAt] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [started, setStarted] = useState(false);
  const [waiting, setWaiting] = useState(false);
  const [progress, setProgress] = useState(0);
  const [loadedMs, setLoadedMs] = useState(0);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);
  const [rate, setRateState] = useState(1);
  const abort = useRef<AbortController | null>(null);

  const move = useCallback((ms: number) => {
    atRef.current = ms;
    setAt(ms);
  }, []);

  /** Gives the element the sound so far, and puts it at `ms`, playing if the reader wants it. */
  const give = useCallback((ms: number) => {
    const el = element.current;
    const sound = recording.current?.sound();
    if (!el || !sound) return;
    const old = given.current.url;
    const url = URL.createObjectURL(sound.blob);
    given.current = { url, ms: sound.ms };
    pending.current = null;
    const start = Math.min(ms, Math.max(0, sound.ms - 50));
    const ready = () => {
      el.removeEventListener('loadedmetadata', ready);
      try {
        el.currentTime = start / 1000;
      } catch {
        // Not seekable yet: it starts from the top.
      }
      el.playbackRate = rateRef.current;
      if (wanted.current) {
        setWaiting(false);
        void el.play()?.catch(() => setPlaying(false));
      }
    };
    el.addEventListener('loadedmetadata', ready);
    el.src = url;
    el.load?.();
    if (old) setTimeout(() => URL.revokeObjectURL(old), 1000);
  }, []);

  /** What a part arriving does: more to give, a stall to end, a wait to end. */
  const arrived = useCallback(() => {
    const rec = recording.current;
    if (!rec) return;
    setProgress(rec.progress);
    setLoadedMs(rec.loadedMs);
    if (rec.done) setLoading(false);
    const el = element.current;
    const want = pending.current;
    const enough = Math.min(8000, Math.max(0, lengthMs - 500));
    // A place asked for past what has come (a line tapped late in the meeting) waits for its own sound.
    if (want !== null) {
      if (rec.loadedMs > want + 1000 || rec.done) give(want);
      return;
    }
    if (!given.current.url) {
      if (rec.loadedMs >= enough || rec.done) give(atRef.current);
      return;
    }
    // Paused with more come: given it now, where it is, so a Play goes on past where it stopped.
    if (el && el.paused && !wanted.current && rec.loadedMs > given.current.ms + 250) give(atRef.current);
  }, [give, lengthMs]);

  const load = useCallback(() => {
    if (recording.current) return;
    const rec = new SharedRecording(id, key, audio, fetcher);
    recording.current = rec;
    setLoading(true);
    setFailed(null);
    const controller = new AbortController();
    abort.current = controller;
    rec.load(arrived, controller.signal).catch((failure: unknown) => {
      if (controller.signal.aborted) return;
      recording.current = null;
      given.current = { url: '', ms: 0 };
      setLoading(false);
      setWaiting(false);
      wanted.current = false;
      setFailed(failure instanceof Error ? failure.message : String(failure));
    });
  }, [id, key, audio, fetcher, arrived]);

  useEffect(() => {
    const el = typeof Audio !== 'undefined' ? new Audio() : null;
    if (!el) return undefined;
    el.preload = 'auto';
    element.current = el;
    const time = () => {
      const ms = el.currentTime * 1000;
      move(ms);
      if (ms > 0) setStarted(true);
      const rec = recording.current;
      if (rec && !el.paused && wantsMore(ms, given.current.ms, rec.loadedMs)) give(ms);
    };
    const played = () => {
      setPlaying(true);
      setStarted(true);
    };
    const paused = () => setPlaying(false);
    const ended = () => {
      const rec = recording.current;
      // The end of what it was given, with more to come: a stall, not the end.
      if (rec && !rec.done && wanted.current) {
        pending.current = given.current.ms;
        setWaiting(true);
        return;
      }
      if (rec && rec.loadedMs > given.current.ms + 250) {
        give(given.current.ms);
        return;
      }
      wanted.current = false;
      setPlaying(false);
      setStarted(false);
      move(0);
      try {
        el.currentTime = 0;
      } catch {
        // Nothing to rewind.
      }
    };
    el.addEventListener('timeupdate', time);
    el.addEventListener('play', played);
    el.addEventListener('pause', paused);
    el.addEventListener('ended', ended);
    return () => {
      el.removeEventListener('timeupdate', time);
      el.removeEventListener('play', played);
      el.removeEventListener('pause', paused);
      el.removeEventListener('ended', ended);
      el.pause?.();
      abort.current?.abort();
      if (given.current.url) URL.revokeObjectURL(given.current.url);
      element.current = null;
    };
  }, [give, move]);

  const toggle = useCallback(() => {
    const el = element.current;
    if (!el) return;
    if (wanted.current) {
      wanted.current = false;
      setWaiting(false);
      el.pause();
      return;
    }
    wanted.current = true;
    setStarted(true);
    if (!recording.current) {
      setWaiting(true);
      load();
      return;
    }
    if (!given.current.url || pending.current !== null) {
      setWaiting(true);
      return;
    }
    el.playbackRate = rateRef.current;
    void el.play()?.catch(() => {
      wanted.current = false;
      setPlaying(false);
    });
  }, [load]);

  const seek = useCallback(
    (ms: number, play = false) => {
      const el = element.current;
      const to = Math.max(0, Math.min(ms, lengthMs));
      move(to);
      setStarted(true);
      if (play) wanted.current = true;
      if (!recording.current) {
        pending.current = to;
        if (play) {
          setWaiting(true);
          load();
        }
        return;
      }
      const rec = recording.current;
      if (el && given.current.url && to < given.current.ms - 200) {
        pending.current = null;
        el.currentTime = to / 1000;
        if (wanted.current && el.paused) void el.play()?.catch(() => setPlaying(false));
      } else if (rec.loadedMs > to + 500 || rec.done) {
        give(to);
      } else {
        pending.current = to;
        if (wanted.current) setWaiting(true);
        el?.pause();
      }
    },
    [give, load, lengthMs, move],
  );

  const setRate = useCallback((next: number) => {
    rateRef.current = next;
    setRateState(next);
    if (element.current) element.current.playbackRate = next;
  }, []);

  return { at, playing, started, waiting, progress, loadedMs, loading, failed, rate, toggle, seek, setRate };
}

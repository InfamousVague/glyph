import { convertFileSrc } from '@tauri-apps/api/core';
import { answerHost } from './host.ts';
import { hasNativeGeneration } from './nativeGeneration.ts';
import { isAndroid } from './platform.ts';
import { invoke, isTauri } from './tauri.ts';

/**
 * Films in notes, on the phone they were added on (docs/DESIGN.md §141).
 *
 * A film is picked with the Photo Picker by the Android shell (media/VideoPick.kt), which copies it and makes its
 * poster, and kept by Rust (`save_video`, src-tauri/src/videos.rs): the film under `video/`, the poster among the
 * pictures. The note's line (core/videoRefs.ts) names both. The card that draws it (editor/videos.ts) plays the film
 * through the `vid` scheme, a range at a time, and asks first, with a HEAD, whether the film is on this phone at all:
 * a note synced from the phone to another, or a phone reset since, has the poster and not the film.
 *
 * All of it needs native generation 21, the binary with the picker, the scheme and the commands. A page that arrives
 * over the air on an older binary shows no "A video" row, and a video line there says to update.
 */

/** The binary generation with `pickVideo`, `save_video`, `discard_picked` and the `vid` scheme. */
export const VIDEO_GENERATION = 21;

/** The scheme films play through. RUST TWIN: src-tauri/src/videos.rs `SCHEME`, which a test here reads. */
export const VIDEO_SCHEME = 'vid';

/** What a person reads when they ask for a second film while the first is still being copied. */
export const STILL_ADDING = 'A video is still being added.';

/** A film picked and kept: its name, its poster's, its length and its size as it is watched. */
export interface PickedVideo {
  video: string;
  poster: string;
  ms: number;
  width: number;
  height: number;
}

/**
 * What the shell answers a pick with (media/VideoPick.kt `picked`, `cancelled`, `failed`), and `copying`, which it
 * says first, once a film is chosen and before the copy starts: the pick is still waiting, and the page can now say it
 * is adding the film, rather than while the picker is still up.
 */
export type VideoAnswer = { path: string; poster: string; ms: number; width: number; height: number } | { cancelled: true } | { error: string } | { copying: true };

/** The shell's JSON as the page reads it; anything else is a film that could not be read. */
export function readVideoAnswer(json: string): VideoAnswer {
  const unread = { error: 'This video can’t be read.' };
  let answer: unknown;
  try {
    answer = JSON.parse(json);
  } catch {
    return unread;
  }
  if (!answer || typeof answer !== 'object') return unread;
  const said = answer as Record<string, unknown>;
  if (said.copying === true) return { copying: true };
  if (said.cancelled === true) return { cancelled: true };
  if (typeof said.error === 'string') return { error: said.error };
  if (typeof said.path !== 'string' || typeof said.poster !== 'string') return unread;
  const number = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0);
  return { path: said.path, poster: said.poster, ms: number(said.ms), width: number(said.width), height: number(said.height) };
}

/** The one pick waiting for its film: what its answer settles, and who is told when the copying starts. */
let pending: { settle: (answer: Exclude<VideoAnswer, { copying: true }>) => void; copying?: () => void } | null = null;
let listening = false;

/** Throws away a film and its poster the shell copied, which no note will name. */
function discard(answer: { path: string; poster: string }): void {
  for (const path of [answer.path, answer.poster]) void invoke('discard_picked', { path }).catch(() => undefined);
}

/**
 * Hears the shell's `video` answers from now on: the one a pick is waiting for, and one it is not, a film picked
 * before the page reloaded, whose copies are thrown away at once rather than left for the launch sweep.
 */
export function listenForVideos(): void {
  if (listening) return;
  listening = true;
  answerHost('video', (json) => {
    const answer = readVideoAnswer(json);
    if ('copying' in answer) {
      pending?.copying?.();
      return;
    }
    const waiting = pending;
    pending = null;
    if (waiting) {
      waiting.settle(answer);
      return;
    }
    if ('path' in answer) discard(answer);
  });
}

// A page that loads while the shell still holds a film picked before a reload hears it, and lets it go.
if (typeof window !== 'undefined' && typeof window.GlyphHost?.pickVideo === 'function') listenForVideos();

/** Whether this binary can add a film: an Android binary of generation 21, whose bridge has the picker. */
export async function canAddVideos(): Promise<boolean> {
  if (!isTauri() || !isAndroid || typeof window.GlyphHost?.pickVideo !== 'function') return false;
  return hasNativeGeneration(VIDEO_GENERATION);
}

/** Where a film on this phone stands, for its card: playable, not here, on a binary too old, or elsewhere entirely. */
export type FilmHere = 'here' | 'missing' | 'update' | 'elsewhere';

/** The answers of the HEAD asked of each film, kept for the page's life: whether it is here does not change unasked. */
const asked = new Map<string, Promise<boolean>>();

/** Whether the film is on this phone: one HEAD to the app's own scheme, which reads nothing, asked once. */
function filmIsHere(name: string): Promise<boolean> {
  let answer = asked.get(name);
  if (!answer) {
    answer = fetch(videoUrl(name), { method: 'HEAD' }).then(
      (response) => response.ok,
      () => false,
    );
    asked.set(name, answer);
  }
  return answer;
}

/** A film that would not play after all (it went since it was asked about): its card says so from now on. */
export function filmGone(name: string): void {
  asked.set(name, Promise.resolve(false));
}

/**
 * Whether the film is on this phone now, asked afresh: a film that would not play is asked again before its card
 * says it is gone, since a film the WebView cannot decode, or a read that failed, is still here. One gone is
 * remembered as gone.
 */
export async function filmStillHere(name: string): Promise<boolean> {
  const here = await fetch(videoUrl(name), { method: 'HEAD' }).then(
    (response) => response.ok,
    () => false,
  );
  if (!here) filmGone(name);
  return here;
}

/**
 * Where films play at all: on an Android phone of generation 21 (`phone`), on an older Android binary (`update`), or
 * on another device, which never has a film (`elsewhere`). Nothing is asked but the generation, once per page.
 */
export async function filmsPlay(): Promise<'phone' | 'update' | 'elsewhere'> {
  if (!isTauri() || !isAndroid) return 'elsewhere';
  return (await hasNativeGeneration(VIDEO_GENERATION)) ? 'phone' : 'update';
}

/**
 * Where the film named `name` stands on this device: `here` to play, `missing` on a phone of generation 21 that has
 * not got it, `update` on an Android binary older than 21, and `elsewhere` on any other device (the Mac, a browser).
 * Nothing but the HEAD is asked, of the app's own scheme; nothing leaves the phone.
 */
export async function filmHere(name: string): Promise<FilmHere> {
  const where = await filmsPlay();
  if (where !== 'phone') return where;
  return (await filmIsHere(name)) ? 'here' : 'missing';
}

/**
 * Where a card plays a film from: `http://vid.localhost/<name>` on Android, as the `img` scheme names its pictures
 * (core/images.ts); src-tauri/src/videos.rs serves it in ranges.
 */
export function videoUrl(name: string): string {
  return convertFileSrc(name, VIDEO_SCHEME);
}

/** What a pick asks of its caller as it goes. */
export interface PickWays {
  /** Whether the film is still wanted once it has been copied: the note still open, its place still kept. */
  keep?: () => boolean;
  /** The film was chosen and its copy has started. */
  copying?: () => void;
}

/**
 * Lets the person pick a film, keeps it, and answers it; null if they chose none, or if `keep` says it is no longer
 * wanted, when its copies are thrown away rather than kept for a note that will never name them (the poster would go
 * among the pictures, which nothing sweeps). One pick at a time: a second while the first is still being copied is
 * refused, since the shell's answer does not say which pick it is for. Throws the sentence a person reads when it
 * could not be read or kept.
 */
export async function pickVideo({ keep, copying }: PickWays = {}): Promise<PickedVideo | null> {
  const bridge = window.GlyphHost;
  if (typeof bridge?.pickVideo !== 'function') throw new Error('Videos need the newest Ghost.md.');
  if (pending) throw new Error(STILL_ADDING);
  listenForVideos();
  const answer = await new Promise<Exclude<VideoAnswer, { copying: true }>>((resolve) => {
    pending = { settle: resolve, copying };
    let started: string | undefined;
    try {
      started = bridge.pickVideo?.();
    } catch {
      started = undefined;
    }
    if (started !== 'started') {
      pending = null;
      resolve({ error: started || 'The video picker did not open.' });
    }
  });
  if ('cancelled' in answer) return null;
  if ('error' in answer) throw new Error(answer.error);
  if (keep && !keep()) {
    discard(answer);
    return null;
  }
  const kept = await invoke<{ video: string; poster: string }>('save_video', { path: answer.path, poster: answer.poster });
  asked.set(kept.video, Promise.resolve(true));
  return { ...kept, ms: answer.ms, width: answer.width, height: answer.height };
}

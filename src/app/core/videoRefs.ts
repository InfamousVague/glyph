import { lineWords } from './itemSyntax.ts';

/**
 * A film written into a note's words: its poster, an ordinary picture, linked to the film, alone on its line.
 *
 *   [![video 0:12](image/<poster>.jpg)](video/<uuid>.mp4)
 *
 * The + beside the line writes one where the caret is (editor/AddList.tsx, Matt: "add a menu to add things like geotag
 * cards images videos and more"), on the phone the film was picked on, and the editor draws the card under it
 * (editor/videos.ts). The alt text is "video" and the length, as a voice memo's is (`![voice 0:08](tape:…)`,
 * core/clips.ts), so any reader shows the still and the length.
 *
 * The poster is a picture like any other: `IMAGE_REF` (core/imageRefs.ts) reads the inner `![video 0:12](image/…)`, so
 * sync, a share, the reader's download and a deleted note's clean-up carry it with no word about films. The film's
 * name is under `video/`, which no picture's pattern takes. It stays on its phone (src-tauri/src/videos.rs says why),
 * so the owner's other devices and a reader of a shared page see the still, each told so in words meant for them.
 *
 * Only the words, and nothing that reaches a device, as core/imageRefs.ts and core/placeRefs.ts are.
 */

/** A film's reference in a body: the alt, the poster's name and the film's name, as groups 1 to 3. Global. */
export const VIDEO_REF = /\[!\[([^\]\n]*)\]\(image\/([A-Za-z0-9_.-]+)\)\]\(video\/([A-Za-z0-9_-]+\.(?:mp4|m4v|mov|webm))\)/g;

/** The one form a video line's words take. */
const VIDEO_WORDS = new RegExp(`^${VIDEO_REF.source}$`);

/** A film read from a line. */
export interface VideoLine {
  /** The poster's name under `image/`. */
  poster: string;
  /** The film's name under `video/`. */
  video: string;
  /** Its length in ms, read back from the alt ("video 0:12"), or null where the alt does not say. */
  ms: number | null;
  /** The alt as written. */
  alt: string;
}

/** The film a line is, or null: a line whose words, past its quote's markers and its list lead, are exactly one reference. */
export function videoOfLine(text: string): VideoLine | null {
  const found = VIDEO_WORDS.exec(lineWords(text));
  if (!found) return null;
  const [, alt = '', poster = '', video = ''] = found;
  return { poster, video, alt, ms: lengthOf(alt) };
}

/** "0:12", "12:04" or "1:02:03": a film's length as a person reads it. At least a second, for any film at all. */
export function lengthText(ms: number): string {
  const total = Math.max(ms > 0 ? 1 : 0, Math.round(ms / 1000));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = String(total % 60).padStart(2, '0');
  return hours ? `${hours}:${String(minutes).padStart(2, '0')}:${seconds}` : `${minutes}:${seconds}`;
}

/** The length an alt says, "video 0:12" as 12000 ms, or null. */
export function lengthOf(alt: string): number | null {
  const found = /(?:^|\s)(\d+):(\d{2})(?::(\d{2}))?$/.exec(alt.trim());
  if (!found) return null;
  const [, a = '0', b = '0', c] = found;
  const seconds = c === undefined ? Number(a) * 60 + Number(b) : Number(a) * 3600 + Number(b) * 60 + Number(c);
  return seconds * 1000;
}

/** The line for a film: its poster linked to it, the alt its length. */
export function videoMarkdown(poster: string, video: string, ms: number): string {
  return `[![video ${lengthText(ms)}](image/${poster})](video/${video})`;
}

/** Every film a body names, in order, without repeats. */
export function videoNames(body: string): string[] {
  return [...new Set([...body.matchAll(VIDEO_REF)].map((found) => found[3] ?? '').filter(Boolean))];
}

import type { Segment } from './markdown.ts';

/**
 * The words a recording's last decode added, kept as one more phrase.
 *
 * `capture_stop` drains Whisper after the page has already stopped listening for phrases (engine.ts `stop`), so the
 * words at the very end of a recording - still being decoded when Done was pressed - come back only in the stop's own
 * transcript, never as a phrase. When that transcript carries on from the phrases already committed, word for word,
 * what it adds is set after them as a phrase of its own, timed from the last one to the end of the recording: the note
 * keeps its last words and the tape's transcript keeps its timing. When it disagrees with them anywhere, the phrases
 * stand as they were heard, since they are what the tape and the better words are timed by. Whether the recording was a
 * command is read from the whole transcript either way (CaptureScreen.tsx `finish`).
 */

/** A word, as it is compared: letters and digits, with an apostrophe inside one ("don't", "Sam’s"). */
const WORD = /[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/gu;

/** The words of `text`, accents and case gone: only to tell whether one transcript carries on from another. */
function wordsOf(text: string): string[] {
  return Array.from(text.matchAll(WORD), (match) => match[0].normalize('NFKD').replace(/\p{M}/gu, '').toLocaleLowerCase());
}

/** `text` after its first `count` words, as it was written, with Whisper's punctuation and casing kept. */
function afterWords(text: string, count: number): string {
  if (!count) return text.trim();
  const words = Array.from(text.matchAll(WORD));
  const end = words[count - 1]?.index;
  const last = words[count - 1]?.[0];
  if (end === undefined || !last) return '';
  return text
    .slice(end + last.length)
    .replace(/^[\s,;:!?….-]+/, '')
    .trim();
}

/**
 * `segments` with what `transcript` says past them as one more phrase, ending at `endMs`; `segments` as they were when
 * the transcript adds nothing, says something else, or there is none (the browser and simulated engines have none).
 */
export function withFinalWords(segments: readonly Segment[], transcript: string | null, endMs: number): Segment[] {
  const finalText = transcript?.trim();
  if (!finalText) return [...segments];
  const committed = wordsOf(segments.map((segment) => segment.text).join(' '));
  const finalWords = wordsOf(finalText);
  if (!finalWords.length || committed.length >= finalWords.length || !committed.every((word, index) => word === finalWords[index])) return [...segments];
  const suffix = afterWords(finalText, committed.length);
  if (!suffix) return [...segments];
  const startMs = segments.at(-1)?.endMs ?? 0;
  return [...segments, { text: suffix, startMs, endMs: Math.max(endMs, startMs + 1) }];
}

/**
 * A record per note, kept on the page under one key: what the AI remembers about each note between visits.
 *
 * Three things are kept this way - the home page's gist (format/results.ts), the run log with its Undo
 * (ai/log.ts), and the AI's marks still on a note (ai/marks.ts) - and each wrote out the same reading of its sheet
 * (an object of notes, anything else read as empty), the same copy-then-write, and the same forgetting of a note
 * that is gone. They live here once. What each record holds, and when it is written, stays with its module.
 *
 * So does the reading and writing itself: each module hands over its own read and write through core/stored.ts,
 * naming its `glyph-` key at the call. That is where core/reset.test.ts looks to prove a reset can find every key,
 * and a key passed through here instead would be one it could not see. Storage that refuses is a device that cannot
 * remember (core/stored.ts): the sheet reads as empty and a write is silence, so what the AI keeps holds for this run
 * of the app and not beyond it.
 */

export type Sheet<V> = Record<string, V>;

export interface NoteSheet<V> {
  /** Every note's record, as last kept. What it answers may be shared between readers: a change goes through `update`. */
  read(): Readonly<Sheet<V>>;
  /**
   * One note's record worked out from the one kept - `undefined` when there is none - and kept: answering `undefined`
   * takes the note's record away, and answering the record it was given leaves the sheet as it is, unwritten.
   */
  update(noteId: string, fn: (was: V | undefined) => V | undefined): void;
  /** A note is gone: so is its record. */
  forget(noteId: string): void;
}

/** A sheet as read: only an object of notes is one, and anything else another build or a half-written store left is an empty one. */
export function sheetOf<V>(value: unknown): Sheet<V> {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Sheet<V>) : {};
}

/** The sheet `read` answers and `write` keeps. */
export function noteSheet<V>(read: () => Readonly<Sheet<V>>, write: (sheet: Sheet<V>) => void): NoteSheet<V> {
  const update = (noteId: string, fn: (was: V | undefined) => V | undefined) => {
    const sheet = read();
    const was = sheet[noteId];
    const next = fn(was);
    if (next === was) return;
    // A copy: a read may be shared by every reader (core/stored.ts `readStoredShared`), and is never changed in place.
    const copy = { ...sheet };
    if (next === undefined) delete copy[noteId];
    else copy[noteId] = next;
    write(copy);
  };
  return { read, update, forget: (noteId) => update(noteId, () => undefined) };
}

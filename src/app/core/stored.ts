/**
 * The page's own memory on this device: localStorage, asked the one way the whole app asks it.
 *
 * About thirty modules keep something here - a preference, a queue, a once-flag, the place a note was left - and each
 * used to write its own try/catch round `getItem` and `setItem`, each with its own words about what a refusal means.
 * The words were the same idea every time, so it lives here once: storage that REFUSES - a private window, a full
 * quota, a webview with site data switched off, a test or a server with no window at all - is a device that cannot
 * remember, not an error. Every caller has already said what it does without a memory (the fallback it passes, or the
 * value it holds for the rest of the run), and an exception from here would stop a screen over a convenience. So a
 * read that cannot be answered is the caller's fallback, and a write that cannot be kept is silence.
 *
 * What each caller keeps, and what its fallback means, stays with the caller: this module knows nothing about any
 * key. Keys are `glyph-<thing>`, which is how a reset finds all of them (core/reset.ts); a key without the prefix is
 * one a reset would leave behind, and core/reset.test.ts fails on it.
 *
 * Values are JSON (`readStored`, `writeStored`), or plain text for the keys that have always held a bare word or
 * number (`readStoredText`, `writeStoredText`) - which is not tidiness to be undone: a build that is rolled back over
 * the air reads what the newer one wrote, so a key keeps the form it was first written in.
 */

/** What is kept under `key`: null when nothing is, undefined when storage would not answer at all. */
function held(key: string): string | null | undefined {
  try {
    return localStorage.getItem(key);
  } catch {
    // Refused (see the header): the caller decides what an unanswerable read means.
    return undefined;
  }
}

/** The text kept under `key`, or null when there is none or storage will not say. */
export function readStoredText(key: string): string | null {
  return held(key) ?? null;
}

/** Keeps `text` under `key`; null removes it. Refused, it is silence (see the header). */
export function writeStoredText(key: string, text: string | null): void {
  try {
    if (text === null) localStorage.removeItem(key);
    else localStorage.setItem(key, text);
  } catch {
    // Refused (see the header): the caller holds the value for this run, or does without it.
  }
}

/**
 * The value kept under `key` as JSON, or `fallback` when there is none, it is not JSON, or storage will not say.
 *
 * `parse` checks what was read - another build's shape, a half-written store - and answers null for a value it will
 * not have, which reads as `fallback` too; an exception inside it does the same. Without it the value is taken as it
 * is. `fallback` is answered as it was passed, so a caller that changes what it reads passes a fresh one each time.
 */
export function readStored<T>(key: string, fallback: T, parse?: (raw: unknown) => T | null): T {
  const text = held(key);
  if (text === null || text === undefined) return fallback;
  try {
    const value: unknown = JSON.parse(text);
    return parse ? (parse(value) ?? fallback) : (value as T);
  } catch {
    // Not JSON, or not a shape `parse` would have: the same as nothing kept.
    return fallback;
  }
}

/** Keeps `value` under `key` as JSON; null removes it. Refused, it is silence (see the header). */
export function writeStored(key: string, value: unknown): void {
  writeStoredText(key, value === null ? null : JSON.stringify(value));
}

/** Each key's value as last parsed, with the text it was parsed from (`readStoredShared`). */
const parsed = new Map<string, { text: string; value: unknown }>();

/**
 * `readStored`, parsing only when the text has changed since the last read of the key.
 *
 * For the keys read in hot places, where a parse per read was measured to cost (plugins/host.ts, format/results.ts).
 * The text is still asked of storage on every read, which is cheap and can never be stale however the key was
 * written. What it answers is SHARED between readers, so a caller that changes it copies it first.
 */
export function readStoredShared<T>(key: string, fallback: T, parse?: (raw: unknown) => T | null): T {
  const text = held(key);
  if (text === null || text === undefined) return fallback;
  const last = parsed.get(key);
  if (last && last.text === text) return last.value as T;
  try {
    const raw: unknown = JSON.parse(text);
    const value = parse ? parse(raw) : (raw as T);
    if (value === null) return fallback;
    parsed.set(key, { text, value });
    return value;
  } catch {
    // Not JSON, or not a shape `parse` would have: the same as nothing kept.
    return fallback;
  }
}

/** Every key kept on this device, the page's and anybody else's: for a reset. Nothing, when storage will not say. */
export function storedKeys(): string[] {
  try {
    const keys: string[] = [];
    for (let i = 0; i < localStorage.length; i += 1) {
      const key = localStorage.key(i);
      if (key !== null) keys.push(key);
    }
    return keys;
  } catch {
    // Refused (see the header): there is nothing this page can see to clear.
    return [];
  }
}

export interface StoredFlag {
  /** Whether it has been marked. */
  is(): boolean;
  /** Marks it, from now on. */
  mark(): void;
  /** Takes the mark away. */
  clear(): void;
}

/**
 * Something that happens once on a device - the guide seen, the sample note made, a migration run - remembered by a
 * key that holds anything at all once it has.
 *
 * `value` is what marking writes and what `is()` then looks for: without one, the moment it was marked (ISO), which
 * is what a dated migration keeps, and any value at all reads as marked. `unreadable` is what `is()` answers when
 * storage cannot be read at all, and it is each flag's own judgement of which mistake is cheaper - a guide shown on
 * every launch, or never; a migration run twice, or not at all - so every caller says it where the key is declared.
 */
export function storedFlag(key: string, { value, unreadable = false }: { value?: string; unreadable?: boolean } = {}): StoredFlag {
  return {
    is() {
      const text = held(key);
      if (text === undefined) return unreadable;
      return value === undefined ? text !== null : text === value;
    },
    mark() {
      writeStoredText(key, value ?? new Date().toISOString());
    },
    clear() {
      writeStoredText(key, null);
    },
  };
}

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { beforeEach, describe, expect, it, vi } from 'vitest';

/*
 * What a reset clears, and the guard that keeps it true: every key the app keeps has to be one a reset can find,
 * which is every key named `glyph-` (core/stored.ts). The list this replaced drifted because nothing failed when a
 * module added a key; this file fails instead. And the order: nothing is wiped while the device could still sync.
 */

let signedIn = false;
/** Signing out as account.ts does it, as far as a reset can see: the session gone from the page and from storage. */
const signOut = vi.fn(async () => {
  signedIn = false;
  localStorage.removeItem('glyph-account-session');
});
/** The account key a sync asks for first, so a test can hold a sync mid-run. */
const accountKey = vi.fn(async (): Promise<CryptoKey | null> => null);
vi.mock('./account/account.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./account/account.ts')>()),
  accountState: () => ({ session: signedIn ? { token: 't', handle: 'sam', accountId: 7 } : null, unlocked: signedIn }),
  signOut: () => signOut(),
  accountKey: () => accountKey(),
}));

let native = false;
/** What was true of this device when the wipe began: the one moment the order is about. */
interface AtWipe {
  signOuts: number;
  session: unknown;
  stored: string | null;
  bookkeeping: string[];
}
let atWipe: AtWipe | null = null;
let wipe: () => Promise<void> = async () => undefined;
const noteWipe = () => {
  atWipe = {
    signOuts: signOut.mock.calls.length,
    session: accountState().session,
    stored: localStorage.getItem('glyph-account-session'),
    bookkeeping: Object.keys(localStorage).filter((key) => key.startsWith('glyph-sync-')),
  };
};
const invoke = vi.fn(async (command: string): Promise<unknown> => {
  if (command === 'ota_status') return { nativeGeneration: 11 };
  if (command === 'reset_local_data') {
    noteWipe();
    return wipe();
  }
  throw new Error(`no ${command} here`);
});
vi.mock('./tauri.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./tauri.ts')>()),
  isTauri: () => native,
  invoke: (command: string) => invoke(command),
}));

const { clearPageData, forgetAccount, resetLocalData, SPARED } = await import('./reset.ts');
const { accountState } = await import('./account/account.ts');
const { syncNow } = await import('./sync/engine.ts');
const { plugins } = await import('../plugins/registry.ts');

// ---- the app's own source, read as text ------------------------------------------------------

// `import.meta.url` is the page's own under jsdom, not a file; Vitest gives the file's directory as `dirname`.
const APP = dirname(import.meta.dirname);

function sources(dir: string): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) found.push(...sources(path));
    else if (/\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name) && !entry.name.endsWith('.d.ts')) found.push(path);
  }
  return found;
}

const FILES = sources(APP).map((path) => ({ name: relative(APP, path), text: readFileSync(path, 'utf8') }));

/** The code without its comments, near enough: the prose talks about localStorage and the keys all the time. */
const codeOf = (text: string) => text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`])\/\/.*$/gm, '$1');

/** Every `'glyph-…'` the source names, and the `glyph-…${` a key is built from. */
const NAMED = new Set(FILES.flatMap(({ text }) => [...text.matchAll(/['"`](glyph-[a-z0-9-]+)['"`]/g)].map((m) => m[1]!)));
const BUILT = new Set(FILES.flatMap(({ text }) => [...text.matchAll(/`(glyph-[a-z0-9-]*)\$\{/g)].map((m) => m[1]!)));

/** The helpers a key is kept through (core/stored.ts, core/deviceFlag.ts). */
const HELPERS = ['readStored', 'readStoredShared', 'readStoredText', 'writeStored', 'writeStoredText', 'storedFlag', 'deviceFlag'];

/** The first argument of every call to a helper, file by file: the key it keeps. */
function keysPassed(name: string, text: string): string[] {
  const code = codeOf(text);
  const args: string[] = [];
  for (const match of code.matchAll(new RegExp(`\\b(?:${HELPERS.join('|')})\\b`, 'g'))) {
    let at = match.index + match[0].length;
    // Past a type argument, however nested: readStored<Record<string, Kept>>(…
    if (code[at] === '<') {
      let depth = 0;
      for (; at < code.length; at += 1) {
        if (code[at] === '<') depth += 1;
        else if (code[at] === '>' && --depth === 0) break;
      }
      at += 1;
    }
    if (code[at] !== '(') continue;
    const arg = /^\s*([^,)]+)/.exec(code.slice(at + 1))?.[1]?.trim() ?? '';
    // The helpers' own definitions take `key` and are the one place allowed to.
    if (/^key(: string)?$/.test(arg) && (name === 'core/stored.ts' || name === 'core/deviceFlag.ts')) continue;
    args.push(arg);
  }
  return args;
}

/**
 * A key argument as the text it stands for, if the file says: a literal, a template's start, a const, or a function in
 * the same file that answers one (sync's `stateKey(…)`).
 */
function resolve(arg: string, text: string): string | null {
  const literal = /^['"]([^'"]*)['"]$/.exec(arg) ?? /^`([^`$]*)/.exec(arg);
  if (literal) return literal[1]!;
  const called = /^(\w+)\(/.exec(arg)?.[1];
  if (called) return new RegExp(`\\bfunction ${called}\\([^)]*\\)[^{]*\\{\\s*return\\s*['"\`]([^'"\`$]*)`).exec(text)?.[1] ?? null;
  if (!/^\w+$/.test(arg)) return null;
  const constant = (source: string, exported: boolean) =>
    new RegExp(`\\b${exported ? 'export ' : ''}const ${arg}\\s*=\\s*['"\`]([^'"\`$]*)`).exec(source)?.[1] ?? null;
  // Named in the file, or imported from the one that exports it (WispBench's `WISP_DRAW_KEY`).
  return constant(text, false) ?? FILES.map((file) => constant(file.text, true)).find((key) => key !== null) ?? null;
}

// ---- the tests -----------------------------------------------------------------------------

beforeEach(() => {
  localStorage.clear();
  signedIn = false;
  native = false;
  atWipe = null;
  wipe = async () => undefined;
  signOut.mockClear();
  accountKey.mockClear();
  invoke.mockClear();
});

/** A device signed in to account 7, with the bookkeeping of its last sync, and some left from account 3. */
function signedInWithBookkeeping(): void {
  signedIn = true;
  localStorage.setItem('glyph-account-session', JSON.stringify({ token: 't', handle: 'sam', accountId: 7 }));
  localStorage.setItem('glyph-sync-7-notes', JSON.stringify({ cursor: 9, notes: { n1: { rev: 3, mark: 'x' } }, files: {} }));
  localStorage.setItem('glyph-sync-7-prefs', JSON.stringify({ rev: 2, seen: null }));
  localStorage.setItem('glyph-sync-3-notes', JSON.stringify({ cursor: 4, notes: { n2: { rev: 1, mark: 'y' } }, files: {} }));
}

/** A reset run to its end. jsdom cannot reload, and says so ("Not implemented: navigation") without failing. */
const reset = () => resetLocalData({ models: false });

describe('a reset', () => {
  it('clears every key the app names, and leaves developer mode, the smoke overrides and other apps’ keys', () => {
    const seeded = [...NAMED, ...[...BUILT].map((start) => `${start}7-notes`), ...plugins.storageKeys()];
    for (const key of seeded) localStorage.setItem(key, 'kept');
    localStorage.setItem('glyph-added-later', 'kept');
    localStorage.setItem('someone-else', 'kept');
    clearPageData();
    const left = Object.keys(localStorage).sort();
    expect(left).toEqual([...SPARED, 'someone-else'].sort());
  });

  it('signs out and forgets every account’s sync bookkeeping before the phone’s notes are wiped', async () => {
    native = true;
    signedInWithBookkeeping();
    await reset();
    expect(atWipe).toEqual({ signOuts: 1, session: null, stored: null, bookkeeping: [] });
  });

  it('does the same before the browser’s pictures and notes go', async () => {
    signedInWithBookkeeping();
    localStorage.setItem('glyph-notes', JSON.stringify([{ id: 'n1' }]));
    const deleteDatabase = vi.fn(() => {
      noteWipe();
      const request = {} as IDBOpenDBRequest;
      queueMicrotask(() => request.onsuccess?.call(request, new Event('success')));
      return request;
    });
    vi.stubGlobal('indexedDB', { deleteDatabase });
    try {
      await reset();
    } finally {
      vi.unstubAllGlobals();
    }
    expect(deleteDatabase).toHaveBeenCalledWith('glyph-images');
    expect(atWipe).toEqual({ signOuts: 1, session: null, stored: null, bookkeeping: [] });
    expect(localStorage.getItem('glyph-notes')).toBeNull();
  });

  it('leaves nothing that could sync the wiped notes as deletions when the native wipe fails partway', async () => {
    native = true;
    signedInWithBookkeeping();
    wipe = async () => {
      throw new Error('could not remove the recordings');
    };
    await expect(resetLocalData({ models: true })).rejects.toThrow('could not remove the recordings');
    expect(signOut).toHaveBeenCalledTimes(1);
    expect(accountState().session).toBeNull();
    expect(localStorage.getItem('glyph-account-session')).toBeNull();
    expect(Object.keys(localStorage).filter((key) => key.startsWith('glyph-sync-'))).toEqual([]);
    // The page stays up after a failure, and its syncs go on asking: signed out, one asks the service nothing.
    const fetcher = vi.fn();
    vi.stubGlobal('fetch', fetcher);
    try {
      await syncNow();
    } finally {
      vi.unstubAllGlobals();
    }
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('waits for a sync already running to finish before anything is wiped', async () => {
    native = true;
    signedInWithBookkeeping();
    let release: (key: CryptoKey | null) => void = () => undefined;
    accountKey.mockImplementationOnce(() => new Promise((resolve) => (release = resolve)));
    const running = syncNow();
    const resetting = reset();
    try {
      // Every step up to the wait is a promise already settled; a task queued now runs after all of them.
      await new Promise((resolve) => setTimeout(resolve, 0));
      expect(signOut).toHaveBeenCalledTimes(1);
      expect(atWipe).toBeNull();
    } finally {
      // Held, the sync would hold every later test's reset too.
      release(null);
      await running;
    }
    await resetting;
    expect(atWipe).toEqual({ signOuts: 1, session: null, stored: null, bookkeeping: [] });
  });

  it('wipes nothing when the device cannot sign out, so the notes and the bookkeeping still agree', async () => {
    native = true;
    signedInWithBookkeeping();
    signOut.mockImplementationOnce(async () => {
      throw new Error('IndexedDB failed');
    });
    await expect(resetLocalData({ models: false })).rejects.toThrow('Could not sign out, so nothing was reset: IndexedDB failed');
    expect(atWipe).toBeNull();
    expect(localStorage.getItem('glyph-sync-7-notes')).not.toBeNull();
    expect(localStorage.getItem('glyph-account-session')).not.toBeNull();
  });

  it('asks nothing of an account a device never signed in to', async () => {
    await forgetAccount();
    expect(signOut).not.toHaveBeenCalled();
  });

  it('spares only keys the app really keeps, so the list cannot drift the way the old one did', () => {
    const elsewhere = new Set(FILES.filter((f) => f.name !== 'core/reset.ts').flatMap(({ text }) => [...text.matchAll(/['"`](glyph-[a-z0-9-]+)['"`]/g)].map((m) => m[1]!)));
    for (const key of SPARED) expect(elsewhere).toContain(key);
  });
});

describe('every key the app keeps is one a reset can find', () => {
  it('is kept through core/stored.ts: nothing else touches browser storage', () => {
    const touching = FILES.filter(({ name, text }) => name !== 'core/stored.ts' && /\b(?:localStorage|sessionStorage)\s*[.[]/.test(codeOf(text)));
    expect(touching.map((f) => f.name)).toEqual([]);
  });

  it('is named glyph-, wherever a helper is handed one', () => {
    const wrong: string[] = [];
    const unresolved: string[] = [];
    for (const { name, text } of FILES) {
      for (const arg of keysPassed(name, text)) {
        const key = resolve(arg, text);
        if (key === null) unresolved.push(`${name}: ${arg}`);
        else if (!key.startsWith('glyph-')) wrong.push(`${name}: ${arg} = '${key}'`);
      }
    }
    expect(wrong).toEqual([]);
    // Keys handed on rather than named, each checked where it is made: the reset's own are what storage holds, found
    // by their name; sync's are `glyph-sync-<account>-<part>` (`stateKey`, resolved above); and a plugin's are its
    // manifest's, which a reset clears by name. A new entry here is a key nobody has shown a reset can find.
    expect(unresolved.sort()).toEqual([
      'core/reset.ts: key',
      'core/reset.ts: key',
      'core/sync/engine.ts: key',
      'core/sync/engine.ts: key',
      'plugins/host.ts: key',
      'plugins/host.ts: key',
      'plugins/host.ts: key',
    ]);
    expect(BUILT).toContain('glyph-sync-');
  });

  it('finds the keys it checks: a scan that sees nothing passes for the wrong reason', () => {
    const passed = FILES.flatMap(({ name, text }) => keysPassed(name, text));
    expect(passed.length).toBeGreaterThan(40);
    expect(NAMED).toContain('glyph-note-places');
    expect(NAMED).toContain('glyph-developer');
  });
});

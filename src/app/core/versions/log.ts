import { useEffect, useMemo, useRef, useState } from 'react';
import { firstChange } from './diff.ts';
import type { Version } from './file.ts';
import { versionsOf } from './record.ts';
import { VERSIONS_CHANGED } from './store.ts';

/**
 * The changes across many notes at once, for an organization's audit log (notes/OrganizationLog.tsx; Matt: "an
 * "audit log" for organizations to be able to browse history of changes across all files"): every version kept of
 * every note filed in its workspace, read from each note's versions file (file.ts, record.ts) and held here as a line
 * each - who, when, how much, the first line it changed - rather than as every version's whole text, which the log
 * reads again for the one version it opens (record.ts `useVersions`).
 */

/** One version of one note, as a line of the log. */
export interface Change {
  noteId: string;
  /** The version's place in its note's file, from 1. */
  n: number;
  /** When it was kept, in ms. */
  at: number;
  /** Who kept it: their handle, or `me` without an account. */
  by: string;
  /** The name it was given, if any. */
  label?: string;
  /** How many lines it put in and took out against the version before. */
  added: number;
  removed: number;
  /** The first line it put in or took out; null for a version of no change to the lines (a name given). */
  peek: { kind: 'add' | 'del'; text: string } | null;
  /** Its note's first version: the note created. */
  first: boolean;
}

/** A note's versions as changes, in the file's order. */
export function changesIn(noteId: string, versions: readonly Version[]): Change[] {
  return versions.map((version, i) => ({
    noteId,
    n: version.n,
    at: version.at,
    by: version.by,
    ...(version.label ? { label: version.label } : {}),
    added: version.added,
    removed: version.removed,
    peek: firstChange(versions[i - 1]?.text ?? null, version.text),
    first: version.n === 1,
  }));
}

/** Note `id`'s changes, from its versions file, and how many of the file's versions could not be read. */
export async function changesOf(id: string): Promise<{ changes: Change[]; damaged: number }> {
  const { versions, damaged } = await versionsOf(id);
  return { changes: changesIn(id, versions), damaged };
}

/** Newest first; two kept at the same moment by note, then the later version first, so the order holds from one read to the next. */
export function newestFirst(a: Change, b: Change): number {
  return b.at - a.at || a.noteId.localeCompare(b.noteId) || b.n - a.n;
}

export interface ChangesRead {
  /** Every change of every note read so far, newest first. */
  changes: Change[];
  /** How many versions, over every file, could not be read and were left out. */
  damaged: number;
  /** How many of the notes have been read, of how many: the log says so while they are coming in. */
  read: number;
  total: number;
}

type FileRead = { changes: Change[]; damaged: number };

/** How many notes' files are read at once: enough to be quick, not so many that a big workspace floods the bridge. */
const AT_ONCE = 6;

/**
 * The changes of notes `ids`, read from their versions files, a few at a time, and read again - one note at a time -
 * as any of them changes here (store.ts VERSIONS_CHANGED: a version kept, or sync bringing a file). A note that
 * leaves the set is dropped; one that joins is read. A file that cannot be read counts as a note with no changes.
 */
export function useChangesAcross(ids: readonly string[]): ChangesRead {
  const [files, setFiles] = useState<ReadonlyMap<string, FileRead>>(() => new Map());
  // What has been read, for the effect to see without running again on every read that lands.
  const have = useRef(files);
  have.current = files;
  const key = ids.join('\n');

  useEffect(() => {
    const wanted = key ? key.split('\n') : [];
    const set = new Set(wanted);
    let live = true;
    const read = async (id: string) => {
      const got = await changesOf(id).catch((): FileRead => ({ changes: [], damaged: 0 }));
      if (live) setFiles((now) => new Map(now).set(id, got));
    };
    // The notes no longer here are dropped; those not read yet are read, a few at a time, in the order they are listed.
    setFiles((now) => ([...now.keys()].every((id) => set.has(id)) ? now : new Map([...now].filter(([id]) => set.has(id)))));
    const todo = wanted.filter((id) => !have.current.has(id));
    void (async () => {
      for (let i = 0; i < todo.length && live; i += AT_ONCE) await Promise.all(todo.slice(i, i + AT_ONCE).map(read));
    })();
    const onChanged = (event: Event) => {
      const id = (event as CustomEvent<string>).detail;
      if (set.has(id)) void read(id);
    };
    window.addEventListener(VERSIONS_CHANGED, onChanged);
    return () => {
      live = false;
      window.removeEventListener(VERSIONS_CHANGED, onChanged);
    };
  }, [key]);

  return useMemo(() => {
    const wanted = key ? key.split('\n') : [];
    const changes: Change[] = [];
    let damaged = 0;
    let read = 0;
    for (const id of wanted) {
      const got = files.get(id);
      if (!got) continue;
      read += 1;
      damaged += got.damaged;
      changes.push(...got.changes);
    }
    changes.sort(newestFirst);
    return { changes, damaged, read, total: wanted.length };
  }, [files, key]);
}

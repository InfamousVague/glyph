import type { Note } from '../core/store.ts';

/**
 * Pinned notes sit in a category of their own above the rest, each group under
 * a small label. The labels only appear when there is something to tell apart:
 * with nothing pinned the list is one plain run, as it always was, and the
 * archive is never split.
 */
export function groupsOf(notes: Note[], view: 'notes' | 'archive'): { key: string; label: string | null; notes: Note[] }[] {
  const pinned = view === 'notes' ? notes.filter((n) => n.starred) : [];
  if (!pinned.length) return notes.length ? [{ key: 'all', label: null, notes }] : [];
  const others = notes.filter((n) => !n.starred);
  return [
    { key: 'pinned', label: 'Pinned', notes: pinned },
    ...(others.length ? [{ key: 'others', label: 'Others', notes: others }] : []),
  ];
}

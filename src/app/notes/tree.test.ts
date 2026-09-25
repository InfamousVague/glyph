import { beforeEach, describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { ARCHIVE_FOLDER, noteTree, readClosed, readCompact, readTrashOpen, writeClosed, writeCompact, writeTrashOpen } from './tree.ts';

describe('the notes as the sidebar shows them', () => {
  it('puts each note in its workspace, and the rest below', () => {
    const tree = noteTree([makeNote('a'), makeNote('b'), makeNote('c')], {
      list: [{ id: 'w1', name: 'Work' }, { id: 'w2', name: 'Home' }],
      of: { a: 'w1', b: 'w2' },
    });
    expect(tree.folders.map((f) => [f.name, f.notes.map((n) => n.id)])).toEqual([
      ['Work', ['a']],
      ['Home', ['b']],
    ]);
    expect(tree.loose.map((n) => n.id)).toEqual(['c']);
  });

  it('keeps an empty workspace, so it can still be filed into', () => {
    const tree = noteTree([makeNote('a')], { list: [{ id: 'w1', name: 'Work' }], of: {} });
    expect(tree.folders).toEqual([{ id: 'w1', name: 'Work', notes: [] }]);
    expect(tree.loose.map((n) => n.id)).toEqual(['a']);
  });

  it('treats a note filed in a workspace that has gone as filed in none', () => {
    const tree = noteTree([makeNote('a')], { list: [], of: { a: 'gone' } });
    expect(tree.loose.map((n) => n.id)).toEqual(['a']);
  });

  it('keeps archived notes out of the folders and in the archive', () => {
    const tree = noteTree([makeNote('a', '# a', { archivedAt: 5 }), makeNote('b')], { list: [{ id: 'w1', name: 'Work' }], of: { a: 'w1', b: 'w1' } });
    expect(tree.folders[0]?.notes.map((n) => n.id)).toEqual(['b']);
    expect(tree.archived.map((n) => n.id)).toEqual(['a']);
  });

  it('orders a folder as the list does: pinned first, then the most recent', () => {
    const tree = noteTree([makeNote('old', '# old', { updatedAt: 1 }), makeNote('new', '# new', { updatedAt: 9 }), makeNote('pin', '# pin', { updatedAt: 0, starred: true })], {
      list: [{ id: 'w1', name: 'Work' }],
      of: { old: 'w1', new: 'w1', pin: 'w1' },
    });
    expect(tree.folders[0]?.notes.map((n) => n.id)).toEqual(['pin', 'new', 'old']);
  });

  it('carries a workspace colour through', () => {
    const tree = noteTree([], { list: [{ id: 'w1', name: 'Work', hue: 'sea' }], of: {} });
    expect(tree.folders[0]?.hue).toBe('sea');
  });
});

describe('which folders are closed', () => {
  beforeEach(() => localStorage.clear());

  it('starts with only the archive closed', () => {
    expect([...readClosed()]).toEqual([ARCHIVE_FOLDER]);
  });

  it('remembers what was closed on this device', () => {
    writeClosed(new Set(['w1']));
    expect([...readClosed()]).toEqual(['w1']);
  });

  it('reads rubbish as the starting state', () => {
    localStorage.setItem('glyph-tree-closed', 'not json');
    expect([...readClosed()]).toEqual([ARCHIVE_FOLDER]);
  });
});

describe('the sidebar’s other switches, per device', () => {
  beforeEach(() => localStorage.clear());

  it('keep the trash shut and the notes drawn small until they are changed, and remember each change', () => {
    expect(readTrashOpen()).toBe(false);
    expect(readCompact()).toBe(false);
    writeTrashOpen(true);
    writeCompact(true);
    expect([readTrashOpen(), readCompact()]).toEqual([true, true]);
    expect([localStorage.getItem('glyph-tree-trash-open'), localStorage.getItem('glyph-tree-compact')]).toEqual(['1', '1']);
    writeTrashOpen(false);
    expect(readTrashOpen()).toBe(false);
    expect(localStorage.getItem('glyph-tree-trash-open')).toBe('0');
  });
});

import { describe, expect, it } from 'vitest';
import { noteTitle, type Note } from '../core/store.ts';
import { isMemo, memoBody, memosOf, memoText, withoutMemos } from './memo.ts';

const note = (id: string, body: string, updatedAt: number, archivedAt: number | null = null): Note => ({ id, body, createdAt: updatedAt, updatedAt, source: 'editor', archivedAt });

describe('a memo', () => {
  it('is a note whose front matter says so, and its words are what was written', () => {
    const body = memoBody('  Milk, and the good coffee.\nAsk Sam.  ');
    expect(body).toBe('---\nkind: memo\n---\nMilk, and the good coffee.\nAsk Sam.\n');
    expect(isMemo(body)).toBe(true);
    expect(memoText(body)).toBe('Milk, and the good coffee.\nAsk Sam.');
    // The list names it by its first words, as it names any note.
    expect(noteTitle(body)).toBe('Milk, and the good coffee.');
  });

  it('is not a note of words, a note with other front matter, or a note that mentions memos', () => {
    expect(isMemo('# Groceries\n\nkind: memo')).toBe(false);
    expect(isMemo('---\ntitle: Plans\n---\n# Plans')).toBe(false);
    expect(isMemo('---\nkind: memoir\n---\nwords')).toBe(false);
    expect(isMemo('')).toBe(false);
    expect(memoText('# Groceries\n\n- milk')).toBe('# Groceries\n\n- milk');
  });

  it('reads Obsidian’s spacing and case in the front matter', () => {
    expect(isMemo('---\nid: abc\nKind:  Memo\n---\nwords')).toBe(true);
  });
});

describe('the collection', () => {
  const memos = [note('a', memoBody('first'), 1), note('b', memoBody('second'), 3), note('c', memoBody('gone'), 5, 9)];
  const words = [note('n', '# A note', 4)];

  it('is every memo not in the archive, newest first', () => {
    expect(memosOf([...memos, ...words]).map((n) => n.id)).toEqual(['b', 'a']);
  });

  it('leaves the memos out of the notes', () => {
    expect(withoutMemos([...memos, ...words]).map((n) => n.id)).toEqual(['n']);
  });
});

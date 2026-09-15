import { describe, expect, it } from 'vitest';
import { archiveOrder, listOrder, notePreview, noteTitle, type Note } from './store.ts';

describe('the list labels', () => {
  it('titles a note by its first line, without heading marks', () => {
    expect(noteTitle('# Groceries\nmilk')).toBe('Groceries');
    expect(noteTitle('Plain first line')).toBe('Plain first line');
  });

  it('previews the next line with inline marks taken out', () => {
    expect(notePreview('Title\nSomething with **negative space** and one `strong` colour.')).toBe(
      'Something with negative space and one strong colour.',
    );
    expect(notePreview('Title\n> _quiet_ words, ~~gone~~ here')).toBe('quiet words, gone here');
    expect(notePreview('Title\nThe key is ||under the stone||.')).toBe('The key is under the stone.');
  });

  it('previews a task without its box', () => {
    expect(notePreview('# Weekend trip\n\n- [ ] Book the cabin by Friday')).toBe('Book the cabin by Friday');
    expect(notePreview('Title\n- [x] Done already')).toBe('Done already');
  });

  it('keeps underscores and asterisks that are inside words', () => {
    expect(notePreview('Title\nsnake_case and 2*3*4')).toBe('snake_case and 2*3*4');
  });

  it('skips blank lines and bare markers', () => {
    expect(notePreview('Title\n\n- \n- eggs')).toBe('eggs');
  });
});

describe('the list order', () => {
  const note = (id: string, updatedAt: number, extra: Partial<Note> = {}): Note => ({
    id,
    body: id,
    createdAt: 0,
    updatedAt,
    source: 'editor',
    ...extra,
  });

  it('puts starred notes first and hides the archived', () => {
    const notes = [note('old', 1), note('new', 3), note('starred-old', 0, { starred: true }), note('gone', 9, { archivedAt: 5 })];
    expect(listOrder(notes).map((n) => n.id)).toEqual(['starred-old', 'new', 'old']);
  });

  it('shows the archive most recently archived first', () => {
    const notes = [note('a', 1, { archivedAt: 10 }), note('b', 2, { archivedAt: 20 }), note('live', 3)];
    expect(archiveOrder(notes).map((n) => n.id)).toEqual(['b', 'a']);
  });
});

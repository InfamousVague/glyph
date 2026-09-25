import { describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { bookNotes, openTasks, pinnedNotes, recentNotes, tickedTasks } from './dashboard.ts';

describe('the home page', () => {
  const notes = [
    makeNote('a', '# A', { updatedAt: 10 }),
    makeNote('b', '# B', { updatedAt: 30, starred: true }),
    makeNote('c', '# C', { updatedAt: 20 }),
    makeNote('d', '# D', { updatedAt: 40, archivedAt: 50 }),
  ];

  it('pins and lists recent notes without showing one twice or anything archived', () => {
    expect(pinnedNotes(notes).map((n) => n.id)).toEqual(['b']);
    expect(recentNotes(notes, 5).map((n) => n.id)).toEqual(['c', 'a']);
    expect(recentNotes(notes, 1).map((n) => n.id)).toEqual(['c']);
  });

  it('gathers every unticked to-do, the note touched last first', () => {
    const tasks = openTasks([
      makeNote('old', '# Old\n- [ ] Buy milk\n- [x] Done already', { updatedAt: 1 }),
      makeNote('new', '# New\n\n1. [ ] Ship it ^ship\n* [ ] Tell Sam\n- plain bullet', { updatedAt: 2 }),
    ]);
    expect(tasks.map((t) => [t.noteId, t.line, t.text, t.at])).toEqual([
      ['new', 2, 'Ship it', 'ship'],
      ['new', 3, 'Tell Sam', undefined],
      ['old', 1, 'Buy milk', undefined],
    ]);
  });

  it('leaves out a to-do written as an example in a code fence, an empty box, and the archive', () => {
    const tasks = openTasks([
      makeNote('n', '```md\n- [ ] not a task\n```\n- [ ] \n- [ ] real', { updatedAt: 1 }),
      makeNote('gone', '- [ ] archived', { updatedAt: 2, archivedAt: 3 }),
    ]);
    expect(tasks.map((t) => t.text)).toEqual(['real']);
  });

  it('counts the ticked to-dos, leaving out examples in a fence, empty boxes and the archive', () => {
    expect(
      tickedTasks([
        makeNote('a', '- [x] Done\n- [X] Also done\n- [ ] Open\n- [x] ', { updatedAt: 1 }),
        makeNote('b', '```\n- [x] an example\n```\n1. [x] numbered', { updatedAt: 2 }),
        makeNote('gone', '- [x] archived', { updatedAt: 3, archivedAt: 4 }),
      ]),
    ).toBe(3);
    expect(tickedTasks([makeNote('c', '- [ ] only open', { updatedAt: 1 })])).toBe(0);
  });

  it('takes brackets glued to the words as words, as the note draws them (core/itemSyntax.ts)', () => {
    expect(openTasks([makeNote('n', '- [ ]Buy milk\n- [ ] Real', { updatedAt: 1 })]).map((t) => t.text)).toEqual(['Real']);
    expect(tickedTasks([makeNote('n', '- [x]Done\n- [x](https://example.com/x)', { updatedAt: 1 })])).toBe(0);
  });
});

describe('the library', () => {
  it('is the books, newest change first, the archive left out, and Recent is without them', () => {
    const notes = [
      makeNote('a', '# A plain note', { updatedAt: 5 }),
      makeNote('b', '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\n- [[A plain note]]\n', { updatedAt: 3 }),
      makeNote('c', '---\ntitle: "Old"\nbook: true\n---\n', { updatedAt: 9, archivedAt: 1 }),
      makeNote('d', '---\ntitle: "Trip"\nbook: true\n---\n', { updatedAt: 7 }),
    ];
    expect(bookNotes(notes).map((n) => n.id)).toEqual(['d', 'b']);
    expect(recentNotes(notes, 10).map((n) => n.id)).toEqual(['a']);
  });
});

import { describe, expect, it } from 'vitest';
import { bookNoteBody } from '../book/book.ts';
import { canvasNoteBody } from '../canvas/jsonCanvas.ts';
import { GUIDE_TITLE } from '../guidebook/guidebook.ts';
import { makeNote } from '../../test/notes.ts';
import { GUIDE_CHAPTER_TITLES, LIBRARY_TITLES } from '../../test/libraryTitles.ts';
import { commandCandidates } from './candidates.ts';
import { FIND, findNote, headingIn, headingsOf, nameScore, nameWords, titleKind } from './noteFind.ts';

/**
 * Matt's library as the recorder reads it: his 76 titles (the two canvases among them as the canvases they are), the
 * Guide added (its index and 44 chapters), through the same filter CaptureScreen uses (capture/candidates.ts).
 */
const library = (() => {
  const own = LIBRARY_TITLES.filter((title) => !/canvas/i.test(title)).map((title, i) => makeNote(`n${i}`, title === 'House TODOs' ? '# House TODOs\n\n- [ ] Fix the gutter\n' : `# ${title}`, { updatedAt: 1000 - i }));
  const chapters = GUIDE_CHAPTER_TITLES.map((title, i) => makeNote(`g${i}`, `# ${title}\n\nWords.`, { updatedAt: 2000 - i }));
  const index = makeNote('guide', bookNoteBody(GUIDE_TITLE, GUIDE_CHAPTER_TITLES), { updatedAt: 3000 });
  const canvases = [
    makeNote('c1', canvasNoteBody('Canvas · The tick path', { nodes: [], edges: [] }), { updatedAt: 4000 }),
    makeNote('c2', canvasNoteBody('Untitled canvas', { nodes: [], edges: [] }), { updatedAt: 4001 }),
  ];
  return commandCandidates([...own, ...chapters, index, ...canvases]);
})();

const find = (name: string, aim: { id: string; body: string } | null = null) => findNote(name, library, { aim });
const titleOf = (name: string) => {
  const found = find(name);
  return found.status === 'resolved' ? found.note.title : found.status;
};

describe('the notes a command can name', () => {
  it('leaves out the Guide’s chapters and canvases, and keeps the book and the person’s own notes', () => {
    const titles = library.map((c) => c.title);
    expect(titles).toContain('House TODOs');
    expect(titles).toContain(GUIDE_TITLE);
    expect(titles).not.toContain('Lists and to-dos');
    expect(titles).not.toContain('Untitled canvas');
    expect(titles).not.toContain('Canvas · The tick path');
  });
});

describe('one spelling of to-do, and the kind words', () => {
  it('hears every way Whisper writes to-do as one word', () => {
    for (const said of ["house to do's", 'house to-dos', 'house todos', 'house todo', 'house 2 dos', 'house two dos', 'House TODOs', 'house to dos']) {
      expect(nameWords(said), said).toMatchObject({ distinctive: ['house'], specific: ['todo'] });
    }
  });

  it('tells the words that say which note from the words that say what kind', () => {
    expect(nameWords('the house list items')).toEqual({ words: ['house', 'list', 'item'], distinctive: ['house'], specific: [], generic: ['list', 'item'] });
    expect(nameWords('my chores')).toEqual({ words: ['chore'], distinctive: [], specific: ['chore'], generic: [] });
  });

  it('reads a title’s kind for where words go in it', () => {
    expect(titleKind('House TODOs')).toBe('task');
    expect(titleKind('Chores')).toBe('task');
    expect(titleKind('Groceries')).toBe('bullet');
    expect(titleKind('Packing list')).toBe('bullet');
    expect(titleKind('Daily Life')).toBeNull();
    // By the word it ends on: about tasks is not a list of them.
    expect(titleKind('Task Management')).toBeNull();
    expect(titleKind('Task list')).toBe('task');
    expect(titleKind('Home jobs')).toBe('task');
  });

  it('never lets a kind word decide, and lets a shared one back a match up', () => {
    const house = nameWords('House TODOs');
    expect(nameScore(nameWords('house to do list'), house)).toBe(1);
    expect(nameScore(nameWords('house chores'), house)).toBeCloseTo(0.9);
    expect(nameScore(nameWords('house list'), house)).toBeGreaterThan(nameScore(nameWords('house'), house));
    expect(nameScore(nameWords('tasks'), nameWords('Task Management'))).toBe(0);
  });

  // A name that is only the start of a title is a fair pick after the keyword, and not clear without it (docs/DESIGN.md §136).
  it('is clear only for the whole of a title’s distinctive words, never for its first word alone', () => {
    const score = (said: string, title: string) => nameScore(nameWords(said), nameWords(title));
    expect(FIND.clear).toBe(0.9);
    expect(score('bank', 'Bank statements')).toBe(0.85);
    expect(score('weekend', 'Weekend trip')).toBe(0.85);
    expect(score('car', 'Car insurance')).toBe(0.85);
    expect(score('garden jobs', 'House and garden jobs')).toBe(0.85);
    expect(score('the weekend list', 'Weekend trip')).toBe(0.85);
    expect(score('house', 'House TODOs')).toBe(0.9);
    expect(score('the work list', 'Work')).toBe(0.9);
    expect(score('weekend trip', 'Weekend trip')).toBe(1);
  });
});

describe('finding the note in Matt’s library', () => {
  it('finds House TODOs however it is said', () => {
    for (const said of [
      "house to do's",
      'house to-dos',
      'house todos',
      'house todo',
      'house 2 dos',
      'house two dos',
      'house to do list',
      'house list',
      'house list items',
      'house chores',
      'house tasks',
      'house stuff',
      'household to dos',
      'house',
      'the house to-do list',
      'my house to do’s list',
    ]) {
      expect(titleOf(said), said).toBe('House TODOs');
    }
  });

  it('finds Todo by its kind words alone, with the Guide’s Lists and to-dos left out', () => {
    for (const said of ['to-do list', 'my to-do list', 'todo', 'the to do list']) expect(titleOf(said), said).toBe('Todo');
  });

  it('is unsure between titles that come as close as each other', () => {
    for (const said of ['task list', 'hello trade the book', 'signing']) expect(find(said).status, said).toBe('unsure');
    const book = find('hello trade the book');
    expect(book.status === 'unsure' ? book.candidates.map((c) => c.title).sort() : []).toEqual(['HelloTrade — The Book', 'HelloTrade: The Book']);
  });

  it('finds nothing where nothing is named, with the titles that came near', () => {
    const tasks = find('tasks');
    expect(tasks.status).toBe('missing');
    expect(tasks.status === 'missing' ? tasks.near.map((c) => c.title) : []).toContain('Task Management');
    expect(find('the moon base')).toEqual({ status: 'missing', near: [] });
    expect(find('groceries and eggs').status).toBe('missing');
    // Beside a Groceries note too: letters alone never stretch a title over more words than it has.
    const groceries = [...library, { id: 'gr', title: 'Groceries', note: { body: '# Groceries\n\n- Eggs\n' } }];
    expect(findNote('groceries', groceries)).toMatchObject({ status: 'resolved', note: { id: 'gr' } });
    expect(findNote('groceries and eggs', groceries).status).toBe('missing');
  });

  it('takes words run together or apart', () => {
    const titles = [
      { id: 'h', title: 'HelloTrade' },
      { id: 'w', title: 'Weekend trip' },
    ];
    expect(findNote('hello trade', titles)).toMatchObject({ status: 'resolved', note: { id: 'h' } });
    expect(findNote('week end trip', titles)).toMatchObject({ status: 'resolved', note: { id: 'w' } });
    expect(findNote('weekend', titles)).toMatchObject({ status: 'resolved', note: { id: 'w' } });
  });
});

describe('the note being written to', () => {
  const homeJobs = { id: 'jobs', body: '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n' };

  it('is what “the list”, “this note” and “here” mean', () => {
    for (const said of ['the list', 'this note', 'here', 'this list']) expect(find(said), said).toEqual({ status: 'current', heading: null });
  });

  it('is what a kind word alone means when that note keeps such a list', () => {
    expect(find('my to-do list', homeJobs)).toEqual({ status: 'current', heading: null });
  });

  it('is the note, under a heading, when a name is one of its headings', () => {
    expect(find('kitchen', homeJobs)).toEqual({ status: 'current', heading: 'Kitchen' });
    expect(find('the electrical list', homeJobs)).toEqual({ status: 'current', heading: 'Electrical' });
    // A note named better than any heading is still that note.
    expect(titleOf('house to-dos')).toBe('House TODOs');
    expect(findNote('house to-dos', library, { aim: homeJobs })).toMatchObject({ status: 'resolved', note: { title: 'House TODOs' } });
  });

  it('reads a board’s lanes and a note’s labels as its places, never its own title', () => {
    expect(headingsOf('# Launch\n\n```board\nTo do: a\nDoing: b\n```\n\nShopping:\n- eggs\n')).toEqual(['Shopping', 'To do', 'Doing']);
    expect(headingsOf('# Home jobs\n\n## Kitchen\n```\n## Not a heading\n```\n')).toEqual(['Kitchen']);
    // A heading named as surely as a note is found (`FIND.resolved`): a quarter of its words is not it, half is.
    const drains = '# Home jobs\n\n## Upstairs kitchen sink drains\n- [ ] Fix tap\n';
    expect(headingIn(drains, 'the sink')).toBe(false);
    expect(headingIn(drains, 'kitchen sink')).toBe(true);
    expect(headingIn('# Launch\n\n```board\nTo do: a\nDoing: b\n```\n', 'doing')).toBe(true);
    expect(headingIn('# House TODOs\n\n- [ ] Fix the gutter\n', 'the sofa')).toBe(false);
  });
});

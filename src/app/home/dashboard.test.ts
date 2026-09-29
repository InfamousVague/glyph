import { describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { bookNotes, digest, isTape, openTasks, pinnedNotes, recentNotes, startOfToday, summaryKindOf, tapedNotes, tapesWaiting, tickedTasks, touchedToday } from './dashboard.ts';
import { bookNoteBody } from '../book/book.ts';
import { GUIDE_TITLE } from '../guidebook/guidebook.ts';
import { newTemplatePageBody, templatesNotebookBody } from '../notes/ownTemplates.ts';

describe('the home page', () => {
  const notes = [
    makeNote('a', '# A', { updatedAt: 10 }),
    makeNote('b', '# B', { updatedAt: 30, starred: true }),
    makeNote('c', '# C', { updatedAt: 20 }),
    makeNote('d', '# D', { updatedAt: 40, archivedAt: 50 }),
  ];

  it('pins and lists recent notes without showing one twice or anything archived', () => {
    expect(pinnedNotes(notes).map((n) => n.id)).toEqual(['b']);
    expect(recentNotes(notes, 5, {}).map((n) => n.id)).toEqual(['c', 'a']);
    expect(recentNotes(notes, 1, {}).map((n) => n.id)).toEqual(['c']);
  });

  it('leaves a journal’s entries out of Recent, and a notebook’s pages in', () => {
    const withJournal = [
      ...notes,
      makeNote('j', '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n- [[2026-09-28 14.05]]\n', { updatedAt: 60 }),
      makeNote('e', '---\ntitle: "2026-09-28 14.05"\n---\nWalked.', { updatedAt: 70 }),
      makeNote('g', bookNoteBody('Field guide', ['Trees']), { updatedAt: 5 }),
      makeNote('t', '# Trees', { updatedAt: 80 }),
    ];
    expect(recentNotes(withJournal, 5, {}).map((n) => n.id)).toEqual(['t', 'c', 'a']);
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
    expect(recentNotes(notes, 10, {}).map((n) => n.id)).toEqual(['a']);
  });
});

describe('the shelf of tapes', () => {
  const recorded = (id: string, createdAt: number, over: Partial<ReturnType<typeof makeNote>> = {}) =>
    makeNote(id, `# ${id}`, { source: 'capture', recordingMs: 40_000, createdAt, updatedAt: createdAt, ...over });
  const none = {};

  it('is what the recorder made, the last recorded first, whatever was touched since', () => {
    const notes = [recorded('old', 10, { updatedAt: 90 }), recorded('new', 30), recorded('mid', 20)];
    expect(tapedNotes(notes, none).map((n) => n.id)).toEqual(['new', 'mid', 'old']);
  });

  it('leaves out the archive, the Guide, a typed note spoken into, and a recording whose tape was removed', () => {
    const guide = makeNote('guide', bookNoteBody(GUIDE_TITLE, ['Your first note']), { updatedAt: 50 });
    const notes = [
      recorded('kept', 5),
      recorded('gone', 6, { archivedAt: 7 }),
      guide,
      makeNote('first', '# Your first note', { source: 'capture', recordingMs: 9_000, createdAt: 8, updatedAt: 8 }),
      makeNote('typed', '# Typed then spoken', { source: 'editor', recordingMs: 12_000, createdAt: 9, updatedAt: 9 }),
      recorded('removed', 4, { recordingMs: null }),
      recorded('silent', 3, { recordingMs: 0 }),
    ];
    expect(tapedNotes(notes, none).map((n) => n.id)).toEqual(['kept']);
    expect(isTape(notes[4]!, none)).toBe(false);
  });

  it('counts a meeting as a tape whatever its source, by the meetings preference', () => {
    const meeting = makeNote('m', '# Meeting, 26 Sep 14:05', { source: 'editor', recordingMs: 3_600_000, createdAt: 40, updatedAt: 40 });
    expect(isTape(meeting, { m: 40 })).toBe(true);
    expect(isTape(meeting, none)).toBe(false);
    expect(tapedNotes([meeting, recorded('r', 30)], { m: 40 }).map((n) => n.id)).toEqual(['m', 'r']);
  });

  it('asks the queue for a meeting’s write-up for a meeting, and a recording’s for anything else', () => {
    const meeting = makeNote('m', '# Meeting', { source: 'editor', recordingMs: 3_600_000 });
    expect(summaryKindOf(meeting, { m: 40 })).toBe('meeting');
    expect(summaryKindOf(meeting, none)).toBe('recording');
    expect(summaryKindOf(recorded('r', 30), { m: 40 })).toBe('recording');
  });

  it('keeps a pinned tape on the shelf as well as in Pinned, since pinning is a deliberate act', () => {
    const pinned = recorded('p', 10, { starred: true });
    expect(tapedNotes([pinned], none).map((n) => n.id)).toEqual(['p']);
    expect(pinnedNotes([pinned]).map((n) => n.id)).toEqual(['p']);
  });

  it('puts the meeting being recorded first on the shelf, with no tape yet, and out of Recent', () => {
    const live = makeNote('live', '# Meeting, 26 Sep 14:05', { source: 'capture', createdAt: 5, updatedAt: 5 });
    const notes = [recorded('tape', 50), live, makeNote('plain', '# Plain', { updatedAt: 30 })];
    // Without the live id it is a note with no recording: Recent's, not the shelf's.
    expect(tapedNotes(notes, none).map((n) => n.id)).toEqual(['tape']);
    expect(recentNotes(notes, 10, none).map((n) => n.id)).toEqual(['plain', 'live']);
    // With it, it is first on the shelf whatever its date, and gone from Recent.
    expect(tapedNotes(notes, none, 'live').map((n) => n.id)).toEqual(['live', 'tape']);
    expect(recentNotes(notes, 10, none, 'live').map((n) => n.id)).toEqual(['plain']);
    // A live id for a note that is not here changes nothing; an archived one stays out.
    expect(tapedNotes(notes, none, 'elsewhere').map((n) => n.id)).toEqual(['tape']);
    expect(tapedNotes([{ ...live, archivedAt: 6 }], none, 'live')).toEqual([]);
    // Once it has its recording it is a tape by its own right, and is not listed twice.
    expect(tapedNotes([recorded('tape', 50), { ...live, recordingMs: 3_600_000 }], none, 'live').map((n) => n.id)).toEqual(['live', 'tape']);
  });

  it('leaves out of Recent exactly what the shelf takes, so a typed note with a tape stays in Recent', () => {
    const notes = [
      recorded('tape', 50),
      makeNote('typed', '# Typed then spoken', { source: 'editor', recordingMs: 12_000, createdAt: 40, updatedAt: 40 }),
      makeNote('plain', '# Plain', { updatedAt: 30 }),
      makeNote('meeting', '# Meeting', { source: 'editor', recordingMs: 900_000, createdAt: 20, updatedAt: 60 }),
    ];
    expect(recentNotes(notes, 10, none).map((n) => n.id)).toEqual(['meeting', 'typed', 'plain']);
    expect(recentNotes(notes, 10, { meeting: 20 }).map((n) => n.id)).toEqual(['typed', 'plain']);
    const shelf = tapedNotes(notes, { meeting: 20 }).map((n) => n.id);
    const recent = recentNotes(notes, 10, { meeting: 20 }).map((n) => n.id);
    expect(shelf.filter((id) => recent.includes(id))).toEqual([]);
    expect([...shelf, ...recent].sort()).toEqual(['meeting', 'plain', 'tape', 'typed']);
  });
});

describe('the digest', () => {
  const none = { pending: new Set<string>(), native: new Set<string>(), waiting: new Set<string>(), failed: new Set<string>(), needsModel: new Set<string>() };
  const set = (...ids: string[]) => new Set(ids);

  it('counts the notes touched since the local day began, the archive and the Guide out', () => {
    // A Wednesday at 10:30, local time.
    const now = new Date(2026, 8, 23, 10, 30).getTime();
    const midnight = new Date(2026, 8, 23, 0, 0, 0, 0).getTime();
    expect(startOfToday(now)).toBe(midnight);
    // The Guide's pages are out, as everywhere on the page, and so is its book: added this morning, it would be the
    // newest note of all, and not one the person touched.
    const guide = makeNote('guide', bookNoteBody(GUIDE_TITLE, ['Your first note']), { updatedAt: now - 60_000 });
    const notes = [
      makeNote('at-midnight', '# A', { updatedAt: midnight }),
      makeNote('just-before', '# B', { updatedAt: midnight - 1 }),
      makeNote('this-morning', '# C', { updatedAt: now - 60_000 }),
      makeNote('gone', '# D', { updatedAt: now, archivedAt: now }),
      guide,
      makeNote('first', '# Your first note', { updatedAt: now }),
    ];
    expect(touchedToday(notes, now)).toBe(2);
  });

  it('counts what is waiting on the tapes once each, working before needing a model before failed', () => {
    const tapes = ['a', 'b', 'c', 'd', 'e', 'f'].map((id) => makeNote(id, `# ${id}`, { source: 'capture', recordingMs: 40_000 }));
    const waiting = tapesWaiting(tapes, {
      refining: set('a'),
      summaries: { pending: set('b', 'e'), native: set('c'), waiting: set(), needsModel: set('d', 'e'), failed: set('d', 'f') },
    });
    expect(waiting).toEqual({ working: 4, needsModel: 1, failed: 1 });
    // A write-up waiting for the phone to charge is working, as far as the digest says: it is on its way.
    expect(tapesWaiting(tapes, { refining: set(), summaries: { ...none, waiting: set('a') } })).toEqual({ working: 1, needsModel: 0, failed: 0 });
    expect(tapesWaiting(tapes, { refining: set(), summaries: none })).toEqual({ working: 0, needsModel: 0, failed: 0 });
    // Only the tapes given: a note in a queue but not on the page is not counted.
    expect(tapesWaiting([], { refining: set('a'), summaries: none })).toEqual({ working: 0, needsModel: 0, failed: 0 });
  });

  it('says each phrase that is true, in its order, with where it goes', () => {
    expect(digest({ open: 5, waiting: { working: 2, needsModel: 1, failed: 1 }, touched: 3 })).toEqual([
      { text: '5 to-dos open', go: 'tasks' },
      { text: 'Working on 2 tapes', go: 'tapes' },
      { text: '1 tape needs a model', go: 'model' },
      { text: '1 summary didn’t come', go: 'tapes' },
      // The day's count is said, not a word: the notes it counts are all over the page, not in one group.
      { text: '3 notes touched today', go: null },
    ]);
  });

  it('speaks in the singular for one, and in the plural for more', () => {
    expect(digest({ open: 1, waiting: { working: 1, needsModel: 2, failed: 2 }, touched: 1 }).map((p) => p.text)).toEqual([
      '1 to-do open',
      'Working on 1 tape',
      '2 tapes need a model',
      '2 summaries didn’t come',
      '1 note touched today',
    ]);
  });

  it('says nothing is waiting when none of the waiting phrases are true, and leaves out a count of nothing', () => {
    expect(digest({ open: 0, waiting: { working: 0, needsModel: 0, failed: 0 }, touched: 0 })).toEqual([{ text: 'Nothing waiting on you', go: null }]);
    expect(digest({ open: 0, waiting: { working: 0, needsModel: 0, failed: 0 }, touched: 2 }).map((p) => p.text)).toEqual(['Nothing waiting on you', '2 notes touched today']);
    expect(digest({ open: 3, waiting: { working: 0, needsModel: 0, failed: 0 }, touched: 0 }).map((p) => p.text)).toEqual(['3 to-dos open']);
  });
});

describe('Ghost.md: The Guide on the home page', () => {
  const guide = makeNote('guide', bookNoteBody(GUIDE_TITLE, ['Your first note', 'Boards made of list items']), { updatedAt: 50 });
  const first = makeNote('first', '# Your first note\n\n- [ ] Book the cabin\n- [x] Call Sam', { updatedAt: 60 });
  const boards = makeNote('boards', '# Boards made of list items\n\n- [ ] Pack the coffee', { updatedAt: 70 });
  const mine = makeNote('mine', bookNoteBody('Field guide', ['Trees']), { updatedAt: 10 });
  const trees = makeNote('trees', '# Trees\n\n- [ ] Find an oak', { updatedAt: 20 });
  const own = makeNote('own', '# Groceries\n\n- [ ] Eggs', { updatedAt: 30 });
  const notes = [guide, first, boards, mine, trees, own];

  it('keeps its pages out of Recent, and a chapter of a book of one’s own in it', () => {
    expect(recentNotes(notes, 6, {}).map((n) => n.id)).toEqual(['own', 'trees']);
  });

  it('leaves its example to-dos out of the to-do list and the count of ticked ones', () => {
    expect(openTasks(notes).map((t) => t.text)).toEqual(['Eggs', 'Find an oak']);
    expect(tickedTasks(notes)).toBe(0);
  });
});

describe('your templates on the home page', () => {
  const book = makeNote('tpl', templatesNotebookBody(['A checklist', 'A walk']), { updatedAt: 90 });
  const checklist = makeNote('checklist', '---\ntitle: "A checklist"\ntemplates: page\n---\n# {{title}}\n\n- [ ] Bread\n- [x] Milk', { updatedAt: 80 });
  const walk = makeNote('walk', newTemplatePageBody('A walk'), { updatedAt: 70 });
  const own = makeNote('own', '# Groceries\n\n- [ ] Eggs', { updatedAt: 30 });
  const notes = [book, checklist, walk, own];

  it('keeps a Templates notebook’s pages out of Recent, To do, the ticked count and the notes touched today', () => {
    expect(recentNotes(notes, 6, {}).map((n) => n.id)).toEqual(['own']);
    expect(openTasks(notes).map((t) => t.text)).toEqual(['Eggs']);
    expect(tickedTasks(notes)).toBe(0);
    expect(touchedToday(notes, 100)).toBe(2);
  });
});

describe('a to-do the AI filled (docs/DESIGN.md §145)', () => {
  it('is its answer’s words on home’s To do, and a to-do holding a blank is its question’s', () => {
    const note = makeNote('tap', '# Kitchen tap\n- [x] Found the leak\n- [ ] ??Turn off the water and fit the new washer??(Qwen3.5 4B from memory, 2026-09-28. Asked: the next step)\n- [ ] {?what to buy}');
    expect(openTasks([note]).map((t) => t.text)).toEqual(['Turn off the water and fit the new washer', 'what to buy']);
  });
});

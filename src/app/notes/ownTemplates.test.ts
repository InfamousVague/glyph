import { describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { lookOf } from '../core/look.ts';
import { noteTitle } from '../core/noteTitle.ts';
import { BUILT_INS } from './noteTemplates.ts';
import {
  OWN_SENTENCE,
  isTemplatePageBody,
  isTemplatesBody,
  newTemplatePageBody,
  seedPlan,
  templateOf,
  templatePageBody,
  templatePages,
  templatesNotebookBody,
  templatesOf,
} from './ownTemplates.ts';

/**
 * Your own templates (ownTemplates.ts): a notebook found by its key, its pages in its order and each read once, a page's
 * look passed on and nothing else of its front matter, a built-in's rules kept while its words are one's, the pages
 * kept apart, and a seed that makes only what is missing.
 */

const DAY = BUILT_INS[0]!;
const MAP = BUILT_INS.find((one) => one.kind === 'map')!;
/** The six built-ins' pages, and a notebook naming them, made at `at`. */
function seeded(at = 1000, id = 'tpl') {
  const pages = BUILT_INS.map((template, i) => makeNote(`${id}-${template.kind}`, templatePageBody(template), { createdAt: at + i }));
  return [makeNote(id, templatesNotebookBody(BUILT_INS.map((one) => one.name)), { createdAt: at + 10 }), ...pages];
}

describe('the Templates notebook', () => {
  it('is found by its key beside book: true, never by its name', () => {
    const body = templatesNotebookBody(['A day']);
    expect(isTemplatesBody(body)).toBe(true);
    expect(noteTitle(body)).toBe('Templates');
    expect(isTemplatesBody(body.replace('title: "Templates"', 'title: "Starts"'))).toBe(true);
    expect(isTemplatesBody('---\ntitle: "Templates"\nbook: true\n---\n# Templates\n')).toBe(false);
    expect(isTemplatesBody('---\ntemplates: true\n---\n# Not a notebook\n')).toBe(false);
    // Said, and said yes: a notebook marked false, or a page's mark, is not one.
    expect(isTemplatesBody(body.replace('templates: true', 'templates: false'))).toBe(false);
    expect(isTemplatesBody(body.replace('templates: true', 'templates: page'))).toBe(false);
  });

  it('names a built-in’s page by its title, marks it, keeps its look beside it, and a new page leaves its heading open', () => {
    expect(templatePageBody(DAY)).toBe('---\ntitle: "A day"\ntemplates: page\n---\n# {{date:YYYY-MM-DD}}\n\n{{date}}\n\n- [ ] ');
    expect(templatePageBody(MAP)).toBe('---\ntitle: "A map at the top"\ntemplates: page\nlook: map\n---\n# {{title}}\n\n{{date}}, {{time}}.\n');
    expect(newTemplatePageBody('A walk')).toBe('---\ntitle: "A walk"\ntemplates: page\n---\n# {{title}}\n\n');
    expect(noteTitle(templatePageBody(MAP))).toBe('A map at the top');
    expect(isTemplatePageBody(templatePageBody(DAY))).toBe(true);
    expect(isTemplatePageBody('# A day\n')).toBe(false);
    expect(isTemplatePageBody(templatesNotebookBody(['A day']))).toBe(false);
  });
});

describe('the templates it holds', () => {
  it('are none without a notebook, and its pages in its index’s order with one', () => {
    expect(templatesOf([makeNote('n', '# A day')])).toBeNull();
    const notes = seeded();
    expect(templatesOf(notes)?.map((one) => one.name)).toEqual(BUILT_INS.map((one) => one.name));
    const reordered = notes.map((note) => (note.id === 'tpl' ? { ...note, body: templatesNotebookBody(['A page to read', 'A day']) } : note));
    expect(templatesOf(reordered)?.map((one) => one.name)).toEqual(['A page to read', 'A day']);
  });

  it('keep a built-in’s sentence and rules while their words are its own, and say they are yours once changed', () => {
    const notes = seeded();
    const day = templatesOf(notes)![0]!;
    expect(day).toMatchObject({ id: 'tpl-day', kind: 'day', sentence: DAY.sentence, look: null });
    const changed = notes.map((note) => (note.id === 'tpl-day' ? { ...note, body: `${note.body}Water the plants.` } : note));
    expect(templatesOf(changed)![0]).toMatchObject({ kind: undefined, sentence: OWN_SENTENCE });
  });

  it('pass on a page’s look and its words, never its name, its place or a key the app does not know', () => {
    const page = makeNote('p', '---\ntitle: "A walk"\nlocation: 51.5074,-0.1278\nplace: "London"\nlook: map\nmood: calm\n---\n# {{title}}\n\nWhere.\n');
    const template = templateOf(page);
    expect(template.name).toBe('A walk');
    expect(template.look).toBe('map');
    expect(template.words).toBe('# {{title}}\n\nWhere.\n');
    expect(lookOf(template.words)).toBeNull();
  });

  it('read two notebooks made on two devices oldest first, and a page named twice once', () => {
    const one = seeded(1000, 'one');
    const two = [makeNote('two', templatesNotebookBody(['A walk', 'A day']), { createdAt: 5000 }), makeNote('walk', newTemplatePageBody('A walk'), { createdAt: 5001 })];
    expect(templatesOf([...two, ...one])?.map((template) => template.name)).toEqual([...BUILT_INS.map((template) => template.name), 'A walk']);
  });
});

describe('the pages kept apart', () => {
  it('are every page a Templates notebook names, and not the notebook or anything else', () => {
    const notes = [...seeded(), makeNote('mine', '# A walk\n\n- [ ] Shoes')];
    const apart = templatePages(notes);
    expect([...apart].sort()).toEqual(BUILT_INS.map((template) => `tpl-${template.kind}`).sort());
    expect(apart.has('tpl')).toBe(false);
    expect(templatePages([makeNote('mine', '# A day')]).size).toBe(0);
  });
});

describe('a note of the person’s named like a page', () => {
  const MINE = makeNote('mine', '# Notes on a book\n\n- [ ] Return Middlemarch to the library', { createdAt: 500 });

  it('is never taken for the page: the seed makes the page beside it, and the card is the page’s', () => {
    const plan = seedPlan([MINE]);
    expect('pages' in plan && plan.pages.map((one) => one.kind)).toEqual(['day', 'meeting', 'checklist', 'book', 'map', 'reading']);
    const notes = [...seeded(), MINE];
    expect(templatesOf(notes)?.find((one) => one.name === 'Notes on a book')).toMatchObject({ id: 'tpl-book', kind: 'book' });
    expect(templatePages(notes).has('mine')).toBe(false);
  });

  it('stays the person’s when it is newer than the page, and the page stays apart', () => {
    const later = { ...MINE, createdAt: 9000 };
    const notes = [later, ...seeded()];
    expect(templatesOf(notes)?.find((one) => one.name === 'Notes on a book')?.id).toBe('tpl-book');
    const apart = templatePages(notes);
    expect(apart.has('mine')).toBe(false);
    expect(apart.has('tpl-book')).toBe(true);
  });

  it('keeps every page of a name apart, as two devices’ seeds leave them', () => {
    const notes = [...seeded(1000, 'one'), ...seeded(5000, 'two')];
    const apart = templatePages(notes);
    expect(apart.has('one-day') && apart.has('two-day')).toBe(true);
    // The cards are the older notebook's pages, each name once.
    expect(templatesOf(notes)?.filter((one) => one.name === 'A day').map((one) => one.id)).toEqual(['one-day']);
  });
});

describe('the seed', () => {
  it('opens a notebook there is, makes all six and the notebook the first time, and only what is missing after a cut', () => {
    const notes = seeded();
    expect(seedPlan(notes)).toEqual({ open: notes[0] });
    const first = seedPlan([]);
    expect('pages' in first && first.pages.map((one) => one.kind)).toEqual(['day', 'meeting', 'checklist', 'book', 'map', 'reading']);
    // Cut short after three pages: those are there, so only the rest and the notebook.
    const cut = seeded().slice(1, 4);
    const again = seedPlan(cut);
    expect('pages' in again && again.pages.map((one) => one.kind)).toEqual(['book', 'map', 'reading']);
    expect('pages' in again && again.index).toBe(templatesNotebookBody(BUILT_INS.map((one) => one.name)));
  });
});

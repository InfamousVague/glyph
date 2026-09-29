import { bookNoteBody, chaptersOf, isBookBody } from '../book/book.ts';
import { frontMatterValue, quotedTitle, withFrontMatterValue } from '../core/frontMatter.ts';
import { lookOf, withLook } from '../core/look.ts';
import { noteTitle } from '../core/noteTitle.ts';
import type { Note } from '../core/store.ts';
import { titleKey } from '../core/titleKey.ts';
import { wordsOf } from '../core/untouched.ts';
import { BUILT_INS, type NoteTemplate } from './noteTemplates.ts';

/**
 * Your own templates (docs/DESIGN.md §144, slice 2): the templates a new note's blank page offers, kept as notes, the
 * pages of a notebook called Templates. Matt chose notes in a notebook over Settings: Settings sync as one sealed blob,
 * last writer wins, and Claude reads notes only. Notes sync note by note, are searched, are what Obsidian's templates
 * folder is, and are changed in the editor they will be used in.
 *
 * **The notebook** is found by its key, `templates: true` beside `book: true`, never by its name, so it can be renamed.
 * The blank page's last card, Your templates, makes it the first time, with the six built-ins as its pages (the pages
 * first, then the index, as the Guide is added, so a second press after a first one cut short makes only what is
 * missing), and opens it. From then on the blank page's cards are its pages, in its index's order: two made on two
 * devices are read oldest first, and a page named twice is offered once.
 *
 * **A page** is named by its `title:`, since its first line is the template's own heading, `# {{title}}`; its words
 * after the front matter are the template. Only `look:` passes from a page to a note made from it: its `title:`, a
 * `location:` and `place:` from where it was written, and any key the app does not know stay with the page, so a page
 * written where it was tagged never hands its place to every note made from it. A page whose words are still a built-in's
 * says that one's sentence and keeps its rules (A day's taken name, A map at the top's place); any other says
 * `One of your own.` A notebook's Add a page makes a page a template can be written in.
 *
 * The pages stay out of Recent, To do, the ticked count, the notes touched today, what a spoken command can name, and
 * the palette's list before anything is typed (`templatePages`), as the Guide's and a journal's entries do. The costs:
 * seven notes appear and sync, and a device on 1.9.0 shows the pages in Recent the day they are made, with their
 * `{{date}}` as it is, until the update reaches it. Pure.
 */

/** The notebook's name when it is made. It is found by its key, so a new name is kept. */
export const TEMPLATES_TITLE = 'Templates';
/** A page's sentence when its words are its own. */
export const OWN_SENTENCE = 'One of your own.';
/** The Your templates card's sentence. */
export const YOUR_TEMPLATES_SENTENCE = 'Change these or write your own. They are notes in a notebook.';

const said = (value: string | null) => value !== null && /^(true|yes)$/i.test(value);

/** Whether a note is a Templates notebook: `templates: true` beside `book: true`. */
export function isTemplatesBody(body: string): boolean {
  return isBookBody(body) && said(frontMatterValue(body, 'templates'));
}

/** A new Templates notebook's body, its pages named in order. */
export function templatesNotebookBody(pages: readonly string[]): string {
  return withFrontMatterValue(bookNoteBody(TEMPLATES_TITLE, pages), 'templates', 'true');
}

/** A built-in's page: its name as its `title:`, its look beside it, and its words. */
export function templatePageBody(template: NoteTemplate): string {
  const named = `---\ntitle: ${quotedTitle(template.name, template.name)}\n---\n${template.words}`;
  return template.look ? withLook(named, template.look) : named;
}

/** A page added to the notebook by name: its heading left open for the name a note is given. */
export function newTemplatePageBody(name: string): string {
  return `---\ntitle: ${quotedTitle(name, 'A template')}\n---\n# {{title}}\n\n`;
}

/** The Templates notebooks, oldest first. */
function notebooks(notes: readonly Note[]): Note[] {
  return notes.filter((note) => !note.archivedAt && isTemplatesBody(note.body)).sort((a, b) => a.createdAt - b.createdAt);
}

/** The notes by their title's key, the first of any two that share one, less the notebooks themselves. */
function byTitle(notes: readonly Note[]): Map<string, Note> {
  const map = new Map<string, Note>();
  for (const note of notes) {
    if (note.archivedAt || isBookBody(note.body)) continue;
    const key = titleKey(noteTitle(note.body));
    if (key && !map.has(key)) map.set(key, note);
  }
  return map;
}

/** A page as a template: its name, its words after the front matter, and its look alone; a built-in's rules where its words are one's. */
export function templateOf(page: Note): NoteTemplate {
  const words = wordsOf(page.body);
  const look = lookOf(page.body);
  const builtIn = BUILT_INS.find((one) => one.words.trim() === words.trim() && one.look === look);
  return { id: page.id, kind: builtIn?.kind, name: noteTitle(page.body) || 'A template', sentence: builtIn?.sentence ?? OWN_SENTENCE, words, look };
}

/** The templates the blank page offers from your notebook, in its order; null where there is no Templates notebook. */
export function templatesOf(notes: readonly Note[]): NoteTemplate[] | null {
  const books = notebooks(notes);
  if (!books.length) return null;
  const pages = byTitle(notes);
  const seen = new Set<string>();
  const out: NoteTemplate[] = [];
  for (const book of books) {
    for (const chapter of chaptersOf(book.body)) {
      const key = titleKey(chapter.title);
      const page = pages.get(key);
      if (!key || seen.has(key) || !page) continue;
      seen.add(key);
      out.push(templateOf(page));
    }
  }
  return out;
}

/** The notes a Templates notebook's index names: its pages, kept out of the lists a person's own notes are in. */
export function templatePages(notes: readonly Note[]): Set<string> {
  const ids = new Set<string>();
  const books = notebooks(notes);
  if (!books.length) return ids;
  const pages = byTitle(notes);
  for (const book of books) {
    for (const chapter of chaptersOf(book.body)) {
      const page = pages.get(titleKey(chapter.title));
      if (page) ids.add(page.id);
    }
  }
  return ids;
}

/**
 * What Your templates still has to make: the notebook to open where there is one, or the built-ins' pages whose name
 * no note has yet, and the notebook. A first press cut short by the phone leaves pages and no notebook: the next makes
 * only the notebook, naming the pages already there.
 */
export function seedPlan(notes: readonly Note[]): { open: Note } | { pages: NoteTemplate[]; index: string } {
  const book = notebooks(notes)[0];
  if (book) return { open: book };
  const pages = byTitle(notes);
  return { pages: BUILT_INS.filter((template) => !pages.has(titleKey(template.name))), index: templatesNotebookBody(BUILT_INS.map((template) => template.name)) };
}

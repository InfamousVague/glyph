import { bookNoteBody, chaptersOf, isBookBody } from '../book/book.ts';
import { frontMatterEnd, frontMatterValue, quotedTitle, withFrontMatterValue } from '../core/frontMatter.ts';
import { lookOf, withLook } from '../core/look.ts';
import { noteTitle } from '../core/noteTitle.ts';
import { isTicket, propertiesOf, TICKET_PROPERTIES } from '../core/properties.ts';
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
 * **A page is marked**, `templates: page`, by the seed and by Add a page in the notebook, and only a marked note is
 * ever a page: a chapter of the index is the marked note of its name. Found by name alone, a note of the person's that
 * shared a page's name was taken for the page (found in review): a note `# Notes on a book` holding a to-do, there
 * before the first press, was made a page, its to-do gone from home and its words a card. So the seed makes every
 * page no marked note has, whatever the person's notes are called, and a note named like a page later stays theirs.
 * The same key as the notebook's, so Claude's rewrite keeps it (mcp/server.ts). A note of the person's put in the
 * index by hand is a line of the notebook's and not a template, since nothing marks it.
 *
 * **A page** is named by its `title:`, since its first line is the template's own heading, `# {{title}}`; its words
 * after the front matter are the template. Only `look:` passes from a page to a note made from it: its `title:`, a
 * `location:` and `place:` from where it was written, and any key the app does not know stay with the page, so a page
 * written where it was tagged never hands its place to every note made from it. A ticket's page passes its ticket's keys
 * too (docs/DESIGN.md §157): a Bug report's `type: ticket`, its status and its `id: "{{next-id}}"` are what make the
 * note it makes a ticket, so they go with the words, in a block of their own. The page is drawn as the ticket it makes,
 * with no key of its own, since `{{next-id}}` is none. A page whose words are still a built-in's
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

/** Whether a note is a template's page: marked `templates: page`, and not a notebook. */
export function isTemplatePageBody(body: string): boolean {
  return !isBookBody(body) && /^page$/i.test(frontMatterValue(body, 'templates') ?? '');
}

/** A new Templates notebook's body, its pages named in order. */
export function templatesNotebookBody(pages: readonly string[]): string {
  return withFrontMatterValue(bookNoteBody(TEMPLATES_TITLE, pages), 'templates', 'true');
}

/** A built-in's page: its name as its `title:`, its mark, its own keys and its look beside them, and its words. */
export function templatePageBody(template: NoteTemplate): string {
  const lines = template.words.split('\n');
  const end = frontMatterEnd(lines);
  const own = lines.slice(1, Math.max(1, end - 1)).map((line) => `${line}\n`);
  const named = `---\ntitle: ${quotedTitle(template.name, template.name)}\ntemplates: page\n${own.join('')}---\n${lines.slice(end).join('\n')}`;
  return template.look ? withLook(named, template.look) : named;
}

/** The keys a ticket's page passes to the note made from it: a ticket's own (core/properties.ts), any case. */
const TICKET_KEYS = new Set<string>(TICKET_PROPERTIES.map((property) => property.key));

/** A page's ticket keys as they are written, for the block a ticket's template opens with; none for a page that is not a ticket. */
function ticketBlock(body: string): string {
  if (!isTicket(body)) return '';
  const lines = body.split('\n');
  const kept = propertiesOf(body).filter((property) => TICKET_KEYS.has(property.key.toLowerCase()));
  return kept.length ? `---\n${kept.map((property) => lines[property.line]).join('\n')}\n---\n` : '';
}

/** A page added to the notebook by name: marked, its heading left open for the name a note is given. */
export function newTemplatePageBody(name: string): string {
  return `---\ntitle: ${quotedTitle(name, 'A template')}\ntemplates: page\n---\n# {{title}}\n\n`;
}

/** The Templates notebooks, oldest first. */
function notebooks(notes: readonly Note[]): Note[] {
  return notes.filter((note) => !note.archivedAt && isTemplatesBody(note.body)).sort((a, b) => a.createdAt - b.createdAt);
}

/** The marked pages by their title's key, oldest first: never a note of the person's, whatever it is called. */
function pagesByTitle(notes: readonly Note[]): Map<string, Note[]> {
  const map = new Map<string, Note[]>();
  const pages = notes.filter((note) => !note.archivedAt && isTemplatePageBody(note.body)).sort((a, b) => a.createdAt - b.createdAt);
  for (const page of pages) {
    const key = titleKey(noteTitle(page.body));
    if (key) map.set(key, [...(map.get(key) ?? []), page]);
  }
  return map;
}

/**
 * A page as a template: its name, its words after the front matter (a ticket's keys in front of them), and its look
 * alone; a built-in's rules where its words are one's.
 */
export function templateOf(page: Note): NoteTemplate {
  const words = ticketBlock(page.body) + wordsOf(page.body);
  const look = lookOf(page.body);
  const builtIn = BUILT_INS.find((one) => one.words.trim() === words.trim() && one.look === look);
  return { id: page.id, kind: builtIn?.kind, name: noteTitle(page.body) || 'A template', sentence: builtIn?.sentence ?? OWN_SENTENCE, words, look };
}

/** The templates the blank page offers from your notebook, in its order; null where there is no Templates notebook. */
export function templatesOf(notes: readonly Note[]): NoteTemplate[] | null {
  const books = notebooks(notes);
  if (!books.length) return null;
  const pages = pagesByTitle(notes);
  const seen = new Set<string>();
  const out: NoteTemplate[] = [];
  for (const book of books) {
    for (const chapter of chaptersOf(book.body)) {
      const key = titleKey(chapter.title);
      const page = pages.get(key)?.[0];
      if (!key || seen.has(key) || !page) continue;
      seen.add(key);
      out.push(templateOf(page));
    }
  }
  return out;
}

/**
 * The marked pages a Templates notebook's index names, kept out of the lists a person's own notes are in: every one of
 * a name, so a second device's seed leaves no page of its own in Recent.
 */
export function templatePages(notes: readonly Note[]): Set<string> {
  const ids = new Set<string>();
  const books = notebooks(notes);
  if (!books.length) return ids;
  const pages = pagesByTitle(notes);
  for (const book of books) {
    for (const chapter of chaptersOf(book.body)) {
      for (const page of pages.get(titleKey(chapter.title)) ?? []) ids.add(page.id);
    }
  }
  return ids;
}

/**
 * What Your templates still has to make: the notebook to open where there is one, or the built-ins' pages no marked
 * page has made yet, and the notebook. A first press cut short by the phone leaves pages and no notebook: the next
 * makes only the notebook, naming the pages already there. A note of the person's by a page's name is not a page, so
 * the seed makes that page beside it.
 */
export function seedPlan(notes: readonly Note[]): { open: Note } | { pages: NoteTemplate[]; index: string } {
  const book = notebooks(notes)[0];
  if (book) return { open: book };
  const pages = pagesByTitle(notes);
  return { pages: BUILT_INS.filter((template) => !pages.has(titleKey(template.name))), index: templatesNotebookBody(BUILT_INS.map((template) => template.name)) };
}

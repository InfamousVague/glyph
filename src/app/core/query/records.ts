import { chaptersOf, isBookBody } from '../../book/book.ts';
import { quietRanges } from '../blanks.ts';
import { fencedLines } from '../boards/fence.ts';
import { cardText, itemOnLine } from '../boards/items.ts';
import { isoDay } from '../days.ts';
import { frontMatterEnd } from '../frontMatter.ts';
import { itemWords } from '../itemLinks.ts';
import { taskBox } from '../itemSyntax.ts';
import { noteTitle } from '../noteTitle.ts';
import { DEFAULT_STATUSES, isTicket, issueKeyOf, propertiesOf, propertyList, statusesOf, ticketIdOf, ticketOf, type Ticket } from '../properties.ts';
import { tagsIn } from '../tags.ts';
import { fieldsOf, withoutFields, type TaskFields } from '../taskFields.ts';
import { titleKey } from '../titleKey.ts';

/**
 * What a query reads: every note as a record, and every to-do in them as a record of its own (docs/QUERIES.md,
 * docs/DESIGN.md §158). Matt asked for "notion and jira like features … like tickets and such", and a query is the
 * database view over them; this is the database.
 *
 * A note is one record, and a ticket is a note whose front matter says `type: ticket` (core/properties.ts), read with
 * its ticket's fields. A to-do is a record too: any list item with a box (core/itemSyntax.ts `taskBox`), outside the
 * front matter and fenced code, with its note, its line and its fields (core/taskFields.ts). Every reading here is the
 * shared grammar's, never a second parser of it: the box is itemSyntax's, the words itemLinks' and boards' (a mark, a
 * counter and an anchor are not what a to-do says), the fields taskFields', the properties and the ticket
 * properties', the tags core/tags.ts's outside quiet words (core/blanks.ts `quietRanges`), a notebook's pages
 * book/book.ts's. So a query reads a note the way everything else in the app reads it, and it reads a ticket or a
 * field the moment either is written, whoever wrote it.
 *
 * A note's reading depends only on its words, so it is kept by the note's id until its words change (`RecordCache`):
 * the editor builds the library on every keystroke in the open note, and every other note is read once. What depends
 * on the other notes - the notebook a note is a page of, the workflow its statuses are in, the notes its links name -
 * is put together each time, which is a lookup per note. Pure: the notes are given, and so is the cache.
 */

/** A note as a query reads it: the store's `Note` has these and more. */
export interface QueryNote {
  id: string;
  body: string;
  /** Milliseconds since the epoch. */
  createdAt: number;
  updatedAt: number;
}

/** A note, a ticket (a note with `type: ticket`), or a to-do in a note. */
export type RecordKind = 'note' | 'ticket' | 'task';

export interface QueryRecord {
  kind: RecordKind;
  noteId: string;
  /** A to-do's line in its note, counting from 0; -1 for a note. */
  line: number;
  /** A to-do's line as it is written, to find it again where the note has moved under it; '' for a note. */
  source: string;
  /** The note's title (core/noteTitle.ts): a to-do's is its note's. */
  title: string;
  /** A to-do's words as a reader shows them, its fields, mark, counters and anchor taken out; a note's words. */
  text: string;
  /** A to-do's box, ticked or not; null for a note. */
  done: boolean | null;
  /** A to-do's anchor (docs/BOARDS.md), to land on it; null where it has none, and for a note. */
  anchor: string | null;
  /** The title of the notebook the note is a page of (book/book.ts), the first where it is in several; or null. */
  notebook: string | null;
  /** The title keys of every notebook the note is a page of, for `from: [[A notebook]]`. */
  books: readonly string[];
  /** The workflow the record's status moves through: its notebook's `statuses:`, or the default. */
  workflow: readonly string[];
  /**
   * Its tags, lower case and without the `#`: a note's are every tag in its words, its front matter's `tags:` and a
   * ticket's `labels:`; a to-do's are its own words' and its note's front matter's.
   */
  tags: readonly string[];
  /** When the note was made and last changed, as days (core/days.ts). */
  created: string;
  updated: string;
  /** A note's front matter by key in lower case, its values with their quotes off; empty for a to-do. */
  props: Readonly<Record<string, string>>;
  /** A ticket's properties as core/properties.ts reads them; null for anything else. */
  ticket: Ticket | null;
  /** A to-do's fields as core/taskFields.ts reads them; null for a note. */
  fields: TaskFields | null;
  /** The ids of the notes the note's `[[links]]` name, by title or a ticket's key: for `from: [[A note]]`. */
  linksTo: ReadonlySet<string>;
  /** The title keys its `[[links]]` name, found or not: for `from: [[A note not written yet]]`. */
  linkKeys: readonly string[];
  /** What `"words"` in `from:` look through, lower case: a note's title and words, a to-do's words. */
  haystack: string;
}

/** A note in the library, as `from: [[…]]` finds one: by its title, or a ticket by its key. */
export interface LibraryNote {
  id: string;
  title: string;
  key: string;
  /** A notebook (book/book.ts): its pages are what `[[it]]` names. */
  book: boolean;
  /** A notebook's workflow, its `statuses:`; null for a note that is not a notebook. */
  statuses: readonly string[] | null;
}

/** Every record, and the notes by title and by ticket key. */
export interface Library {
  records: QueryRecord[];
  /** Each note by its title key, the first of a shared title winning, as a `[[link]]` finds it (App.tsx `titled`). */
  byTitle: ReadonlyMap<string, LibraryNote>;
  /** Each ticket by its key, `GHO-12`. */
  byTicket: ReadonlyMap<string, LibraryNote>;
}

/** A to-do as its note's words have it, before the library puts it together. */
interface ReadTask {
  line: number;
  source: string;
  text: string;
  done: boolean;
  anchor: string | null;
  fields: TaskFields;
  tags: string[];
  haystack: string;
}

/** A note as its words have it. */
interface ReadNote {
  title: string;
  key: string;
  props: Record<string, string>;
  ticket: boolean;
  ticketId: string | null;
  book: boolean;
  /** A notebook's pages, by title key. */
  chapters: string[];
  statuses: string[] | null;
  tags: string[];
  frontTags: string[];
  links: string[];
  words: string;
  haystack: string;
  tasks: ReadTask[];
}

/** Notes read, by id, kept while their words stay the same. */
export interface RecordCache {
  read: Map<string, { body: string; note: ReadNote }>;
}

export function recordCache(): RecordCache {
  return { read: new Map() };
}

/** A note link's target as a page names it: the title, a `#heading` or `|words` after it not part of it. */
const LINK = /\[\[([^\]\n|#]{1,120})(?:[#|][^\]\n]*)?\]\]/g;

/** The tags in `text` outside its quiet words, lower case, without the `#`. */
function tagsOf(text: string): string[] {
  const quiet = quietRanges(text);
  return tagsIn(text)
    .filter((tag) => !quiet.some((q) => tag.from >= q.from && tag.from < q.to))
    .map((tag) => tag.name);
}

/** Tags written as a front matter list, `tags: [bug, ui]` or `tags: bug, ui`, without their `#`, lower case. */
function listedTags(value: string | undefined): string[] {
  return propertyList(value)
    .map((tag) => tag.replace(/^#+/, '').trim().toLowerCase())
    .filter(Boolean);
}

/** Each once, in order. */
function unique(items: readonly string[]): string[] {
  return [...new Set(items)];
}

function readNote(body: string): ReadNote {
  const lines = body.split('\n');
  const front = frontMatterEnd(lines);
  const props = Object.create(null) as Record<string, string>;
  for (const property of propertiesOf(body)) {
    const key = property.key.toLowerCase();
    if (!Object.hasOwn(props, key)) props[key] = property.value;
  }
  const frontTags = unique([...listedTags(props.tags), ...listedTags(props.tag), ...listedTags(props.labels)]);
  const fenced = fencedLines(lines);
  const tasks: ReadTask[] = [];
  const links: string[] = [];
  lines.forEach((line, index) => {
    // A link in the front matter is one too (`blocked-by: "[[GHO-9]]"`), as Obsidian reads it; one in code is code.
    if (!fenced.has(index + 1)) for (const found of line.matchAll(LINK)) links.push(found[1]!.trim());
    if (index < front || fenced.has(index + 1)) return;
    const box = taskBox(line);
    if (!box) return;
    const words = itemWords(line) ?? '';
    const fields = fieldsOf(words);
    const text = cardText(withoutFields(words));
    // A box with nothing after it is a to-do still to be written, not one to list.
    if (!text && !words.trim()) return;
    tasks.push({
      line: index,
      source: line,
      text,
      done: box.done,
      anchor: itemOnLine(line)?.id ?? null,
      fields,
      tags: tagsOf(words),
      haystack: text.toLowerCase(),
    });
  });
  const words = lines.slice(front).join('\n').trim();
  const title = noteTitle(body);
  const book = isBookBody(body);
  return {
    title,
    key: titleKey(title),
    props,
    ticket: isTicket(body),
    ticketId: ticketIdOf(body),
    book,
    chapters: book ? chaptersOf(body).map((chapter) => titleKey(chapter.title)) : [],
    statuses: book ? statusesOf(body) : null,
    tags: unique([...tagsOf(body), ...frontTags]),
    frontTags,
    links,
    words,
    haystack: `${title}\n${words}`.toLowerCase(),
    tasks,
  };
}

/** A note read, from the cache while its words are the same. */
function readOf(note: QueryNote, cache: RecordCache): ReadNote {
  const kept = cache.read.get(note.id);
  if (kept && kept.body === note.body) return kept.note;
  const read = readNote(note.body);
  cache.read.set(note.id, { body: note.body, note: read });
  return read;
}

const NO_PROPS: Readonly<Record<string, string>> = Object.freeze(Object.create(null) as Record<string, string>);

/**
 * The library a query reads: every note given as a record, a ticket read as one, and every to-do in them. The notes
 * are the caller's to choose (editor/queries/useQueries.ts leaves out the Trash, the archive, the Guide and the
 * templates' pages); the open note is given as its editor has it, so a query reads what is typed.
 */
export function libraryOf(notes: readonly QueryNote[], cache: RecordCache = recordCache()): Library {
  const read = notes.map((note) => ({ note, read: readOf(note, cache) }));
  // The cache keeps only the notes there are: a note deleted is let go.
  const ids = new Set(notes.map((note) => note.id));
  for (const id of cache.read.keys()) if (!ids.has(id)) cache.read.delete(id);

  const byTitle = new Map<string, LibraryNote>();
  const byTicket = new Map<string, LibraryNote>();
  for (const { note, read: one } of read) {
    const entry: LibraryNote = { id: note.id, title: one.title, key: one.key, book: one.book, statuses: one.statuses };
    if (one.key && !byTitle.has(one.key)) byTitle.set(one.key, entry);
    if (one.ticket && one.ticketId && !byTicket.has(one.ticketId)) byTicket.set(one.ticketId, entry);
  }
  // Each page's notebooks, in the order the notebooks come: the first is the one its title is shown with.
  const booksOf = new Map<string, LibraryNote[]>();
  for (const { note, read: one } of read) {
    if (!one.book) continue;
    const notebook = byTitle.get(one.key)?.id === note.id ? byTitle.get(one.key)! : { id: note.id, title: one.title, key: one.key, book: true, statuses: one.statuses };
    for (const chapter of one.chapters) {
      if (!chapter || chapter === one.key) continue;
      const list = booksOf.get(chapter) ?? [];
      if (!list.some((each) => each.id === notebook.id)) list.push(notebook);
      booksOf.set(chapter, list);
    }
  }

  const records: QueryRecord[] = [];
  for (const { note, read: one } of read) {
    const books = booksOf.get(one.key) ?? [];
    const notebook = books[0] ?? null;
    const workflow = notebook?.statuses ?? DEFAULT_STATUSES;
    const linksTo = new Set<string>();
    for (const link of one.links) {
      const found = byTitle.get(titleKey(link)) ?? byTicket.get(issueKeyOf(link) ?? '');
      if (found) linksTo.add(found.id);
    }
    const shared = {
      noteId: note.id,
      title: one.title,
      notebook: notebook?.title ?? null,
      books: books.map((book) => book.key),
      workflow,
      created: isoDay(new Date(note.createdAt)),
      updated: isoDay(new Date(note.updatedAt)),
      linksTo,
      linkKeys: one.links.map(titleKey).filter(Boolean),
    };
    records.push({
      ...shared,
      kind: one.ticket ? 'ticket' : 'note',
      line: -1,
      source: '',
      text: one.words,
      done: null,
      anchor: null,
      tags: one.tags,
      props: one.props,
      ticket: one.ticket ? ticketOf(note.body, workflow) : null,
      fields: null,
      haystack: one.haystack,
    });
    for (const task of one.tasks) {
      records.push({
        ...shared,
        kind: 'task',
        line: task.line,
        source: task.source,
        text: task.text,
        done: task.done,
        anchor: task.anchor,
        tags: unique([...task.tags, ...one.frontTags]),
        props: NO_PROPS,
        ticket: null,
        fields: task.fields,
        haystack: task.haystack,
      });
    }
  }
  return { records, byTitle, byTicket };
}

/**
 * The note `[[title]]` names in the library: by its title, as a link finds it, or a ticket by its key, as
 * `[[GHO-12]]` does (docs/DESIGN.md §156). Null where it names none.
 */
export function noteNamed(library: Library, title: string): LibraryNote | null {
  return library.byTitle.get(titleKey(title)) ?? library.byTicket.get(issueKeyOf(title) ?? '') ?? null;
}

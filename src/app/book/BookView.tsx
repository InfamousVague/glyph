import { useMemo, useRef, useState, type RefObject } from 'react';
import { BookOpen, Check, ChevronDown, ChevronUp, GripVertical, List, Plus, Ticket, Workflow, X } from '@glacier/icons';
import { isCanvasBody } from '../canvas/jsonCanvas.ts';
import { sameTitle } from '../editor/wikiLinks.ts';
import { authorsAcross } from '../core/authors.ts';
import { Byline } from '../authors/Byline.tsx';
import { bodyWithoutTitle, bookWords, chaptersOf, numbered, toggledTitle, withChapter, withChapterAt, withChapterMoved, withoutChapter } from './book.ts';
import { CanvasMark } from './CanvasMark.tsx';
import { notebookKey } from '../core/properties.ts';
import type { NoteTemplate } from '../notes/noteTemplates.ts';
import { TicketMark } from '../notes/TicketMark.tsx';
import { Editor } from '../editor/Editor.tsx';
import type { VideoMode } from '../editor/videos.ts';
import { isDarkNow, usePreferences } from '../core/preferences.ts';
import { readBookSpot, useBookSpot } from './bookSpot.ts';
import { useRowDrag } from './rowDrag.ts';
import { JUST_THE_TITLE, pageStarts, startLine } from './entryStarts.ts';
import { useBack } from '../core/back.ts';
import styles from './BookView.module.css';

/**
 * A book's index, drawn where its words would be (editor/NoteScreen.tsx): its own words first, then the chapters,
 * numbered, each a row that opens the note - or makes it, where a chapter is a title with no note yet, which the row
 * says. The index is edited here in the three ways an index is: a chapter added (a new one, named here and opened at
 * once; or a note already written, picked from the library), moved - a place up or down, or dragged by its grip
 * (book/rowDrag.ts) - or taken out, none of which touches the chapter's own note. Every change is a change to the
 * book note's body (book/book.ts), written the way typing is, so the Markdown behind the view is always the index it
 * shows, and the view is a toggle away from it. The chapters can also be read straight through, one after another,
 * each in the note's own read-only editor. The bar and the foot a chapter wears to find its way round the book are
 * BookNav.tsx.
 *
 * A chapter can be a canvas (Matt: "Add the ability for canvases to be in books as well"): a canvas is a note found
 * by its title like any other, so it was always a page a book could hold and open - what the index lacked was saying
 * so. A chapter that is a canvas, and a canvas offered in the picker, wear the canvas's own mark (the one the + sheet
 * gives it), so a book reads as the pages and the boards of cards it is made of.
 *
 * Given `spot`, the view keeps where the book was left (book/bookSpot.ts): a book left reading straight through opens
 * reading straight through, scrolled back to the chapter and the line it was at.
 *
 * A notebook with a ticket key (`key: GHO`; book/tickets.ts, docs/DESIGN.md §157) makes tickets as well as pages: New
 * ticket, beside Add a page, asks for the title and what the ticket starts with - just the title, or a ticket's
 * template, a Bug report or a Feature - and puts its line in the index as a page's is, then App makes the ticket with
 * the notebook's next key and its workflow's first open status. A page that is a ticket says its key and status on
 * its row (notes/TicketMark.tsx).
 */

interface BookViewProps {
  body: string;
  /** Whether a note by that title exists: a chapter still to be written is drawn as waiting. */
  known: (title: string) => boolean;
  /** Opens the note by that title, or makes one that starts with it (App.tsx `openTitle`). */
  open: (title: string) => void;
  /** Every note's title, for adding one that is already written. */
  titles: () => string[];
  /** The book's own title, so it is not offered as a chapter of itself. */
  title: string;
  onChange: (body: string) => void;
  /** A note's body by its title, to tell a chapter that is a canvas from one of words; absent, none is marked. */
  bodyOf?: (title: string) => string | null;
  /** Makes a canvas by that title and opens it (App.tsx): the new-chapter form's "Add as a canvas". Absent, no such button. */
  openCanvas?: (title: string) => void;
  /**
   * Makes a page by that title from a template and opens it (App.tsx): Add a page's "Start with". Absent, the form
   * offers no templates and a page begins as its title, through `open`.
   */
  openNew?: (title: string, template: string) => void;
  /**
   * Read, not changed: no grips, no move or take-out tools, nothing to add. The index, the preface, the canvas marks
   * and reading straight through stay. The reader page (src/read/Reader.tsx) draws a shared book with this.
   */
  readOnly?: boolean;
  /** Dark or light, where the page decides rather than the preference (the reader page follows the reader's system). */
  dark?: boolean;
  /**
   * Makes a ticket by that title in this notebook and opens it (App.tsx), from a ticket's template or none: New ticket,
   * offered while the notebook has a key. Absent, no such button.
   */
  openTicket?: (title: string, template: NoteTemplate | null) => void;
  /** The templates a ticket can start from, a Bug report and a Feature among them (notes/noteTemplates.ts). */
  ticketTemplates?: readonly NoteTemplate[];
  /** The book note's id and the page it scrolls in, to keep where it was left (book/bookSpot.ts); absent, nothing is kept. */
  spot?: { id: string; page: RefObject<HTMLElement | null> };
  /** Whose film cards these are (editor/videos.ts): a shared page's say only a still is shared. The owner's by default. */
  videos?: VideoMode;
}

/** The book's own words around its index, drawn as a note is - read-only, formatted - so a link in them opens. */
export function BookWords({ words, known, open, dark, videos = 'still' }: { words: string; known: (title: string) => boolean; open: (title: string) => void; dark: boolean; videos?: VideoMode }) {
  return (
    <div className={styles.preface}>
      <Editor value={words} onChange={noop} dark={dark} assist={false} readOnly display="formatted" wiki={{ known, open }} videos={videos} grow />
    </div>
  );
}

export function BookView({ body, known, open, titles, title, onChange, bodyOf, openCanvas, openNew, openTicket, ticketTemplates = NO_TEMPLATES, readOnly = false, dark: darkGiven, spot, videos = 'still' }: BookViewProps) {
  const isCanvas = (name: string) => {
    const found = bodyOf?.(name);
    return !!found && isCanvasBody(found);
  };
  const chapters = useMemo(() => chaptersOf(body), [body]);
  const numbers = useMemo(() => numbered(chapters), [chapters]);
  const words = useMemo(() => bookWords(body), [body]);
  // Everyone who wrote the book: its own authors, then each chapter's, first met first (core/authors.ts). Read again
  // only when a body changed: `bodyOf` is a new function on every draw of App, and a journal of a year has a page a day.
  const pageBodies = useSameList(chapters.map((c) => bodyOf?.(c.title) ?? ''));
  const authors = useMemo(() => authorsAcross([body, ...pageBodies]), [body, pageBodies]);
  const [adding, setAdding] = useState<'new' | 'existing' | 'ticket' | null>(null);
  /** The notebook's ticket key, where it has one: New ticket is offered only then. */
  const ticketKey = useMemo(() => notebookKey(body), [body]);
  /** Where the book was left, read once as it opens: reading straight through is picked up where it was. */
  const [left, setLeft] = useState(() => {
    const was = spot ? readBookSpot(spot.id) : null;
    return was?.kind === 'reading' ? was : null;
  });
  /** Reading straight through: the chapters one after another, each in the note's own read-only editor. */
  const [reading, setReading] = useState(left !== null);
  const book = useRef<HTMLDivElement>(null);
  useBookSpot(spot?.id ?? null, reading, book, spot?.page, chapters.map((c) => c.title), left);
  const themeDark = isDarkNow(usePreferences().theme);
  const dark = darkGiven ?? themeDark;
  const [draft, setDraft] = useState('');
  /** What the page being added starts with (book/entryStarts.ts `pageStarts`): just its title unless another is picked. */
  const [start, setStart] = useState(JUST_THE_TITLE.id);
  const [filter, setFilter] = useState('');
  /** The notes ticked so far in the picker, in the order they were ticked. */
  const [picked, setPicked] = useState<string[]>([]);
  /** The rows, for a drag to measure; and the drag itself, which writes the chapter to where it was let go. */
  const rowEls = useRef<(HTMLElement | null)[]>([]);
  const drag = useRowDrag(
    () => rowEls.current,
    (from, to) => {
      const chapter = chapters[from];
      if (chapter) onChange(withChapterAt(body, chapter.title, to));
    },
  );

  /** The chapter named in the form, into the index, then opened: as a page of words, or made as an empty canvas. */
  const addNew = (asCanvas = false) => {
    const name = draft.trim();
    if (!name) return;
    const template = pageStarts().find((each) => each.id === start)?.text ?? '';
    onChange(withChapter(body, name));
    setDraft('');
    setStart(JUST_THE_TITLE.id);
    setAdding(null);
    if (asCanvas && openCanvas) openCanvas(name);
    else if (template && openNew) openNew(name, template);
    else open(name);
  };
  /** A ticket named in its form, into the index as a page is, then made by App and opened. */
  const addTicket = () => {
    const name = draft.trim();
    if (!name || !openTicket) return;
    const template = ticketTemplates.find((each) => each.id === start) ?? null;
    onChange(withChapter(body, name));
    setDraft('');
    setStart(JUST_THE_TITLE.id);
    setAdding(null);
    openTicket(name, template);
  };
  const togglePick = (name: string) => setPicked((was) => toggledTitle(was, name));
  const addPicked = () => {
    let next = body;
    for (const name of picked) next = withChapter(next, name);
    onChange(next);
    setPicked([]);
    setFilter('');
    setAdding(null);
  };
  /** Either form put away, and what it was holding let go: the next one opens as new. */
  const closeAdding = () => {
    setStart(JUST_THE_TITLE.id);
    setPicked([]);
    setFilter('');
    setAdding(null);
  };
  // While a form is open, the back gesture (Escape on a desktop) closes it before it would leave the notebook, as the
  // journal's own template choice does (JournalView.tsx), whichever of its controls has the focus.
  useBack(adding !== null, closeAdding);
  const others = adding === 'existing' ? titles().filter((t) => t.trim() && !sameTitle(t, title) && !chapters.some((c) => sameTitle(c.title, t)) && (!filter.trim() || t.toLowerCase().includes(filter.trim().toLowerCase()))) : [];

  if (reading) {
    return (
      <div ref={book} className={styles.book} data-chapters={chapters.length} data-reading="">
        {/* The way back, and the chapters as a rail: a tap scrolls to that one. */}
        <div className={styles.readBar}>
          <button
            type="button"
            className={styles.action}
            onClick={() => {
              // Back at the index, the place the book was left at is spent: reading through again starts afresh.
              setLeft(null);
              setReading(false);
            }}
          >
            <List size={16} aria-hidden="true" /> Index
          </button>
          <nav className={styles.rail} aria-label="Pages">
            {chapters.map((chapter, i) => (
              <button
                key={`${chapter.line}-${chapter.title}`}
                type="button"
                className={styles.railItem}
                data-depth={chapter.depth}
                onClick={() => document.getElementById(`book-chapter-${i}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              >
                <span className={styles.railNumber}>{numbers[i]}</span> {chapter.title}
              </button>
            ))}
          </nav>
        </div>
        {chapters.map((chapter, i) => {
          const there = known(chapter.title);
          const words = there ? (bodyOf?.(chapter.title) ?? null) : null;
          const canvas = words !== null && isCanvasBody(words);
          return (
            <section key={`${chapter.line}-${chapter.title}`} id={`book-chapter-${i}`} className={styles.chapterRead} data-depth={chapter.depth} aria-label={chapter.title}>
              <h2 className={styles.readTitle}>
                <button type="button" className={styles.readTitleButton} onClick={() => open(chapter.title)} aria-label={`Open ${chapter.title}`}>
                  <span className={styles.number} aria-hidden="true">
                    {numbers[i]}
                  </span>
                  {chapter.title}
                  {canvas ? <CanvasMark /> : null}
                </button>
              </h2>
              {!there ? (
                <p className={styles.readNote}>Not written yet.</p>
              ) : canvas ? (
                <p className={styles.readNote}>A canvas: open it to see the cards.</p>
              ) : words === null ? null : (
                <div className={styles.readBody}>
                  <Editor value={bodyWithoutTitle(words, chapter.title)} onChange={noop} dark={dark} assist={false} readOnly display="formatted" videos={videos} peek grow />
                </div>
              )}
            </section>
          );
        })}
      </div>
    );
  }

  return (
    <div className={styles.book} data-chapters={chapters.length} data-read-only={readOnly || undefined}>
      <Byline authors={authors} />
      {words.before ? <BookWords words={words.before} known={known} open={open} dark={dark} videos={videos} /> : null}
      {chapters.length === 0 ? (
        <p className={styles.empty}>{readOnly ? 'No pages yet.' : 'No pages yet. Add one below, or a note you have already written.'}</p>
      ) : (
        <ol className={styles.index} aria-label="Pages">
          {chapters.map((chapter, i) => {
            const there = known(chapter.title);
            const canvas = there && isCanvas(chapter.title);
            return (
              <li
                key={`${chapter.line}-${chapter.title}`}
                ref={(el) => {
                  rowEls.current[i] = el;
                }} className={styles.row} data-depth={chapter.depth} data-waiting={there ? undefined : ''}
                data-lifted={drag.lifted?.index === i || undefined}
                style={drag.rowStyle(i)}
              >
                {readOnly ? null : (
                  <span className={styles.grip} aria-hidden="true" {...drag.grip(i)}>
                    <GripVertical size={16} />
                  </span>
                )}
                <span className={styles.number} aria-hidden="true">
                  {numbers[i]}
                </span>
                <button
                  type="button"
                  className={styles.chapter}
                  onClick={() => open(chapter.title)}
                  aria-label={there ? (canvas ? `${chapter.title}, a canvas` : chapter.title) : `${chapter.title}, not written yet`}
                >
                  <span className={styles.chapterTitle}>
                    {chapter.title}
                    {canvas ? <CanvasMark /> : null}
                  </span>
                  {there ? null : <span className={styles.waiting}>not written yet</span>}
                  {there && !canvas ? <TicketMark body={bodyOf?.(chapter.title) ?? ''} notebook={body} /> : null}
                </button>
                {readOnly ? null : (
                <span className={styles.tools}>
                  <button type="button" className={styles.tool} aria-label={`Move ${chapter.title} up`} disabled={i === 0} onClick={() => onChange(withChapterMoved(body, chapter.title, -1))}>
                    <ChevronUp size={16} aria-hidden="true" />
                  </button>
                  <button type="button" className={styles.tool} aria-label={`Move ${chapter.title} down`} disabled={i === chapters.length - 1} onClick={() => onChange(withChapterMoved(body, chapter.title, 1))}>
                    <ChevronDown size={16} aria-hidden="true" />
                  </button>
                  <button type="button" className={styles.tool} aria-label={`Take ${chapter.title} out of the notebook`} onClick={() => onChange(withoutChapter(body, chapter.title))}>
                    <X size={16} aria-hidden="true" />
                  </button>
                </span>
                )}
              </li>
            );
          })}
        </ol>
      )}

      {words.after ? <BookWords words={words.after} known={known} open={open} dark={dark} videos={videos} /> : null}

      {readOnly ? (
        chapters.length ? (
          <div className={styles.adds}>
            <button type="button" className={styles.action} onClick={() => setReading(true)}>
              <BookOpen size={16} aria-hidden="true" /> Read straight through
            </button>
          </div>
        ) : null
      ) : adding === 'new' || adding === 'ticket' ? (
        <form
          className={styles.add}
          onSubmit={(event) => {
            event.preventDefault();
            if (adding === 'ticket') addTicket();
            else addNew();
          }}
        >
          <input
            className={styles.field}
            aria-label={adding === 'ticket' ? 'New ticket’s title' : "New page's title"}
            placeholder={adding === 'ticket' ? 'What needs doing' : 'Page title'}
            value={draft}
            autoFocus
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => {
              // Taken here, so the back stack does not also step: one Escape closes the form and nothing more.
              if (event.key === 'Escape') {
                event.preventDefault();
                closeAdding();
              }
            }}
          />
          {adding === 'ticket' ? (
            <PageStarts chosen={start} onChoose={setStart} label="Start the ticket with" starts={ticketLines(ticketKey, draft.trim(), ticketTemplates)} />
          ) : openNew ? (
            <PageStarts chosen={start} onChoose={setStart} label="Start the page with" starts={pageLines(draft.trim(), title)} />
          ) : null}
          <button type="submit" className={styles.action} disabled={!draft.trim()}>
            Add and open
          </button>
          {openCanvas && adding === 'new' ? (
            <button type="button" className={styles.action} disabled={!draft.trim()} onClick={() => addNew(true)}>
              <Workflow size={16} aria-hidden="true" /> Add as a canvas
            </button>
          ) : null}
          <button type="button" className={styles.quiet} onClick={closeAdding}>
            Cancel
          </button>
        </form>
      ) : adding === 'existing' ? (
        <div className={styles.add}>
          <input className={styles.field} aria-label="Find a note to add" placeholder="Find a note" value={filter} autoFocus onChange={(event) => setFilter(event.target.value)} />
          <ul className={styles.picker} aria-label="Notes to add">
            {others.length === 0 ? <li className={styles.none}>{filter.trim() ? 'No note by that name outside the notebook.' : 'Every note is in the notebook already.'}</li> : null}
            {others.slice(0, 40).map((name) => {
              const on = picked.some((p) => sameTitle(p, name));
              return (
                <li key={name}>
                  <button type="button" className={styles.pick} aria-pressed={on} onClick={() => togglePick(name)}>
                    <span className={styles.pickMark} aria-hidden="true">
                      {on ? <Check size={14} /> : null}
                    </span>
                    {name}
                    {isCanvas(name) ? <CanvasMark /> : null}
                  </button>
                </li>
              );
            })}
          </ul>
          <button type="button" className={styles.action} disabled={picked.length === 0} onClick={addPicked}>
            {picked.length <= 1 ? 'Add' : `Add ${picked.length} notes`}
          </button>
          <button
            type="button"
            className={styles.quiet}
            onClick={() => {
              setPicked([]);
              setAdding(null);
            }}
          >
            Cancel
          </button>
        </div>
      ) : (
        <div className={styles.adds}>
          <button type="button" className={styles.action} onClick={() => setAdding('new')}>
            <Plus size={16} aria-hidden="true" /> Add a page
          </button>
          {openTicket && ticketKey ? (
            <button type="button" className={styles.action} onClick={() => setAdding('ticket')}>
              <Ticket size={16} aria-hidden="true" /> New ticket
            </button>
          ) : null}
          <button type="button" className={styles.action} onClick={() => setAdding('existing')}>
            <BookOpen size={16} aria-hidden="true" /> Add a note you have
          </button>
          {chapters.length ? (
            <button type="button" className={styles.action} onClick={() => setReading(true)}>
              <BookOpen size={16} aria-hidden="true" /> Read straight through
            </button>
          ) : null}
        </div>
      )}
    </div>
  );
}

/** No ticket templates, as one list, so the default is the same list on every draw. */
const NO_TEMPLATES: readonly NoteTemplate[] = [];

function noop(): void {
  // Read-only: nothing typed comes back.
}

/** `list`, or the list last given when every item is the same: an identity a memo can key on. */
function useSameList(list: readonly string[]): readonly string[] {
  const kept = useRef(list);
  const was = kept.current;
  if (was.length !== list.length || was.some((item, i) => item !== list[i])) kept.current = list;
  return kept.current;
}

/** One way a page or a ticket can start, as Start with lists it: its name, and how it starts, on one line. */
interface StartRow {
  id: string;
  name: string;
  line: string;
}

/** A page's ways to start: just the title, then the templates, each with a line of how it would start this minute. */
function pageLines(title: string, notebook: string): StartRow[] {
  const now = new Date();
  return pageStarts().map((each) => ({ id: each.id, name: each.name, line: each.text ? startLine(each.text, notebook, now) : title || 'The page’s title, and nothing under it' }));
}

/** A ticket's ways to start: its key and title alone, then each ticket's template, said in its sentence. */
function ticketLines(key: string | null, title: string, templates: readonly NoteTemplate[]): StartRow[] {
  const alone = `${key ? `${key}-…` : 'Its key'}, ${title ? `“${title}”` : 'its title'} and its status, and nothing under them`;
  return [{ id: JUST_THE_TITLE.id, name: JUST_THE_TITLE.name, line: alone }, ...templates.map((each) => ({ id: each.id, name: each.name, line: each.sentence }))];
}

/**
 * What a new page starts with, under its title in Add a page: just the title, chosen until another is, then the
 * templates, each with a line of how it would start this minute. A tap chooses; Add and open makes the page from it.
 * New ticket's the same way, its templates the tickets' (Bug report, Feature), each said in its sentence.
 */
function PageStarts({ chosen, onChoose, label, starts }: { chosen: string; onChoose: (id: string) => void; label: string; starts: readonly StartRow[] }) {
  const rows = useRef<(HTMLButtonElement | null)[]>([]);
  /*
   * One stop for Tab, on the chosen row, and the arrows move the choice and the focus together, as a radio group does
   * (notes/WorkspaceSwatch.tsx): focus never rests on a row that is not the one chosen, so the ring and the choice agree.
   */
  const step = (from: number, by: number) => {
    const to = (from + by + starts.length) % starts.length;
    onChoose(starts[to]!.id);
    rows.current[to]?.focus();
  };
  return (
    <div className={styles.starts} role="radiogroup" aria-label={label}>
      <p className={styles.startsTitle}>Start with</p>
      {starts.map((each, n) => (
        <button
          key={each.id}
          ref={(el) => {
            rows.current[n] = el;
          }}
          type="button"
          role="radio"
          aria-checked={chosen === each.id}
          tabIndex={chosen === each.id ? 0 : -1}
          className={styles.start}
          onClick={() => onChoose(each.id)}
          onKeyDown={(event) => {
            if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
              event.preventDefault();
              step(n, 1);
            } else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
              event.preventDefault();
              step(n, -1);
            }
          }}
        >
          <span className={styles.startName}>{each.name}</span>
          <span className={styles.startLine}>{each.line}</span>
        </button>
      ))}
    </div>
  );
}

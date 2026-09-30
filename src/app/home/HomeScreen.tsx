import { useMemo, useRef, useState, type CSSProperties } from 'react';
import { BookOpen, FileText, Mic, Search, Workflow, X } from '@glacier/icons';
import { noteTitle, type Note } from '../core/store.ts';
import { titleKey } from '../core/titleKey.ts';
import { inWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import { usePreferences } from '../core/preferences.ts';
import type { VoiceModelState } from '../capture/useVoiceModel.ts';
import type { Updates } from '../core/ota.ts';
import { useGlideToTop } from '../core/glideToTop.ts';
import { isAndroid } from '../core/platform.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Ghost } from '../art/Ghost.tsx';
import { Cog, Grid, Magnifier, Notebook, Pin, Plus } from '../art/Icons.tsx';
import { NoteCard } from '../notes/NoteCard.tsx';
import { when } from '../notes/when.ts';
import { WorkspaceBar } from '../notes/WorkspaceBar.tsx';
import { WorkspaceSheet } from '../notes/WorkspaceSheet.tsx';
import { UpdateNotice, VoiceModelStatus } from '../notes/Notices.tsx';
import { useGists } from '../format/gist.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { bookIndex, chaptersOf, placeOf } from '../book/book.ts';
import { journalCards } from '../book/journalMonths.ts';
import type { OpenTask } from './dashboard.ts';
import { firstLine, HOME_FILTERS, homeCounts, homeLists, kindOf, library, SPAN_WORDS, timeline, type HomeFilter } from './homeLayout.ts';
import styles from './HomeScreen.module.css';
import look from './HomeLayouts.module.css';

/**
 * The home page: the notebooks and the notes, a search over them, and a filter, drawn one of five ways (docs/DESIGN.md
 * §147; Matt: "redesign the home page / dashboard to be easier to navigate, remove things like the todo list and other
 * things, focus more on displaying the books and notes in an easy way to search and look through; give me 5 different
 * dashboard layout styles we can choose from in the settings").
 *
 * It was a dashboard of what was waiting - a digest, the to-dos of every note, the shelf of tapes, notices - and grew
 * crowded (§132, §137). Now it is a way into the notes. At its top, the search: the page narrows as it is typed, every
 * word anywhere in a note (notes/allNotes.ts `matches`). Under it the filter - All, Notebooks, Notes, Pinned, with how
 * many of each - and the workspace pills. Then the notebooks and the notes in the layout chosen in Settings ›
 * Appearance (home/homeLayout.ts `HOME_LAYOUTS`): Cards, List, Shelf, Library or Timeline. Only what needs the person
 * stays above them: an update ready, the voice model's download or its failure. Tapes are notes like any other, and a
 * to-do is found in its note.
 *
 * The glass bar, the scroller with its smoke, and the dock - write, Speak, Settings, the palette - are as they were.
 */

interface HomeScreenProps {
  notes: Note[];
  loading: boolean;
  onOpen: (id: string, at?: string) => void;
  onNew: () => void;
  onCapture: () => void;
  onSettings: () => void;
  /** Settings at the Model card. Kept for the callers; the page no longer offers it. */
  onGetModel?: () => void;
  /** The command palette (commands/CommandBar.tsx); absent until it has handed back its opener. */
  onSearch?: () => void;
  /** Every note, as a grid of cards (notes/AllNotesScreen.tsx). */
  onAllNotes: (options?: { tapes: boolean }) => void;
  /** Kept for the callers: the page no longer lists to-dos. */
  onTick?: (task: OpenTask) => void;
  voiceModel: VoiceModelState;
  onRetryVoiceModel: () => void;
  updates: Updates;
  /** Kept for the callers: the Academy is offered from Settings now, not from the home page. */
  showAcademy?: boolean;
  onAcademy?: () => void;
  onHideAcademy?: () => void;
}

/** How many notes the Cards and Shelf layouts draw before "All notes" takes over, and how many get a gist written. */
const CARDED = 48;
const GISTED = 16;

export function HomeScreen({ notes, loading, onOpen, onNew, onCapture, onSettings, onSearch, onAllNotes, voiceModel, onRetryVoiceModel, updates }: HomeScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  const field = useRef<HTMLInputElement>(null);
  useWispEdge(scroller, 'home', topBar, { foot: true });
  const { homeLayout: layout } = usePreferences();
  const spaces = useWorkspaces();
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<HomeFilter>('all');
  const workspace = spaces.current?.id ?? null;
  // Another workspace, filter or layout: the page glides back to its top rather than jumping there.
  useGlideToTop(scroller, `${workspace ?? 'all'}|${filter}|${layout}`);
  const inSpace = useMemo(() => inWorkspace(notes, workspace), [notes, workspace]);
  const lists = useMemo(() => homeLists(inSpace, query, filter), [inSpace, query, filter]);
  const counts = useMemo(() => homeCounts(inSpace), [inSpace]);
  /** Every page's notebook, for a card's mark and the Library's pages (book/book.ts). */
  const inBooks = useMemo(() => bookIndex(inSpace), [inSpace]);
  const journals = useMemo(() => journalCards(notes), [notes]);
  const byTitle = useMemo(() => new Map(notes.filter((n) => !n.archivedAt).map((n) => [titleKey(noteTitle(n.body)), n])), [notes]);
  const pagesOf = (book: Note) => chaptersOf(book.body).flatMap((c) => byTitle.get(titleKey(c.title)) ?? []);
  // A line under each card's title, for the cards on the first screens only: the runner asks about what is on screen.
  const carded = useMemo(() => (layout === 'cards' || layout === 'shelf' ? [...lists.books, ...lists.notes].slice(0, GISTED) : []), [layout, lists]);
  const gists = useGists(carded);

  const searched = query.trim() !== '';
  const hasNotes = counts.all > 0;
  const found = lists.books.length + lists.notes.length;

  const card = (note: Note, i: number, dense = false) => (
    <NoteCard key={note.id} note={note} index={i} onOpen={onOpen} gist={gists[note.id]} place={placeOf(inBooks, note)} entries={journals.get(note.id)} dense={dense} />
  );
  // A row names the notebook a page is in, but not under that notebook's own heading (the Library).
  const row = (note: Note, i: number, inBook = false) => (
    <HomeRow key={note.id} note={note} index={i} onOpen={onOpen} bookName={inBook ? null : (placeOf(inBooks, note)?.title ?? null)} entries={journals.get(note.id)?.count} />
  );

  const section = (id: string, heading: string, mark: React.ReactNode, count: number, body: React.ReactNode) => (
    <section className={look.section} aria-labelledby={`home-${id}`} data-section={id}>
      <h2 id={`home-${id}`} className={look.heading}>
        {mark}
        <span>{heading}</span>
        <span className={look.count}>{count}</span>
      </h2>
      {body}
    </section>
  );

  let body: React.ReactNode = null;
  if (found) {
    if (layout === 'list') {
      body = (
        <>
          {lists.books.length ? section('books', 'Notebooks', <Notebook className={look.mark} />, lists.books.length, <ul className={look.rows}>{lists.books.map((n, i) => row(n, i))}</ul>) : null}
          {lists.notes.length ? section('notes', 'Notes', <FileText size={15} className={look.mark} aria-hidden="true" />, lists.notes.length, <ul className={look.rows}>{lists.notes.map((n, i) => row(n, i))}</ul>) : null}
        </>
      );
    } else if (layout === 'shelf') {
      body = (
        <>
          {lists.books.length
            ? section(
                'books',
                'Notebooks',
                <Notebook className={look.mark} />,
                lists.books.length,
                <ol className={look.shelf} aria-label="Notebooks">
                  {lists.books.map((book, i) => (
                    <BookCover key={book.id} book={book} index={i} onOpen={onOpen} count={journals.get(book.id)?.count ?? chaptersOf(book.body).length} journal={journals.has(book.id)} />
                  ))}
                </ol>,
              )
            : null}
          {lists.notes.length
            ? section('notes', 'Notes', <FileText size={15} className={look.mark} aria-hidden="true" />, lists.notes.length, <ol className={look.dense}>{lists.notes.slice(0, CARDED).map((n, i) => card(n, i, true))}</ol>)
            : null}
        </>
      );
    } else if (layout === 'library') {
      const shelves = library(lists, pagesOf, (n) => placeOf(inBooks, n));
      body = (
        <>
          {shelves.books.map(({ book, pages }) => (
            <section key={book.id} className={look.section} aria-label={noteTitle(book.body) || 'Untitled notebook'}>
              <button type="button" className={look.bookHead} onClick={() => onOpen(book.id)}>
                <Notebook className={look.mark} />
                <span className={look.bookName}>{noteTitle(book.body) || 'Untitled notebook'}</span>
                <span className={look.count}>{pages.length}</span>
              </button>
              {pages.length ? <ul className={look.rows}>{pages.map((page, i) => row(page, i, true))}</ul> : <p className={look.none}>{journals.has(book.id) ? 'No entries yet.' : 'No pages yet.'}</p>}
            </section>
          ))}
          {shelves.loose.length
            ? section('loose', shelves.books.length ? 'In no notebook' : 'Notes', <FileText size={15} className={look.mark} aria-hidden="true" />, shelves.loose.length, <ul className={look.rows}>{shelves.loose.map((n, i) => row(n, i))}</ul>)
            : null}
        </>
      );
    } else if (layout === 'timeline') {
      body = timeline(lists).map(({ span, notes: inSpan }) => section(span, SPAN_WORDS[span], null, inSpan.length, <ul className={look.rows}>{inSpan.map((n, i) => row(n, i))}</ul>));
    } else {
      body = (
        <>
          {lists.books.length ? section('books', 'Notebooks', <Notebook className={look.mark} />, lists.books.length, <ol className={styles.cards}>{lists.books.map((n, i) => card(n, i))}</ol>) : null}
          {lists.notes.length
            ? section('notes', 'Notes', <FileText size={15} className={look.mark} aria-hidden="true" />, lists.notes.length, <ol className={styles.cards}>{lists.notes.slice(0, CARDED).map((n, i) => card(n, i + lists.books.length))}</ol>)
            : null}
        </>
      );
    }
  }
  // The Cards and Shelf layouts stop at a few dozen notes; the rest are a tap away on the grid of every note.
  const cut = (layout === 'cards' || layout === 'shelf') && lists.notes.length > CARDED;

  return (
    <div className={styles.screen}>
      <header ref={topBar} className={`app-headerPane ${styles.topBar}`}>
        <h1 className={styles.saidOnly}>Home</h1>
      </header>
      <div ref={scroller} className={styles.scroll}>
        {/* The column the layouts ask their width of, and inside it the layout: a container never answers its own queries. */}
        <div className={styles.page}>
          <div className={look.page} data-layout={layout}>
            {/* The search, first: the page narrows as it is typed. Not on a blank page, which has nothing to search. */}
            {hasNotes ? (
              <div className={look.search} data-filled={searched || undefined}>
                <Search size={17} strokeWidth={2.2} className={look.searchMark} aria-hidden="true" />
                <input
                  ref={field}
                  type="search"
                  className={look.field}
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                  placeholder="Search notebooks and notes"
                  aria-label="Search notebooks and notes"
                  autoComplete="off"
                  autoCorrect="off"
                  autoCapitalize="off"
                  spellCheck={false}
                  enterKeyHint="search"
                />
                {searched ? (
                  <button
                    type="button"
                    className={look.clear}
                    aria-label="Clear the search"
                    onClick={() => {
                      setQuery('');
                      field.current?.focus();
                    }}
                  >
                    <X size={14} strokeWidth={2.4} aria-hidden="true" />
                  </button>
                ) : null}
              </div>
            ) : null}
            {hasNotes ? (
              <div className={look.filters} role="radiogroup" aria-label="Show">
                {HOME_FILTERS.map((each) => (
                  <button key={each.id} type="button" role="radio" aria-checked={filter === each.id} className={look.filter} onClick={() => setFilter(each.id)}>
                    {each.id === 'pinned' ? <Pin className={look.filterMark} /> : null}
                    {each.label}
                    <span className={look.filterCount}>{counts[each.id]}</span>
                  </button>
                ))}
              </div>
            ) : null}
            <WorkspaceBar onManage={setManage} />
            <div className={look.notices}>
              <UpdateNotice updates={updates} />
              <VoiceModelStatus state={voiceModel} onRetry={onRetryVoiceModel} />
            </div>
  
            {!loading && !hasNotes ? (
              <div className={styles.empty}>
                <Ghost scene={spaces.current ? 'empty-workspace' : 'no-notes'} size="lead" className={styles.emptyArt} />
                <p className={styles.emptyLead}>{spaces.current ? `Nothing in ${spaces.current.name} yet.` : 'A blank page.'}</p>
                <p className={styles.emptyHint}>{isAndroid ? 'Write it, or hold the side key and say it.' : 'Write it, or tap Speak and say it.'}</p>
              </div>
            ) : !loading && hasNotes && !found ? (
              <div className={look.nothing}>
                <Ghost scene="search-nothing" size="small" className={look.nothingArt} />
                <p className={look.nothingLead}>{searched ? `Nothing has “${query.trim()}”.` : filter === 'pinned' ? 'Nothing is pinned.' : 'Nothing here.'}</p>
                {searched ? <p className={look.nothingHint}>Try fewer words, or look through All notes.</p> : null}
              </div>
            ) : null}
  
            {body}
  
            {hasNotes ? (
              <button type="button" className={`app-word ${styles.allNotes}`} onClick={() => onAllNotes()}>
                <Grid className={styles.allNotesMark} />
                {cut ? `${lists.notes.length - CARDED} more in All notes` : `All notes · ${counts.all}`}
              </button>
            ) : null}
          </div>
        </div>
      </div>

      {/* The dock: a floating column in the bottom right, Settings, write, then Speak nearest the thumb (HomeScreen.module.css). */}
      <nav className={styles.dock} aria-label="New note">
        <button type="button" className={`${styles.round} ${styles.add}`} onClick={onNew} aria-label="Write a note">
          <Plus />
        </button>
        <button type="button" className={`app-pill ${styles.speak}`} onClick={onCapture} aria-label="Speak a voice note">
          <Mic size={18} strokeWidth={2.2} aria-hidden="true" />
          <span className={styles.speakWord}>Speak</span>
        </button>
        <button type="button" className={`${styles.round} ${styles.cog}`} onClick={onSettings} aria-label="Settings">
          <Cog />
        </button>
        {onSearch ? (
          <button type="button" className={`${styles.round} ${styles.search}`} onClick={onSearch} aria-label="Search and commands">
            <Magnifier />
          </button>
        ) : null}
      </nav>
      <WorkspaceSheet which={manage} onClose={() => setManage(null)} />
    </div>
  );
}

/**
 * A note on one line, for the List, Library and Timeline layouts: its kind's mark, its name, how it starts, and when it
 * was touched, with the pin and its notebook's name where it has them.
 */
function HomeRow({ note, index, onOpen, bookName, entries }: { note: Note; index: number; onOpen: (id: string) => void; bookName: string | null; entries?: number }) {
  const title = noteTitle(note.body);
  const kind = kindOf(note);
  const Mark = kind === 'book' ? BookOpen : kind === 'canvas' ? Workflow : FileText;
  const pages = kind === 'book' ? chaptersOf(note.body).length : 0;
  // A journal counts its entries, from every workspace (book/journalMonths.ts), and a notebook its pages.
  const lead = entries !== undefined ? (entries === 1 ? '1 entry' : `${entries} entries`) : kind === 'book' ? (pages === 1 ? '1 page' : `${pages} pages`) : firstLine(note.body);
  return (
    <li className={look.rowItem} style={{ '--i': Math.min(index, 12) } as CSSProperties}>
      <button type="button" className={look.row} onClick={() => onOpen(note.id)}>
        <Mark size={16} strokeWidth={2} className={look.rowMark} aria-hidden="true" />
        <span className={look.rowText}>
          <span className={look.rowTitle} data-untitled={title ? undefined : ''}>
            {note.starred ? <Pin className={look.rowPin} /> : null}
            {title ? shortenUrls(title) : 'Untitled'}
          </span>
          {lead || bookName ? (
            <span className={look.rowLead}>
              {bookName ? <span className={look.rowBook}>{bookName}</span> : null}
              {lead ? shortenUrls(lead) : null}
            </span>
          ) : null}
        </span>
        <span className={look.rowWhen}>{when(note.updatedAt)}</span>
      </button>
    </li>
  );
}

/** A notebook as a cover on the Shelf: its name large, how many pages or entries, and when it was last written in. */
function BookCover({ book, index, onOpen, count, journal }: { book: Note; index: number; onOpen: (id: string) => void; count: number; journal: boolean }) {
  const title = noteTitle(book.body) || 'Untitled notebook';
  return (
    <li className={look.coverItem} style={{ '--i': Math.min(index, 8) } as CSSProperties}>
      <button type="button" className={look.cover} data-journal={journal || undefined} onClick={() => onOpen(book.id)}>
        <span className={look.coverSpine} aria-hidden="true" />
        <span className={look.coverTitle}>{title}</span>
        <span className={look.coverMeta}>
          {journal ? (count === 1 ? '1 entry' : `${count} entries`) : count === 1 ? '1 page' : `${count} pages`} · {when(book.updatedAt)}
        </span>
      </button>
    </li>
  );
}

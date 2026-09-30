import { useMemo, useRef, useState, type CSSProperties } from 'react';
import { BookOpen, FileText, Mic, Workflow } from '@glacier/icons';
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
import { Clock, Cog, Grid, Magnifier, Notebook, Pin, Plus } from '../art/Icons.tsx';
import { NoteCard } from '../notes/NoteCard.tsx';
import { when } from '../notes/when.ts';
import { WorkspaceSheet } from '../notes/WorkspaceSheet.tsx';
import { UpdateNotice, VoiceModelStatus } from '../notes/Notices.tsx';
import { useGists } from '../format/gist.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { bookIndex, chaptersOf, placeOf } from '../book/book.ts';
import { journalCards } from '../book/journalMonths.ts';
import type { OpenTask } from './dashboard.ts';
import { cardsIn, firstLine, homeCounts, homeLists, homePlan, isBookSection, kindOf, type HomeFilter, type SectionDraw } from './homeLayout.ts';
import { HomeFilters } from './HomeFilters.tsx';
import styles from './HomeScreen.module.css';
import look from './HomeLayouts.module.css';

/**
 * The home page: the notebooks and the notes, a search over them, and filters, drawn one of several ways (docs/DESIGN.md
 * §147; Matt: "redesign the home page / dashboard to be easier to navigate, remove things like the todo list and other
 * things, focus more on displaying the books and notes in an easy way to search and look through; give me 5 different
 * dashboard layout styles we can choose from in the settings").
 *
 * It was a dashboard of what was waiting - a digest, the to-dos of every note, the shelf of tapes, notices - and grew
 * crowded (§132, §137). Now it is a way into the notes. At its top, the search: the page narrows as it is typed, every
 * word anywhere in a note (notes/allNotes.ts `matches`). Beside it, one button for the filters - All, Notebooks,
 * Notes, Pinned, and the workspace - with a chip under the search for each one on (home/HomeFilters.tsx, §148). Then
 * the notebooks and the notes in the layout chosen in Settings › Appearance: the sections home/homeLayout.ts
 * `homePlan` lays out, each drawn as cards, rows or covers. Only what needs the person stays above them: an update
 * ready, the voice model's download or its failure. Tapes are notes like any other, and a to-do is found in its note.
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

/** How many of the first cards get a line written under their titles (format/gist.ts), the rest waiting for a scroll. */
const GISTED = 16;

export function HomeScreen({ notes, loading, onOpen, onNew, onCapture, onSettings, onSearch, onAllNotes, voiceModel, onRetryVoiceModel, updates }: HomeScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
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
  // The day the spans are counted from: a new plan when it turns, not on every draw.
  const today = new Date().setHours(0, 0, 0, 0);
  const plan = useMemo(
    () =>
      homePlan(layout, lists, {
        pagesOf: (book) => chaptersOf(book.body).flatMap((c) => byTitle.get(titleKey(c.title)) ?? []),
        placeOf: (note) => placeOf(inBooks, note),
        now: today,
      }),
    [layout, lists, byTitle, inBooks, today],
  );
  // A line under each card's title, for the first cards only: the runner asks about what is on screen.
  const carded = useMemo(() => cardsIn(plan).slice(0, GISTED), [plan]);
  const gists = useGists(carded);

  const searched = query.trim() !== '';
  const hasNotes = counts.all > 0;
  // The search and its filters stay while there is anything to find, or a workspace to leave: one chosen and empty
  // is left from the filters, since its pills are not on the page any more.
  const tools = notes.some((n) => !n.archivedAt) || spaces.list.length > 0;
  // Whether the layout draws anything: what the search and the filter found, as the layout places it.
  const found = plan.sections.length > 0;

  // The cards' arrival is staggered down the page, whichever section each is in.
  let order = 0;
  // A card or a row names the notebook a page is in, but not under that notebook's own heading.
  const card = (note: Note, dense = false, inBook = false) => (
    <NoteCard key={note.id} note={note} index={order++} onOpen={onOpen} gist={gists[note.id]} place={inBook ? null : placeOf(inBooks, note)} entries={journals.get(note.id)} dense={dense} />
  );
  const row = (note: Note, inBook = false) => (
    <HomeRow key={note.id} note={note} index={order++} onOpen={onOpen} bookName={inBook ? null : (placeOf(inBooks, note)?.title ?? null)} entries={journals.get(note.id)?.count} />
  );
  const drawn = (notes: Note[], draw: SectionDraw, inBook = false) => {
    if (draw === 'rows') return <ul className={look.rows}>{notes.map((n) => row(n, inBook))}</ul>;
    if (draw === 'covers')
      return (
        <ol className={look.shelf} aria-label="Notebooks">
          {notes.map((book) => (
            <BookCover key={book.id} book={book} index={order++} onOpen={onOpen} count={journals.get(book.id)?.count ?? chaptersOf(book.body).length} journal={journals.has(book.id)} />
          ))}
        </ol>
      );
    return <ol className={draw === 'dense' ? look.dense : styles.cards}>{notes.map((n) => card(n, draw === 'dense', inBook))}</ol>;
  };

  const sections = found
    ? plan.sections.map((section) => {
        if (isBookSection(section)) {
          const name = noteTitle(section.book.body) || 'Untitled notebook';
          const journal = journals.has(section.book.id);
          return (
            <section key={section.key} className={look.section} aria-label={name} data-section="book">
              <button type="button" className={look.bookHead} onClick={() => onOpen(section.book.id)}>
                <Notebook className={look.mark} />
                <span className={look.bookName}>{name}</span>
                <span className={look.count}>{section.count}</span>
              </button>
              {section.notes.length ? drawn(section.notes, section.draw, true) : null}
              {section.more ? (
                <button type="button" className={`app-word ${look.more}`} onClick={() => onOpen(section.book.id)}>
                  {section.notes.length ? `${section.more} more in ${name}` : `Open ${name}`}
                </button>
              ) : section.count ? null : (
                <p className={look.none}>{journal ? 'No entries yet.' : 'No pages yet.'}</p>
              )}
            </section>
          );
        }
        const mark =
          section.mark === 'notebook' ? (
            <Notebook className={look.mark} />
          ) : section.mark === 'note' ? (
            <FileText size={15} className={look.mark} aria-hidden="true" />
          ) : section.mark === 'recent' ? (
            <Clock className={look.mark} />
          ) : null;
        return (
          <section key={section.key} className={look.section} aria-labelledby={`home-${section.key}`} data-section={section.key}>
            <h2 id={`home-${section.key}`} className={look.heading}>
              {mark}
              <span>{section.heading}</span>
              {section.count === null ? null : <span className={look.count}>{section.count}</span>}
            </h2>
            {drawn(section.notes, section.draw)}
          </section>
        );
      })
    : null;

  return (
    <div className={styles.screen}>
      <header ref={topBar} className={`app-headerPane ${styles.topBar}`}>
        <h1 className={styles.saidOnly}>Home</h1>
      </header>
      <div ref={scroller} className={styles.scroll}>
        {/* The column the layouts ask their width of, and inside it the layout: a container never answers its own queries. */}
        <div className={styles.page}>
          <div className={look.page} data-layout={layout}>
            {/* The search first, the page narrowing as it is typed, and its filters beside it. Not on a blank page. */}
            {tools ? <HomeFilters query={query} onQuery={setQuery} filter={filter} onFilter={setFilter} counts={counts} onManage={setManage} /> : null}
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

            {sections}

            {hasNotes ? (
              <button type="button" className={`app-word ${styles.allNotes}`} onClick={() => onAllNotes()}>
                <Grid className={styles.allNotesMark} />
                {plan.cut ? `${plan.cut} more in All notes` : `All notes · ${counts.all}`}
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
      <WorkspaceSheet
        which={manage}
        onClose={() => {
          setManage(null);
          // The sheet was opened from the filters' panel, which closed for it: the keyboard goes back to their button.
          scroller.current?.querySelector<HTMLButtonElement>('button[aria-haspopup="dialog"]')?.focus({ preventScroll: true });
        }}
      />
    </div>
  );
}

/**
 * A note on one line, for every layout that draws rows (List, Timeline, Spotlight, Shelf and timeline, Library): its kind's mark, its name, how it starts, and when it
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

/** A notebook as a cover on the shelf (Shelf, Shelf and timeline): its name large, how many pages or entries, and when it was last written in. */
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

import { useMemo, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { BookOpen, FileText, Mic, Workflow } from '@glacier/icons';
import { noteTitle, type Note } from '../core/store.ts';
import { titleKey } from '../core/titleKey.ts';
import { inWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import { usePreferences } from '../core/preferences.ts';
import type { VoiceModelState } from '../capture/useVoiceModel.ts';
import { useMeetingState } from '../capture/meetingLive.ts';
import { counter } from '../capture/tape.ts';
import type { Updates } from '../core/ota.ts';
import { useGlideToTop } from '../core/glideToTop.ts';
import { isAndroid } from '../core/platform.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Ghost } from '../art/Ghost.tsx';
import { Cassette, Clock, Cog, Grid, Magnifier, Notebook, Pin, Plus } from '../art/Icons.tsx';
import { NoteCard } from '../notes/NoteCard.tsx';
import { TicketMark } from '../notes/TicketMark.tsx';
import { isTicket } from '../core/properties.ts';
import { PullToRefresh } from '../notes/PullToRefresh.tsx';
import { SwipeRow } from '../notes/SwipeRow.tsx';
import { isNoteSwipe, noteSwipes, type NoteSwipe } from '../notes/swipe.ts';
import { onNoteContextMenu } from '../notes/noteMenu.ts';
import { when } from '../notes/when.ts';
import { WorkspaceSheet } from '../notes/WorkspaceSheet.tsx';
import { InviteNotice, UpdateNotice, VoiceModelStatus } from '../notes/Notices.tsx';
import { useAccount } from '../core/account/account.ts';
import { NewOrganizationSheet } from './NewOrganizationSheet.tsx';
import { useGists } from '../format/gist.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { bookIndex, chaptersOf, placeOf } from '../book/book.ts';
import { canvasOf } from '../canvas/jsonCanvas.ts';
import { journalCards } from '../book/journalMonths.ts';
import type { OpenTask } from './dashboard.ts';
import { cardsIn, firstLine, homeCounts, homeLists, homePlan, isBookSection, kindOf, type HomeFilter, type HomeKind, type SectionDraw } from './homeLayout.ts';
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
 * ready, an invitation to an organization waiting for its answer (docs/TEAMS.md), the voice model's download or its
 * failure. Tapes are notes like any other, and a to-do is found in its note. Signed in, the filters' panel makes an
 * organization beside a workspace, and an organization's workspace opens the organization's screen.
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
  /**
   * A note swiped past a detent (notes/swipe.ts `noteSwipes`): pinned or unpinned, archived, or deleted, each with its
   * Undo (notes/useNoteActions.ts). Without it the notes do not swipe.
   */
  onSwipe?: (note: Note, action: NoteSwipe) => void;
  /** A pull down from the top (notes/PullToRefresh.tsx, docs/DESIGN.md §152): a sync, and the notes read again. */
  onRefresh?: () => Promise<unknown>;
  voiceModel: VoiceModelState;
  onRetryVoiceModel: () => void;
  updates: Updates;
  /** Kept for the callers: the Academy is offered from Settings now, not from the home page. */
  showAcademy?: boolean;
  onAcademy?: () => void;
  onHideAcademy?: () => void;
  /** An organization's dashboard (notes/OrganizationScreen.tsx): from a new one, from an invitation accepted. */
  onOrganization?: (orgId: string) => void;
  /** An organization's settings (settings/OrganizationSheet.tsx): from "Edit" on its workspace; absent, the dashboard. */
  onOrganizationSettings?: (orgId: string) => void;
}

/** How many of the first cards get a line written under their titles (format/gist.ts), the rest waiting for a scroll. */
const GISTED = 16;

export function HomeScreen({ notes, loading, onOpen, onNew, onCapture, onSettings, onSearch, onAllNotes, onSwipe, onRefresh, voiceModel, onRetryVoiceModel, updates, onOrganization, onOrganizationSettings }: HomeScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  useWispEdge(scroller, 'home', topBar, { foot: true });
  // The meeting being recorded now, whose note has no tape until it stops: its row says so (capture/meetingLive.ts).
  const meeting = useMeetingState();
  const recording = meeting?.recording ? meeting.noteId : null;
  const { homeLayout: layout } = usePreferences();
  const spaces = useWorkspaces();
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  // A new organization, from the filters' panel: signed in, and with somewhere for it to open.
  const account = useAccount();
  const [newOrg, setNewOrg] = useState(false);
  const makeOrg = account.session && onOrganization ? () => setNewOrg(true) : undefined;
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
  // Right to pin, left to archive, further left to delete (docs/DESIGN.md §151): every card, row and line swipes.
  const swipe = (note: Note) => (onSwipe ? { ...noteSwipes(note), onAction: (id: string) => isNoteSwipe(id) && onSwipe(note, id) } : undefined);
  // A card or a row names the notebook a page is in, but not under that notebook's own heading.
  const card = (note: Note, dense = false, inBook = false) => (
    <NoteCard key={note.id} note={note} index={order++} onOpen={onOpen} gist={gists[note.id]} place={inBook ? null : placeOf(inBooks, note)} notebook={placeOf(inBooks, note)?.book.body} entries={journals.get(note.id)} dense={dense} swipe={swipe(note)} />
  );
  const row = (note: Note, inBook = false) => (
    <HomeRow key={note.id} note={note} index={order++} onOpen={onOpen} bookName={inBook ? null : (placeOf(inBooks, note)?.title ?? null)} notebook={placeOf(inBooks, note)?.book.body} entries={journals.get(note.id)?.count} live={note.id === recording} swipe={swipe(note)} />
  );
  const drawn = (notes: Note[], draw: SectionDraw, inBook = false) => {
    if (draw === 'rows') return <ul className={look.rows}>{notes.map((n) => row(n, inBook))}</ul>;
    if (draw === 'lines')
      return (
        <ul className={look.lines}>
          {notes.map((n) => (
            <HomeLine key={n.id} note={n} index={order++} onOpen={onOpen} bookName={placeOf(inBooks, n)?.title ?? null} notebook={placeOf(inBooks, n)?.book.body} live={n.id === recording} swipe={swipe(n)} />
          ))}
        </ul>
      );
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
          ) : section.mark === 'pinned' ? (
            <Pin className={`${look.mark} ${look.markPin}`} />
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
            {tools ? <HomeFilters query={query} onQuery={setQuery} filter={filter} onFilter={setFilter} counts={counts} onManage={setManage} onNewOrganization={makeOrg} onOrganization={onOrganizationSettings ?? onOrganization} /> : null}
            <div className={look.notices}>
              <UpdateNotice updates={updates} />
              <InviteNotice onOpen={onOrganization} />
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
      {onRefresh ? <PullToRefresh scroller={scroller} onRefresh={onRefresh} /> : null}
      <WorkspaceSheet
        which={manage}
        onClose={() => {
          setManage(null);
          // The sheet was opened from the filters' panel, which closed for it: the keyboard goes back to their button.
          scroller.current?.querySelector<HTMLButtonElement>('button[aria-haspopup="dialog"]')?.focus({ preventScroll: true });
        }}
        onOrganization={onOrganizationSettings ?? onOrganization}
      />
      {makeOrg && onOrganization ? <NewOrganizationSheet open={newOrg} onClose={() => setNewOrg(false)} onMade={onOrganization} /> : null}
    </div>
  );
}

/** What a row or a line swipes with, from the page (`swipe`), or nothing where the notes do not swipe. */
type Swipe = ReturnType<typeof noteSwipes> & { onAction: (id: string) => void };

/** A row's or a line's button in a swipe's frame (notes/SwipeRow.tsx), or alone where the notes do not swipe. */
function Swiped({ swipe, compact = false, children }: { swipe?: Swipe; compact?: boolean; children: ReactNode }) {
  if (!swipe) return children;
  return (
    <SwipeRow start={swipe.start} end={swipe.end} onAction={swipe.onAction} compact={compact}>
      {children}
    </SwipeRow>
  );
}

/**
 * A note's kind as a mark at the start of its row or line: a notebook, a canvas, a recording's cassette (the one the
 * tape shelf wore, art/Icons.tsx), or a page of words.
 */
function KindMark({ kind }: { kind: HomeKind }) {
  if (kind === 'tape') return <Cassette className={`${look.rowMark} ${look.rowMarkTape}`} />;
  const Mark = kind === 'book' ? BookOpen : kind === 'canvas' ? Workflow : FileText;
  return <Mark size={16} strokeWidth={2} className={look.rowMark} aria-hidden="true" />;
}

/**
 * What a recording says before its words: how long it is, "0:40", or, for the meeting being recorded, that it is. A
 * voice note reads as one at a glance in the timeline, where it had been a page of words like any other.
 */
function TapeWords({ note, live }: { note: Note; live: boolean }) {
  if (live) return <span className={look.rowLive}>Recording now</span>;
  if (kindOf(note) !== 'tape') return null;
  return <span className={look.rowTape}>{counter(note.recordingMs ?? 0)}</span>;
}

/**
 * A note on one line, for every layout that draws rows (List, Timeline, Spotlight, Shelf and timeline, Library): its kind's mark, its name, how it starts, and when it
 * was touched, with the pin and its notebook's name where it has them, and a ticket's key and status (docs/DESIGN.md §157).
 */
function HomeRow({
  note,
  index,
  onOpen,
  bookName,
  notebook,
  entries,
  live = false,
  swipe,
}: {
  note: Note;
  index: number;
  onOpen: (id: string) => void;
  bookName: string | null;
  /** The notebook it is a page of, whose workflow a ticket's status is placed in. */
  notebook?: string;
  entries?: number;
  live?: boolean;
  swipe?: Swipe;
}) {
  const title = noteTitle(note.body);
  const kind = live ? 'tape' : kindOf(note);
  const pages = kind === 'book' ? chaptersOf(note.body).length : 0;
  // A journal counts its entries, from every workspace (book/journalMonths.ts), a notebook its pages, and a canvas its
  // cards: its first line is JSON, and a row that began "{" said nothing.
  const cards = kind === 'canvas' ? (canvasOf(note.body)?.nodes.length ?? 0) : 0;
  const counted = (n: number, one: string, many: string) => (n === 1 ? `1 ${one}` : `${n} ${many}`);
  const lead =
    entries !== undefined
      ? counted(entries, 'entry', 'entries')
      : kind === 'book'
        ? counted(pages, 'page', 'pages')
        : kind === 'canvas'
          ? cards
            ? counted(cards, 'card', 'cards')
            : 'No cards yet'
          : firstLine(note.body);
  return (
    <li className={look.rowItem} style={{ '--i': Math.min(index, 12) } as CSSProperties} onContextMenu={onNoteContextMenu(note.id)}>
      <Swiped swipe={swipe}>
        <button type="button" className={look.row} onClick={() => onOpen(note.id)}>
          <KindMark kind={kind} />
          <span className={look.rowText}>
            <span className={look.rowTitle} data-untitled={title ? undefined : ''}>
              {note.starred ? <Pin className={look.rowPin} /> : null}
              {title ? shortenUrls(title) : 'Untitled'}
            </span>
            {lead || bookName || kind === 'tape' || isTicket(note.body) ? (
              <span className={look.rowLead}>
                {bookName ? <span className={look.rowBook}>{bookName}</span> : null}
                <TicketMark body={note.body} notebook={notebook} className={look.rowTicket} />
                <TapeWords note={note} live={live} />
                {lead ? shortenUrls(lead) : null}
              </span>
            ) : null}
          </span>
          <span className={look.rowWhen}>{when(note.updatedAt)}</span>
        </button>
      </Swiped>
    </li>
  );
}

/**
 * A note on one short line, for Spotlight's pinned notes: its kind's mark, its name, the notebook it is in, and when.
 * No pin, since the list is the pinned ones, and no line of how it starts: the list is for finding a note by its name.
 */
function HomeLine({ note, index, onOpen, bookName, notebook, live = false, swipe }: { note: Note; index: number; onOpen: (id: string) => void; bookName: string | null; notebook?: string; live?: boolean; swipe?: Swipe }) {
  const title = noteTitle(note.body);
  const kind = live ? 'tape' : kindOf(note);
  return (
    <li className={look.rowItem} style={{ '--i': Math.min(index, 12) } as CSSProperties} onContextMenu={onNoteContextMenu(note.id)}>
      <Swiped swipe={swipe} compact>
        <button type="button" className={look.line} onClick={() => onOpen(note.id)}>
          <KindMark kind={kind} />
          <span className={look.lineTitle} data-untitled={title ? undefined : ''}>
            {title ? shortenUrls(title) : 'Untitled'}
          </span>
          {bookName ? <span className={look.lineBook}>{bookName}</span> : null}
          <TicketMark body={note.body} notebook={notebook} />
          <TapeWords note={note} live={live} />
          <span className={look.rowWhen}>{when(note.updatedAt)}</span>
        </button>
      </Swiped>
    </li>
  );
}

/** A notebook as a cover on the shelf (Shelf, Shelf and timeline): its name large, how many pages or entries, and when it was last written in. */
function BookCover({ book, index, onOpen, count, journal }: { book: Note; index: number; onOpen: (id: string) => void; count: number; journal: boolean }) {
  const title = noteTitle(book.body) || 'Untitled notebook';
  return (
    <li className={look.coverItem} style={{ '--i': Math.min(index, 8) } as CSSProperties} onContextMenu={onNoteContextMenu(book.id)}>
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

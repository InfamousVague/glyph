import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { Mic } from '@glacier/icons';
import { noteTitle, type Note } from '../core/store.ts';
import { inWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import { usePreferences } from '../core/preferences.ts';
import type { VoiceModelState } from '../capture/useVoiceModel.ts';
import type { Updates } from '../core/ota.ts';
import { useGlideToTop } from '../core/glideToTop.ts';
import { isAndroid } from '../core/platform.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Ghost } from '../art/Ghost.tsx';
import { Book, Cassette, Clock, Cog, Grid, Magnifier, Pin, Plus, TickBox } from '../art/Icons.tsx';
import { NoteCard } from '../notes/NoteCard.tsx';
import { when } from '../notes/when.ts';
import { WorkspaceBar } from '../notes/WorkspaceBar.tsx';
import { WorkspaceSheet } from '../notes/WorkspaceSheet.tsx';
import { AcademyCard, RefiningNotice, UpdateNotice, VoiceModelStatus } from '../notes/Notices.tsx';
import { useGists } from '../format/gist.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { isTauri } from '../core/tauri.ts';
import { enqueueSummary } from '../ai/summaries.ts';
import { bookNotes, openTasks, pinnedNotes, recentNotes, summaryKindOf, tapedNotes, tickedTasks, type OpenTask } from './dashboard.ts';
import { TapeShelf } from './TapeShelf.tsx';
import { bookIndex, placeOf } from '../book/book.ts';
import styles from './HomeScreen.module.css';

/**
 * The home page (Matt: "Add a 'home' button to take us to a dashboard like page"; he chose a new page on every screen,
 * the phone's start page included). The top bar's Glyph mark brings you here from anywhere.
 *
 * Redrawn as headed groups with room between them (docs/DESIGN.md §132; Matt: "The library and tapes headers on the
 * home page are different sizes, id like you to redo the home dashboard UI/UX to make it easier to digest everything
 * with cards and quick actions and summaries and better labeling. Right now it's just very data dense with no solid
 * organization and use of white space"). The date is the page's one title; then anything waiting on them (an update,
 * the Academy's invitation, the voice model); then the groups, each under a sentence-case heading with one mark
 * beside it: the notes they pinned first (Matt, §29g: pinned notes "in a category above the rest"), the tapes the
 * recorder made as a row of cards (home/TapeShelf.tsx; Matt: "display them in a cassette shelf on the home page"),
 * their books, the ones they were in last, and every to-do not yet ticked, gathered from all of their notes and ticked
 * here without opening the note. The page does not list every note; "All notes" at its foot opens the page that does,
 * as a grid of the same cards (notes/AllNotesScreen.tsx).
 *
 * The headers Matt saw at two sizes were two kinds of icon: the pin and the cassette were art/Icons.tsx's 1em strokes
 * drawn at 1.15em of a 13px heading, while the Library's book was the kit's lucide, which writes width=24 as an
 * attribute and ignores the em. Every heading's mark is now Icons.tsx's line at the heading's own size.
 *
 * It took the place of the notes list, and kept what the list had that was not the list: the glass bar and scroller,
 * the workspace pills choosing what it shows, and the dock, so starting a note is where it always was.
 */

interface HomeScreenProps {
  notes: Note[];
  loading: boolean;
  onOpen: (id: string, at?: string) => void;
  onNew: () => void;
  onCapture: () => void;
  onSettings: () => void;
  /** Settings open at Formatting, where a language model is fetched: the shelf's "Get a model". Plain Settings when absent. */
  onGetModel?: () => void;
  /**
   * The command palette (commands/CommandBar.tsx): search the notes and everything Glyph can do. Absent until the
   * palette has handed back its opener, and then the dock has no Search button rather than one that does nothing.
   */
  onSearch?: () => void;
  /** Every note, as a grid of cards (notes/AllNotesScreen.tsx); with `tapes`, only the notes with a recording, from the Tapes heading's "See all". */
  onAllNotes: (options?: { tapes: boolean }) => void;
  /** A to-do ticked from here: its note's line rewritten with the box ticked. */
  onTick: (task: OpenTask) => void;
  voiceModel: VoiceModelState;
  onRetryVoiceModel: () => void;
  updates: Updates;
  showAcademy?: boolean;
  onAcademy?: () => void;
  onHideAcademy?: () => void;
}

/**
 * How many of the notes touched last are shown (four: one row on a wide screen, and they run straight into "All
 * notes", which is their See all), how many tapes are on the shelf, how many to-dos the card holds until "Show all"
 * is pressed, and how many it holds then, before the rest are counted instead.
 */
const RECENT = 4;
const SHELF = 8;
const TASKS = 5;
const TASKS_OPEN = 40;
/**
 * How many beats the groups under the shelf wait for it: the two and a bit cassettes the cover screen shows, not all
 * eight, or Recent's first card waited 320ms under an empty heading on every press of Home.
 */
const SHELF_BEATS = 3;

export function HomeScreen({
  notes,
  loading,
  onOpen,
  onNew,
  onCapture,
  onSettings,
  onGetModel,
  onSearch,
  onAllNotes,
  onTick,
  voiceModel,
  onRetryVoiceModel,
  updates,
  showAcademy = false,
  onAcademy,
  onHideAcademy,
}: HomeScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  // Smoke at both ends: under the bar, and at the page's very foot, with the notes running on under the dock's
  // buttons down to it (Matt: "Make the bottom bar transparent and move the dark gradient down").
  useWispEdge(scroller, 'home', topBar, { foot: true });
  const spaces = useWorkspaces();
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  // Another workspace chosen: the page glides back to its top rather than jumping there.
  useGlideToTop(scroller, spaces.current?.id ?? 'all');
  // The chosen workspace chooses the page too, as it chose the list. Held steady between renders, since the cards it
  // works out are what the gist runner is given: a fresh array every time a to-do is ticked would put its work off.
  const workspace = spaces.current?.id ?? null;
  const shown = useMemo(() => inWorkspace(notes, workspace), [notes, workspace]);
  // Which notes are meetings (core/preferences.ts): a meeting is a tape whatever made it, so Recent leaves it to the shelf.
  const { meetings } = usePreferences();
  const pinned = useMemo(() => pinnedNotes(shown), [shown]);
  const recent = useMemo(() => recentNotes(shown, RECENT, meetings), [shown, meetings]);
  // The tapes, the last recorded first; the shelf holds eight and says how many more there are (home/TapeShelf.tsx).
  const taped = useMemo(() => tapedNotes(shown, meetings), [shown, meetings]);
  const shelf = useMemo(() => taped.slice(0, SHELF), [taped]);
  const shelfBeats = Math.min(shelf.length, SHELF_BEATS);
  const books = useMemo(() => bookNotes(shown), [shown]);
  /** Every page's book, for the cards' marks (book/book.ts). */
  const inBooks = useMemo(() => bookIndex(shown), [shown]);
  const tasks = useMemo(() => openTasks(shown), [shown]);
  // One quiet line under each card's title, what the note is about, written by a model on the phone (format/gist.ts).
  // Only the notes with a card or a cassette on the page: the runner asks about what is on screen, not about every
  // note there is. The shelf's notes are here too, or a 40-second voice note would never get a line.
  const carded = useMemo(() => [...pinned, ...shelf, ...recent], [pinned, shelf, recent]);
  const gists = useGists(carded);
  const titleOf = useMemo(() => new Map(notes.map((n) => [n.id, noteTitle(n.body) || 'Untitled'])), [notes]);
  // A tick lands on the page at once; the note catches up when it has been written.
  const [ticked, setTicked] = useState<ReadonlySet<string>>(new Set());
  // Once the notes have been read again they say it themselves, and a line number may now be another to-do's.
  useEffect(() => setTicked(new Set()), [notes]);
  const open = tasks.filter((t) => !ticked.has(`${t.noteId}:${t.line}`));
  // With none left open, a page that had to-dos says they are done; one that never had any says nothing.
  const allDone = !open.length && (ticked.size > 0 || tickedTasks(shown) > 0);
  // "Show all 14": the card opens in place to forty rows. Folded again with the workspace, whose to-dos these are.
  const [showAll, setShowAll] = useState(false);
  useEffect(() => setShowAll(false), [workspace]);
  // The To do card takes one beat between the pinned cards and the shelf.
  const todoBeats = open.length || allDone ? 1 : 0;

  const today = new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });

  /** A note's card (notes/NoteCard.tsx), at its place in the run of cards down the page. */
  const card = (note: Note, i: number) => (
    <NoteCard key={note.id} note={note} index={i} onOpen={onOpen} gist={gists[note.id]} place={placeOf(inBooks, note)} />
  );

  return (
    <div className={styles.screen}>
      <header ref={topBar} className={`app-headerPane ${styles.topBar}`}>
        {/* The name is for a screen reader, which has no bar to look at; the bar shows where you are with its mark. */}
        <h1 className={styles.saidOnly}>Home</h1>
      </header>
      <div ref={scroller} className={styles.scroll}>
        <div className={styles.page}>
          <p className={styles.today}>{today}</p>
          <WorkspaceBar onManage={setManage} />
          <UpdateNotice updates={updates} />
          <VoiceModelStatus state={voiceModel} onRetry={onRetryVoiceModel} />
          {showAcademy && onAcademy ? <AcademyCard onOpen={onAcademy} onHide={onHideAcademy} /> : null}
          <RefiningNotice />

          {!loading && shown.filter((n) => !n.archivedAt).length === 0 ? (
            <div className={styles.empty}>
              <Ghost scene={spaces.current ? 'empty-workspace' : 'no-notes'} size="lead" className={styles.emptyArt} />
              <p className={styles.emptyLead}>{spaces.current ? `Nothing in ${spaces.current.name} yet.` : 'A blank page.'}</p>
              <p className={styles.emptyHint}>{isAndroid ? 'Write it, or hold the side key and say it.' : 'Write it, or tap Speak and say it.'}</p>
            </div>
          ) : null}

          {pinned.length ? (
            <section className={styles.section} aria-labelledby="home-pinned">
              <div className={styles.groupRow}>
                <h2 id="home-pinned" className={styles.group}>
                  <Pin className={`${styles.groupMark} ${styles.groupMarkPin}`} />
                  <span className={styles.groupName}>Pinned</span>
                </h2>
              </div>
              <ol className={styles.cards}>{pinned.map(card)}</ol>
            </section>
          ) : null}

          {/*
            What is waiting, in one card, second on the page: its tick is the page's one in-place action, and a
            meeting's summary writes its `- [ ]` actions here (§127). Five rows, most recently touched note's first,
            each with the note it lives in and when that note was touched; "Show all" opens the card to forty.
          */}
          {open.length ? (
            <section className={styles.section} aria-labelledby="home-tasks">
              <div className={styles.groupRow}>
                <h2 id="home-tasks" className={styles.group}>
                  <TickBox className={styles.groupMark} />
                  <span className={styles.groupName}>To do</span>
                  <span className={styles.count}>· {open.length}</span>
                </h2>
                {open.length > TASKS ? (
                  <button type="button" className={`app-word ${styles.groupWord}`} onClick={() => setShowAll((was) => !was)}>
                    {showAll ? 'Show fewer' : `Show all ${open.length}`}
                  </button>
                ) : null}
              </div>
              <div className={styles.todo} style={{ '--i': Math.min(pinned.length, 8) } as CSSProperties}>
                <ul className={styles.tasks}>
                  {open.slice(0, showAll ? TASKS_OPEN : TASKS).map((task) => (
                    <li key={`${task.noteId}:${task.line}`} className={styles.task}>
                      <button
                        type="button"
                        className={styles.box}
                        aria-label={`Tick off ${task.text}`}
                        onClick={() => {
                          setTicked((was) => new Set(was).add(`${task.noteId}:${task.line}`));
                          onTick(task);
                        }}
                      />
                      <button type="button" className={styles.taskOpen} onClick={() => onOpen(task.noteId, task.at)}>
                        <span className={styles.taskText}>{shortenUrls(task.text)}</span>
                        <span className={styles.taskNote}>
                          {titleOf.get(task.noteId)} · {when(task.touched)}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
                {showAll && open.length > TASKS_OPEN ? <p className={styles.more}>and {open.length - TASKS_OPEN} more in your notes</p> : null}
              </div>
            </section>
          ) : allDone ? (
            <section className={styles.section} aria-labelledby="home-tasks">
              <div className={styles.groupRow}>
                <h2 id="home-tasks" className={styles.group}>
                  <TickBox className={styles.groupMark} />
                  <span className={styles.groupName}>To do</span>
                </h2>
              </div>
              <div className={styles.todo} style={{ '--i': Math.min(pinned.length, 8) } as CSSProperties}>
                <Ghost scene="all-ticked" size="small" className={styles.allDoneArt} />
                <p className={styles.allDoneWords}>Every to-do is done.</p>
              </div>
            </section>
          ) : null}

          {/* The tapes, as cards on a shelf (docs/DESIGN.md §127). No group while there are none. */}
          {shelf.length ? (
            <section className={styles.section} aria-labelledby="home-tapes">
              <div className={styles.groupRow}>
                <h2 id="home-tapes" className={styles.group}>
                  <Cassette className={styles.groupMark} />
                  <span className={styles.groupName}>Tapes</span>
                  {taped.length > shelf.length ? <span className={styles.count}>· {taped.length}</span> : null}
                </h2>
                {/* Only past the shelf's eight: the count and the way to the rest, All notes with its Tapes toggle on. */}
                {taped.length > shelf.length ? (
                  <button type="button" className={`app-word ${styles.groupWord}`} onClick={() => onAllNotes({ tapes: true })}>
                    See all
                  </button>
                ) : null}
              </div>
              <TapeShelf
                notes={shelf}
                gists={gists}
                onOpen={onOpen}
                onGetModel={onGetModel ?? onSettings}
                // The queue is asked for the tape's real kind: a meeting's write-up for a meeting, a recording's otherwise.
                onSummarize={(note) => enqueueSummary(note.id, summaryKindOf(note, meetings))}
                canSummarize={isTauri()}
              />
            </section>
          ) : null}

          {books.length ? (
            <section className={styles.section} aria-labelledby="home-library">
              <div className={styles.groupRow}>
                <h2 id="home-library" className={styles.group}>
                  <Book className={styles.groupMark} />
                  <span className={styles.groupName}>Library</span>
                </h2>
              </div>
              <ol className={styles.cards}>{books.map((n, i) => card(n, i + pinned.length + todoBeats + shelfBeats))}</ol>
            </section>
          ) : null}

          {recent.length ? (
            <section className={styles.section} aria-labelledby="home-recent">
              <div className={styles.groupRow}>
                <h2 id="home-recent" className={styles.group}>
                  <Clock className={styles.groupMark} />
                  <span className={styles.groupName}>Recent</span>
                </h2>
              </div>
              <ol className={styles.cards}>{recent.map((n, i) => card(n, i + pinned.length + todoBeats + shelfBeats + books.length))}</ol>
            </section>
          ) : null}

          {/* The way to every note: the grid page (notes/AllNotesScreen.tsx), with how many wait there. */}
          <button type="button" className={`app-word ${styles.allNotes}`} onClick={() => onAllNotes()}>
            <Grid className={styles.allNotesMark} />
            All notes · {notes.filter((n) => !n.archivedAt).length}
          </button>
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
        {/* Search and the commands, the palette ⌘K opens on a desktop (Matt: "Add a search button to the right hand dock of buttons that opens the command pallette"). */}
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

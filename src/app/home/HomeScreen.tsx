import { useEffect, useMemo, useRef, useState } from 'react';
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
import { WorkspaceBar } from '../notes/WorkspaceBar.tsx';
import { WorkspaceSheet } from '../notes/WorkspaceSheet.tsx';
import { AcademyCard, RefiningNotice, UpdateNotice, VoiceModelStatus } from '../notes/Notices.tsx';
import { useGists } from '../format/gist.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { bookNotes, openTasks, pinnedNotes, recentNotes, tapedNotes, tickedTasks, type OpenTask } from './dashboard.ts';
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
  /** Every note, as a grid of cards (notes/AllNotesScreen.tsx); with `tapes`, only the notes with a recording, from the shelf's "and N more". */
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
 * notes", which is their See all), how many tapes are on the shelf, and how many to-dos before the rest are counted instead.
 */
const RECENT = 4;
const SHELF = 8;
const TASKS = 8;
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

          {/* The tapes, as cassettes on a shelf (docs/DESIGN.md §127). No group while there are none. */}
          {shelf.length ? (
            <section className={styles.section} aria-labelledby="home-tapes">
              <div className={styles.groupRow}>
                <h2 id="home-tapes" className={styles.group}>
                  <Cassette className={styles.groupMark} />
                  <span className={styles.groupName}>Tapes</span>
                </h2>
              </div>
              <TapeShelf
                notes={shelf}
                more={taped.length - shelf.length}
                gists={gists}
                onOpen={onOpen}
                onMore={() => onAllNotes({ tapes: true })}
                onGetModel={onGetModel ?? onSettings}
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
              <ol className={styles.cards}>{books.map((n, i) => card(n, i + pinned.length + shelfBeats))}</ol>
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
              <ol className={styles.cards}>{recent.map((n, i) => card(n, i + pinned.length + shelfBeats + books.length))}</ol>
            </section>
          ) : null}

          {open.length ? (
            <section className={styles.section} aria-labelledby="home-tasks">
              <div className={styles.groupRow}>
                <h2 id="home-tasks" className={styles.group}>
                  <TickBox className={styles.groupMark} />
                  <span className={styles.groupName}>To do</span>
                  <span className={styles.count}>· {open.length}</span>
                </h2>
              </div>
              <ul className={styles.tasks}>
                {open.slice(0, TASKS).map((task) => (
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
                      <span className={styles.taskNote}>{titleOf.get(task.noteId)}</span>
                    </button>
                  </li>
                ))}
              </ul>
              {open.length > TASKS ? <p className={styles.more}>and {open.length - TASKS} more in your notes</p> : null}
            </section>
          ) : allDone ? (
            <section className={styles.section} aria-labelledby="home-tasks">
              <div className={styles.groupRow}>
                <h2 id="home-tasks" className={styles.group}>
                  <TickBox className={styles.groupMark} />
                  <span className={styles.groupName}>To do</span>
                </h2>
              </div>
              <Ghost scene="all-ticked" className={styles.allDoneArt} />
              <p className={styles.allDoneWords}>Every to-do is done.</p>
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

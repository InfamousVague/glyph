import { useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties } from 'react';
import { Mic } from '@glacier/icons';
import { noteTitle, type Note } from '../core/store.ts';
import { longDay } from '../core/stamp.ts';
import { inWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import { usePreferences } from '../core/preferences.ts';
import type { VoiceModelState } from '../capture/useVoiceModel.ts';
import type { Updates } from '../core/ota.ts';
import { useGlideToTop } from '../core/glideToTop.ts';
import { isAndroid } from '../core/platform.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Ghost } from '../art/Ghost.tsx';
import { Cassette, Clock, Cog, Grid, Magnifier, Notebook, Pin, Plus, TickBox } from '../art/Icons.tsx';
import { NoteCard } from '../notes/NoteCard.tsx';
import { when } from '../notes/when.ts';
import { WorkspaceBar } from '../notes/WorkspaceBar.tsx';
import { WorkspaceSheet } from '../notes/WorkspaceSheet.tsx';
import { AcademyCard, RefiningNotice, UpdateNotice, VoiceModelStatus } from '../notes/Notices.tsx';
import { useGists } from '../format/gist.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { isTauri } from '../core/tauri.ts';
import { enqueueSummary, useSummaries } from '../ai/summaries.ts';
import { useRefining } from '../capture/refine.ts';
import {
  bookNotes,
  digest,
  openTasks,
  pinnedNotes,
  recentNotes,
  summaryKindOf,
  tapedNotes,
  tapesWaiting,
  tickedTasks,
  touchedToday,
  type DigestGo,
  type OpenTask,
} from './dashboard.ts';
import { TapeShelf } from './TapeShelf.tsx';
import { useMeetingLive } from './useMeetingLive.ts';
import { CAPS } from './tiers.ts';
import { useColumnTier } from './useColumnTier.ts';
import { bookIndex, placeOf } from '../book/book.ts';
import styles from './HomeScreen.module.css';

/**
 * The home page (Matt: "Add a 'home' button to take us to a dashboard like page"; he chose a new page on every screen,
 * the phone's start page included). The top bar's Glyph mark brings you here from anywhere.
 *
 * Redrawn as headed groups with room between them (docs/DESIGN.md §132; Matt: "The library and tapes headers on the
 * home page are different sizes, id like you to redo the home dashboard UI/UX to make it easier to digest everything
 * with cards and quick actions and summaries and better labeling. Right now it's just very data dense with no solid
 * organization and use of white space"). The date is the page's one title, with a digest under it of what is waiting;
 * then anything waiting on them (an update, the Academy's invitation, the voice model); then the groups, each under a
 * sentence-case heading with one mark beside it, in this order: the notes they pinned (Matt, §29g: pinned notes "in a
 * category above the rest"); every to-do not yet ticked, gathered from all of their notes into one card and ticked
 * here without opening the note, second because it is what is waiting, its tick is the page's one in-place action, and
 * a meeting's summary writes its actions there; the tapes the recorder made as a row of cards (home/TapeShelf.tsx;
 * Matt: "display them in a cassette shelf on the home page"), above the notebooks as §127 placed them; the
 * notebooks (the Library until §142); and the notes they were in last, four of them (six on a desk), running into
 * "All notes" at the foot, which opens the page that lists every note as a grid of the same cards
 * (notes/AllNotesScreen.tsx).
 *
 * Laid out by its own width (home/tiers.ts, docs/DESIGN.md §137; Matt: "Extend the dashboard to support wide phone /
 * tablet layouts too", and then: "It's okay if they're two across or the layout changes slightly on wide the four
 * column was a suggestion not a rule"): the phone's one column under 44rem; from there two of them across, with the
 * Fold's hinge in the gap between; and past 66rem a main two cards across beside a rail that holds To do. The groups
 * keep their order at every width, and the order they are read in is the order they are written in below.
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
  /** Settings open at Recording's Model card, where a language model is fetched: the shelf's "Get a model". Plain Settings when absent. */
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
 * How many tapes are on the shelf, at every width (one row on a phone, two rows of four on the wider screens), and how
 * many to-dos the card holds once "Show all" is pressed, before the rest are counted instead. How many of the notes
 * touched last are shown and how many to-dos before "Show all" are the page's width's to say (home/tiers.ts `CAPS`):
 * four and five on a phone, and the notes run straight into "All notes", which is their See all.
 */
const SHELF = 8;
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
  // Which of its layouts the page is in, by its own column's width (home/tiers.ts): how many notes and to-dos it holds.
  const page = useRef<HTMLDivElement>(null);
  const caps = CAPS[useColumnTier(page)];
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
  // The meeting being recorded now (home/useMeetingLive.ts): a tape while it is made, first on the shelf, not in Recent.
  const live = useMeetingLive();
  const pinned = useMemo(() => pinnedNotes(shown), [shown]);
  const recent = useMemo(() => recentNotes(shown, caps.recent, meetings, live), [shown, caps.recent, meetings, live]);
  // The tapes, the last recorded first; the shelf holds eight and says how many more there are (home/TapeShelf.tsx).
  const taped = useMemo(() => tapedNotes(shown, meetings, live), [shown, meetings, live]);
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
  // Opened out: Show all pressed and more open than the card holds. A tick can end it with Show all still on.
  const spread = showAll && open.length > caps.tasks;
  /*
   * The pair: one pinned card and To do side by side on two columns (HomeScreen.module.css `.grid[data-paired]`), while
   * To do is not opened out. Worked out here rather than asked of the page's shape by the sheet, since it is the page's
   * state, and the heading's hold below turns on it.
   */
  const paired = pinned.length === 1 && (open.length > 0 || allDone) && !spread;
  /*
   * A press on the card keeps its heading where it was on the screen. On two columns To do sits beside a single pinned
   * card, and opened out it spans the page under that card (HomeScreen.module.css), which moves its heading down by the
   * card's height, away from the thumb that pressed it; the tick that brings the count down to what the card holds
   * puts it back beside the card, which moves it up by as much, out from under the finger ticking the list off. So
   * Show all, Show fewer and a tick each note where the heading is, and after the commit the page scrolls by as much
   * as it moved. Where nothing moves (a phone, a desk's rail, a card that already spanned) that is nothing. A scroll
   * set, not a glide: the heading is meant to stay still, so there is nothing for reduced motion.
   */
  const tasksRow = useRef<HTMLDivElement>(null);
  const heldAt = useRef<number | null>(null);
  const holdTasks = () => {
    heldAt.current = tasksRow.current?.getBoundingClientRect().top ?? null;
  };
  // After every commit, and only the one a press asked for: a press is its own commit, since its updates are batched.
  useLayoutEffect(() => {
    const was = heldAt.current;
    heldAt.current = null;
    const row = tasksRow.current;
    const scroll = scroller.current;
    if (was === null || !row || !scroll) return;
    const moved = row.getBoundingClientRect().top - was;
    if (moved) scroll.scrollTop += moved;
  });
  // The To do card takes one beat between the pinned cards and the shelf.
  const todoBeats = open.length || allDone ? 1 : 0;

  // "Monday 28 September", as a journal's {{date}} writes the day (core/stamp.ts).
  const today = longDay(new Date());
  // The digest under the date: what is waiting, from what the page already holds (dashboard.ts `digest`). The tapes'
  // queues are the shelf's own sources, read here as well; two subscribers to one store is fine.
  const summaries = useSummaries();
  const refining = useRefining().pending;
  const waiting = useMemo(() => tapesWaiting(taped, { refining, summaries }), [taped, refining, summaries]);
  const touched = useMemo(() => touchedToday(shown), [shown]);
  const phrases = useMemo(() => digest({ open: open.length, waiting, touched }), [open.length, waiting, touched]);
  const hasNotes = shown.some((n) => !n.archivedAt);
  /**
   * A phrase tapped: the page glides to its group, or Settings opens at Recording's Model card for a missing model. A
   * group that is not on the page: nothing. The glide's target is fixed when it starts, so what is above the group must
   * hold its height while the page moves: a pinned card's peek lets its editor go as the card leaves the scroller, and
   * the blank that stands in is held at the editor's height (notes/NotePeek.tsx), or the heading landed 69px behind the
   * bar.
   */
  const glide = (go: DigestGo) => {
    if (go === 'model') return (onGetModel ?? onSettings)();
    const id = { tasks: 'home-tasks', tapes: 'home-tapes' }[go];
    // Optional-chained: jsdom has no scrollIntoView.
    document
      .getElementById(id)
      ?.closest('section')
      ?.scrollIntoView?.({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
  };

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
        <div ref={page} className={styles.page}>
          {/*
            The page's grid (HomeScreen.module.css, "The page laid out wide"): a plain block on a phone, where the
            wrappers lay out as if they were not there, and two columns, or a main and a rail, on the wider screens.
            Each group says which it is (`data-group`) for its place on them, and the grid whether Pinned and To do
            are a pair (`data-paired`).
          */}
          <div className={styles.grid} data-paired={paired ? '' : undefined}>
            <div className={styles.head}>
              <p className={styles.today}>{today}</p>
              {/* The digest: a row of fragments, each a word that goes to its group. Nothing while loading, and the ghost speaks on an empty page. */}
              {!loading && hasNotes ? (
                <ul className={styles.digest} aria-label="Today">
                  {phrases.map(({ text, go }) => (
                    <li key={text}>
                      {go ? (
                        <button type="button" className={`app-word ${styles.digestWord}`} onClick={() => glide(go)}>
                          {text}
                        </button>
                      ) : (
                        <span>{text}</span>
                      )}
                    </li>
                  ))}
                </ul>
              ) : null}
              <WorkspaceBar onManage={setManage} />
              <div className={styles.notices}>
                <UpdateNotice updates={updates} />
                <VoiceModelStatus state={voiceModel} onRetry={onRetryVoiceModel} />
                {showAcademy && onAcademy ? <AcademyCard onOpen={onAcademy} onHide={onHideAcademy} /> : null}
                <RefiningNotice />
              </div>
            </div>

            {!loading && !hasNotes ? (
              <div className={styles.empty}>
                <Ghost scene={spaces.current ? 'empty-workspace' : 'no-notes'} size="lead" className={styles.emptyArt} />
                <p className={styles.emptyLead}>{spaces.current ? `Nothing in ${spaces.current.name} yet.` : 'A blank page.'}</p>
                <p className={styles.emptyHint}>{isAndroid ? 'Write it, or hold the side key and say it.' : 'Write it, or tap Speak and say it.'}</p>
              </div>
            ) : null}

            {pinned.length ? (
              <section className={styles.section} data-group="pinned" aria-labelledby="home-pinned">
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
              meeting's summary writes its `- [ ]` actions here (§127). Five rows (eight in a desk's rail), most
              recently touched note's first, each with the note it lives in and when that note was touched; "Show all"
              opens the card to forty, which on two columns takes it out of the pair and spreads it across the page.
              With the last one ticked, the same card holds the ghost instead, under a heading with no count and no
              word.
            */}
            {open.length || allDone ? (
              <section className={styles.section} data-group="tasks" aria-labelledby="home-tasks">
                <div ref={tasksRow} className={styles.groupRow}>
                  <h2 id="home-tasks" className={styles.group}>
                    <TickBox className={styles.groupMark} />
                    <span className={styles.groupName}>To do</span>
                    {open.length ? (
                      <span className={styles.count}>
                        <span>·</span> {open.length}
                      </span>
                    ) : null}
                  </h2>
                  {open.length > caps.tasks ? (
                    <button
                      type="button"
                      className={`app-word ${styles.groupWord}`}
                      onClick={() => {
                        holdTasks();
                        setShowAll((was) => !was);
                      }}
                    >
                      {showAll ? 'Show fewer' : `Show all ${open.length}`}
                    </button>
                  ) : null}
                </div>
                <div className={styles.todo} style={{ '--i': Math.min(pinned.length, 8) } as CSSProperties}>
                  {open.length ? (
                    <>
                      <ul className={styles.tasks}>
                        {open.slice(0, showAll ? TASKS_OPEN : caps.tasks).map((task) => (
                          <li key={`${task.noteId}:${task.line}`} className={styles.task}>
                            <button
                              type="button"
                              className={styles.box}
                              aria-label={`Tick off ${task.text}`}
                              onClick={() => {
                                holdTasks();
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
                    </>
                  ) : (
                    <>
                      <Ghost scene="all-ticked" size="small" className={styles.allDoneArt} />
                      <p className={styles.allDoneWords}>Every to-do is done.</p>
                    </>
                  )}
                </div>
              </section>
            ) : null}

            {/* The tapes, as cards on a shelf (docs/DESIGN.md §127). No group while there are none. */}
            {shelf.length ? (
              <section className={styles.section} data-group="tapes" aria-labelledby="home-tapes">
                <div className={styles.groupRow}>
                  <h2 id="home-tapes" className={styles.group}>
                    <Cassette className={styles.groupMark} />
                    <span className={styles.groupName}>Tapes</span>
                    {taped.length > shelf.length ? (
                      <span className={styles.count}>
                        <span>·</span> {taped.length}
                      </span>
                    ) : null}
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
              <section className={styles.section} data-group="library" aria-labelledby="home-library">
                <div className={styles.groupRow}>
                  <h2 id="home-library" className={styles.group}>
                    <Notebook className={styles.groupMark} />
                    <span className={styles.groupName}>Notebooks</span>
                  </h2>
                </div>
                <ol className={styles.cards}>{books.map((n, i) => card(n, i + pinned.length + todoBeats + shelfBeats))}</ol>
              </section>
            ) : null}

            {recent.length ? (
              <section className={styles.section} data-group="recent" aria-labelledby="home-recent">
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

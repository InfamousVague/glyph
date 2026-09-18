import { useEffect, useRef, useState } from 'react';
import { Mic } from '@glacier/icons';
import { noteTitle, type Note } from '../core/store.ts';
import { inWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import type { VoiceModelState } from '../capture/useVoiceModel.ts';
import type { Updates } from '../core/ota.ts';
import { useGlideToTop } from '../core/glideToTop.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Blank } from '../art/Shapes.tsx';
import { Cog, Pin, Plus } from '../art/Icons.tsx';
import { NotePeek } from '../notes/NotePeek.tsx';
import { WorkspaceBar } from '../notes/WorkspaceBar.tsx';
import { WorkspaceSheet } from '../notes/WorkspaceSheet.tsx';
import { AcademyCard, RefiningNotice, UpdateCard, UpdateNotice, VoiceModelStatus } from '../notes/Notices.tsx';
import { when } from '../notes/when.ts';
import { shortenUrls } from '../core/shortUrl.ts';
import { openTasks, pinnedNotes, recentNotes, type OpenTask } from './dashboard.ts';
import styles from './HomeScreen.module.css';

/**
 * The home page (Matt: "Add a 'home' button to take us to a dashboard like page"; he chose a new page on every screen,
 * the phone's start page included). The top bar's Glyph mark brings you here from anywhere.
 *
 * What a person comes back to Glyph for, in the order they want it: anything waiting on them (an update, a memo to
 * sort, the voice model), the notes they pinned, the ones they were in last, and every to-do not yet ticked, gathered
 * from all of their notes - ticked here without opening the note. Every note is one tap away in the sidebar, so the
 * page does not list them all again; "All notes" opens it.
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
  /** Every note: the sidebar, which holds them all. */
  onAllNotes: () => void;
  /** A to-do ticked from here: its note's line rewritten with the box ticked. */
  onTick: (task: OpenTask) => void;
  voiceModel: VoiceModelState;
  onRetryVoiceModel: () => void;
  updates: Updates;
  memoWaiting?: boolean;
  onSortMemo?: () => void;
  showAcademy?: boolean;
  onAcademy?: () => void;
  onHideAcademy?: () => void;
}

/** How many of the notes touched last are shown, and how many to-dos before the rest are counted instead. */
const RECENT = 6;
const TASKS = 8;

export function HomeScreen({
  notes,
  loading,
  onOpen,
  onNew,
  onCapture,
  onSettings,
  onAllNotes,
  onTick,
  voiceModel,
  onRetryVoiceModel,
  updates,
  memoWaiting = false,
  onSortMemo,
  showAcademy = false,
  onAcademy,
  onHideAcademy,
}: HomeScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  useWispEdge(scroller, 'home', topBar);
  const spaces = useWorkspaces();
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  // Another workspace chosen: the page glides back to its top rather than jumping there.
  useGlideToTop(scroller, spaces.current?.id ?? 'all');
  // The chosen workspace chooses the page too, as it chose the list.
  const shown = inWorkspace(notes, spaces.current?.id ?? null);
  const pinned = pinnedNotes(shown);
  const recent = recentNotes(shown, RECENT);
  const tasks = openTasks(shown);
  const titleOf = new Map(notes.map((n) => [n.id, noteTitle(n.body) || 'Untitled']));
  // A tick lands on the page at once; the note catches up when it has been written.
  const [ticked, setTicked] = useState<ReadonlySet<string>>(new Set());
  // Once the notes have been read again they say it themselves, and a line number may now be another to-do's.
  useEffect(() => setTicked(new Set()), [notes]);
  const open = tasks.filter((t) => !ticked.has(`${t.noteId}:${t.line}`));

  const today = new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });

  const card = (note: Note, i: number) => {
    const title = noteTitle(note.body);
    return (
      <li key={note.id} className={styles.cardItem} style={{ '--i': Math.min(i, 8) } as React.CSSProperties}>
        <button type="button" className={styles.card} onClick={() => onOpen(note.id)}>
          <span className={styles.cardTitle} data-untitled={title ? undefined : ''}>
            {title ? shortenUrls(title) : 'Untitled'}
          </span>
          <NotePeek body={note.body} className={styles.cardPeek} />
          <span className={styles.cardWhen}>{when(note.updatedAt)}</span>
        </button>
      </li>
    );
  };

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
          {memoWaiting && onSortMemo ? <UpdateCard text="A memo is waiting to be sorted into your notes." action="Sort" onAction={onSortMemo} /> : null}
          <VoiceModelStatus state={voiceModel} onRetry={onRetryVoiceModel} />
          {showAcademy && onAcademy ? <AcademyCard onOpen={onAcademy} onHide={onHideAcademy} /> : null}
          <RefiningNotice />

          {!loading && shown.filter((n) => !n.archivedAt).length === 0 ? (
            <div className={styles.empty}>
              <Blank className={styles.emptyArt} />
              <p className={styles.emptyLead}>{spaces.current ? `Nothing in ${spaces.current.name} yet.` : 'A blank page.'}</p>
              <p className={styles.emptyHint}>Write it, or hold the side key and say it.</p>
            </div>
          ) : null}

          {pinned.length ? (
            <section aria-labelledby="home-pinned">
              <h2 id="home-pinned" className={styles.group}>
                <Pin className={styles.groupIcon} />
                Pinned
              </h2>
              <ol className={styles.cards}>{pinned.map(card)}</ol>
            </section>
          ) : null}

          {recent.length ? (
            <section aria-labelledby="home-recent">
              <h2 id="home-recent" className={styles.group}>
                Recent
              </h2>
              <ol className={styles.cards}>{recent.map((n, i) => card(n, i + pinned.length))}</ol>
            </section>
          ) : null}

          {open.length ? (
            <section aria-labelledby="home-tasks">
              <h2 id="home-tasks" className={styles.group}>
                To do <span className={styles.count}>{open.length}</span>
              </h2>
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
          ) : null}

          <button type="button" className={`app-word ${styles.allNotes}`} onClick={onAllNotes}>
            All notes · {notes.filter((n) => !n.archivedAt).length}
          </button>
        </div>
      </div>

      {/* The dock the notes list had: write on the left, Speak in the middle as the one ink pill, Settings on the right. */}
      <nav className={styles.dock} aria-label="New note">
        <button type="button" className={`${styles.round} ${styles.add}`} onClick={onNew} aria-label="Write a note">
          <Plus />
        </button>
        <button type="button" className={`app-pill ${styles.speak}`} onClick={onCapture} aria-label="Speak a voice note">
          <Mic size={18} strokeWidth={2.2} aria-hidden="true" />
          Speak
        </button>
        <button type="button" className={`${styles.round} ${styles.cog}`} onClick={onSettings} aria-label="Settings">
          <Cog />
        </button>
      </nav>
      <WorkspaceSheet which={manage} onClose={() => setManage(null)} />
    </div>
  );
}

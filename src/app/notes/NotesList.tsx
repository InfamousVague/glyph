import { useRef, useState } from 'react';
import { useBack } from '../core/back.ts';
import { archiveOrder, listOrder, noteTitle, type Note } from '../core/store.ts';
import { inWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import type { NoteActions } from './useNoteActions.ts';
import { useGists } from '../format/gist.ts';
import { groupsOf } from './groups.ts';
import { ArrowLeft, Cog, Pin, Plus } from '../art/Icons.tsx';
import { useRefining } from '../capture/refine.ts';
import { Blank, EmptyArchive } from '../art/Shapes.tsx';
import { useWispEdge } from '../art/wispEdge.ts';
import { Mic } from '@glacier/icons';
import { WorkspaceBar } from './WorkspaceBar.tsx';
import { WorkspaceSheet } from './WorkspaceSheet.tsx';
import { LinkMarks } from '../plugins/LinkMarks.tsx';
import { SwipeRow } from './SwipeRow.tsx';
import { shortenUrls } from '../core/shortUrl.ts';
import type { SwipeAction } from './swipe.ts';
import type { VoiceModelState } from '../capture/useVoiceModel.ts';
import type { Updates } from '../core/ota.ts';

/*
 * The page comes in from smoke (Matt: "the notes text should animate in with
 * the wisp effect and same with every title, offset them slightly so each
 * animation looks special but doesn't take all day"): the heading at a
 * hand's pace, then the first titles quick and each a beat after the last,
 * the rest simply there. A filter per settling letter is the cost, so only
 * the rows in view on a phone get it.
 */
import styles from './NotesList.module.css';

/**
 * Every note, newest first, set as type.
 *
 * The list is a table of contents rather than a stack of cards: each note's
 * first line at title size, a line of what follows, and when it was touched.
 * Nothing is boxed. Whitespace separates the rows, and the only chrome left is
 * the two ways to start a note, at the bottom where a thumb reaches them on a
 * phone held in one hand: a + on the left to write, Speak in the middle as
 * the screen's one ink pill, because talking is what Glyph is for, and
 * Settings as a cog on the right.
 *
 * The screen title scrolls away with the notes instead of pinning. A 60px
 * header that stayed put would take a fifth of a phone's height from the thing
 * it names. Nothing sits above the title: the count, Tapes and Settings that
 * used to were more words than the list needed (Matt: keep the main page
 * simple). Settings is a cog at the right of the dock; a spoken note's tape is at the top
 * of the note itself.
 *
 * A row is a plain `<button>`: one tap target with one accessible name. No
 * virtualisation yet - rows are variable height now that titles wrap, and a
 * list has to reach a thousand notes before that costs anything measurable.
 *
 * Rows swipe (SwipeRow): right to pin, left to archive, further left to
 * delete, each detent felt and shown. Pinned notes sit first, under a heading
 * that carries the pin - the rows themselves are not marked one by one
 * (Matt: "avoid individually repeatedly marking things like having a pin on
 * each note"). Archived notes
 * leave the list for an Archive view at its foot, where a swipe right restores
 * and a swipe left deletes. On a binary without flags (native generation < 3)
 * the only swipe is delete.
 *
 * Workspaces (core/workspaces.ts) are a row of names under the title once one
 * exists: the list shows the chosen workspace's notes, and All is the list as
 * it was. The archive is never filtered.
 */

interface NotesListProps {
  notes: Note[];
  loading: boolean;
  onOpen: (id: string) => void;
  /** A new note, typed. */
  onNew: () => void;
  /** Start a voice note: the same capture the side key opens. */
  onCapture: () => void;
  voiceModel: VoiceModelState;
  onRetryVoiceModel: () => void;
  updates: Updates;
  onSettings: () => void;
  actions: NoteActions;
  /** Star and archive exist on this binary. */
  canFlag: boolean;
  /** A memo was said and not yet sorted into notes (capture/scratch.ts): the card that opens its sorting. */
  memoWaiting?: boolean;
  onSortMemo?: () => void;
}

const DELETE: SwipeAction = { id: 'delete', label: 'Delete', icon: 'delete', tone: 'danger', detent: 0.55, removes: true };

function swipesFor(note: Note, view: 'notes' | 'archive', canFlag: boolean): { start: SwipeAction[]; end: SwipeAction[] } {
  if (view === 'archive') {
    return {
      start: [{ id: 'restore', label: 'Restore', icon: 'restore', tone: 'accent', detent: 0.22, removes: true }],
      end: [{ ...DELETE, detent: 0.3 }],
    };
  }
  if (!canFlag) return { start: [], end: [{ ...DELETE, detent: 0.3 }] };
  return {
    start: [{ id: 'pin', label: note.starred ? 'Unpin' : 'Pin', icon: note.starred ? 'unpin' : 'pin', tone: 'accent', detent: 0.22 }],
    end: [{ id: 'archive', label: 'Archive', icon: 'archive', tone: 'neutral', detent: 0.22, removes: true }, DELETE],
  };
}

/** A timestamp a person reads rather than parses. */
function when(ms: number, now = Date.now()): string {
  const delta = now - ms;
  const minute = 60_000;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (delta < minute) return 'Just now';
  if (delta < hour) return `${Math.floor(delta / minute)} min ago`;
  if (delta < day) return `${Math.floor(delta / hour)} hr ago`;
  if (delta < 2 * day) return 'Yesterday';
  if (delta < 7 * day) return new Date(ms).toLocaleDateString(undefined, { weekday: 'long' });
  return new Date(ms).toLocaleDateString(undefined, { month: 'long', day: 'numeric' });
}

export function NotesList({
  notes,
  loading,
  onOpen,
  onNew,
  onCapture,
  voiceModel,
  onRetryVoiceModel,
  updates,
  onSettings,
  actions,
  canFlag,
  memoWaiting = false,
  onSortMemo,
}: NotesListProps) {
  const [view, setView] = useState<'notes' | 'archive'>('notes');
  // The phone's back gesture: the archive steps back to the notes.
  useBack(view === 'archive', () => setView('notes'));
  const refining = useRefining();
  const scroller = useRef<HTMLDivElement>(null);
  // Notes going up under the status bar go to smoke (art/wispEdge.ts).
  useWispEdge(scroller);
  const spaces = useWorkspaces();
  // A workspace being added, or one open to rename or remove.
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  const live = notes.filter((n) => !actions.hidden.has(n.id));
  const archived = archiveOrder(live);
  const shown = view === 'archive' ? archived : inWorkspace(listOrder(live), spaces.current?.id ?? null);
  const count = shown.length;
  // One line under each title, what the note is about, written on the phone (format/gist.ts).
  const gists = useGists(shown);

  const act = (note: Note) => (id: string) => {
    if (id === 'pin') actions.pin(note);
    else if (id === 'archive') actions.archive(note, true);
    else if (id === 'restore') actions.archive(note, false);
    else if (id === 'delete') actions.remove(note);
  };
  return (
    <div className={styles.screen}>
      <div ref={scroller} className={styles.scroll}>
        <header className={styles.header}>
          {view === 'archive' ? (
            <div className={styles.topline}>
              <button type="button" className={`app-word ${styles.settings}`} onClick={() => setView('notes')}>
                <ArrowLeft /> Notes
              </button>
            </div>
          ) : null}
          {/* Plain: the smoke is kept for words being typed and deleted (Matt: "this animation is too much and takes too long, save it for things like typing and deleting"). */}
          <h1 className={styles.display}>{view === 'archive' ? 'Archive' : 'Notes'}</h1>
        </header>

        {view === 'notes' ? (
          <>
            <WorkspaceBar onManage={setManage} />
            <UpdateNotice updates={updates} />
            {memoWaiting && onSortMemo ? <UpdateCard text="A memo is waiting to be sorted into your notes." action="Sort" onAction={onSortMemo} /> : null}
            <VoiceModelStatus state={voiceModel} onRetry={onRetryVoiceModel} />
            {refining.download ? (
              <p className={styles.notice} role="status">
                Getting the better voice model, {Math.round(refining.download.received / 1e6)} of{' '}
                {Math.round(refining.download.total / 1e6)} MB.
              </p>
            ) : null}
          </>
        ) : null}

        {!loading && count === 0 ? (
          <div className={styles.empty}>
            {view === 'archive' ? (
              <>
                <EmptyArchive className={styles.emptyArt} />
                <p className={styles.emptyLead}>Nothing archived.</p>
              </>
            ) : spaces.current ? (
              <>
                <p className={styles.emptyLead}>Nothing in {spaces.current.name} yet.</p>
                <p className={styles.emptyHint}>Write one now, or file a note here from its settings.</p>
              </>
            ) : (
              <>
                <Blank className={styles.emptyArt} />
                <p className={styles.emptyLead}>A blank page.</p>
                <p className={styles.emptyHint}>Write it, or hold the side key and say it.</p>
              </>
            )}
          </div>
        ) : null}

        {loading ? (
          <ol className={styles.list} aria-busy="true" aria-label="Loading notes">
            {[0, 1, 2].map((i) => (
              <li key={i} className={styles.skeletonRow} style={{ '--i': i } as React.CSSProperties}>
                <span className={styles.skeletonTitle} style={{ inlineSize: `${64 - i * 14}%` }} />
                <span className={styles.skeletonMeta} />
              </li>
            ))}
          </ol>
        ) : null}

        {groupsOf(shown, view).map((group) => (
          <section key={group.key} aria-labelledby={group.label ? `notes-${group.key}` : undefined}>
            {group.label ? (
              <h2 id={`notes-${group.key}`} className={styles.group}>
                {group.key === 'pinned' ? <Pin className={styles.groupIcon} /> : null}
                {group.label}
              </h2>
            ) : null}
            <ol className={styles.list}>
              {group.notes.map((note) => {
                const i = shown.indexOf(note);
                const title = noteTitle(note.body);
                const { start, end } = swipesFor(note, view, canFlag);
                return (
                  <li key={note.id} className={styles.arrive} style={{ '--i': Math.min(i, 8) } as React.CSSProperties}>
                    <SwipeRow start={start} end={end} onAction={act(note)}>
                      <button type="button" className={styles.row} onClick={() => onOpen(note.id)}>
                        <span className={styles.rowTitle} data-untitled={title ? undefined : ''}>
                          {title ? shortenUrls(title) : 'Untitled'}
                        </span>
                        {gists[note.id] ? <span className={styles.rowGist}>{gists[note.id]}</span> : null}
                        <span className={styles.rowMeta}>
                          {when(view === 'archive' && note.archivedAt ? note.archivedAt : note.updatedAt)}
                          {/* Small ringed marks for what the note is linked to: a Notion board, a project (plugins/LinkMarks.tsx). */}
                          <LinkMarks noteId={note.id} compact />
                          {refining.pending.has(note.id) ? <span className={styles.improving}> · Improving</span> : null}
                        </span>
                      </button>
                    </SwipeRow>
                  </li>
                );
              })}
            </ol>
          </section>
        ))}

        {view === 'notes' && canFlag && archived.length ? (
          <button type="button" className={`app-word ${styles.archiveLink}`} onClick={() => setView('archive')}>
            Archive · {archived.length}
          </button>
        ) : null}
      </div>
      {/* The top of the list softens as the title scrolls under the status bar; the dock paints the bottom. */}

      {/*
        Three places, each with one job: a typed note on the left, a spoken
        note in the middle as the screen's one ink pill, Settings on the right.
        Speak sits at the centre so either thumb reaches it; the two quiet rings
        balance each other at the edges.
      */}
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

/**
 * A blue card when there is something newer to run: the one piece of colour on
 * the list, because on a black page a grey line under the title was easy to
 * miss (Matt: "it blends in too much with the dark background"). Only on the
 * list: a reload here costs nothing, where in the editor or mid-capture it
 * would be an interruption - and a cold start applies the update anyway.
 */
function UpdateNotice({ updates }: { updates: Updates }) {
  const { ready, apk } = updates;
  const mb = (bytes: number) => Math.round(bytes / 1e6);
  if (apk.kind === 'available' || apk.kind === 'failed' || apk.kind === 'needs-permission') {
    return (
      <UpdateCard
        text={
          apk.kind === 'failed'
            ? `Glyph ${apk.info.version} didn’t install. ${apk.message}`
            : apk.kind === 'needs-permission'
              ? 'Let Glyph install apps, then come back.'
              : `Glyph ${apk.info.version} is out.`
        }
        action={apk.kind === 'failed' ? 'Try again' : 'Install'}
        onAction={updates.installApk}
      />
    );
  }
  if (apk.kind === 'downloading') {
    return <UpdateCard text={`Downloading Glyph ${apk.info.version}, ${mb(apk.received)} of ${mb(apk.total)} MB.`} progress={apk.total ? apk.received / apk.total : 0} />;
  }
  if (apk.kind === 'installing') {
    // Android's own dialog is on top now; this is what is left if it is dismissed.
    return <UpdateCard text={`Glyph ${apk.info.version} is waiting on Android.`} action="Open" onAction={updates.installApk} />;
  }
  if (ready) {
    return <UpdateCard text="A new version of Glyph is ready." action="Reload" onAction={updates.reload} />;
  }
  return null;
}

function UpdateCard({ text, action, onAction, progress }: { text: string; action?: string; onAction?: () => void; progress?: number }) {
  return (
    <div className={styles.update} role="status">
      <p className={styles.updateText}>{text}</p>
      {action && onAction ? (
        <button type="button" className={styles.updateAction} onClick={onAction}>
          {action}
        </button>
      ) : null}
      {progress !== undefined ? (
        <span className={styles.updateBar} aria-hidden="true">
          <span style={{ inlineSize: `${Math.round(Math.min(1, Math.max(0, progress)) * 100)}%` }} />
        </span>
      ) : null}
    </div>
  );
}

/**
 * One line under the title while voice notes cannot work yet, and nothing at
 * all once they can. Visible because the alternative - a side key that opens a
 * capture screen which then sits downloading - is the first impression of the
 * feature the app exists for.
 */
function VoiceModelStatus({ state, onRetry }: { state: VoiceModelState; onRetry: () => void }) {
  if (state.kind === 'ready' || state.kind === 'unsupported' || state.kind === 'checking') return null;
  if (state.kind === 'downloading') {
    const mb = (bytes: number) => Math.round(bytes / 1e6);
    return (
      <p className={styles.notice} role="status">
        Downloading the voice model, {mb(state.received)} of {mb(state.total)} MB. Keep Glyph open.
      </p>
    );
  }
  return (
    <p className={styles.notice} role="alert">
      The voice model didn’t download.{' '}
      <button type="button" className={`app-word ${styles.noticeAction}`} onClick={onRetry}>
        Try again
      </button>
    </p>
  );
}

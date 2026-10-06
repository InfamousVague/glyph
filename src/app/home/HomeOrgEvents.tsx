import { useMemo, type ReactNode } from 'react';
import { Activity, FileText } from '@glacier/icons';
import { usePresence } from '../core/live/presence.ts';
import { useNotifications } from '../core/notifications/feed.ts';
import { KIND_HUES, sentenceOf } from '../core/notifications/kinds.ts';
import { noteTitle } from '../core/noteTitle.ts';
import type { Note } from '../core/store.ts';
import { orgWorkspaceId, useWorkspaces } from '../core/workspaces.ts';
import { MARKS, NEWS } from '../notes/orgNews.tsx';
import { when } from '../notes/when.ts';
import styles from './HomeOrgEvents.module.css';

/**
 * What has happened lately in the organization the home page is filtered to (Matt: "On the home page add a right side
 * docked card somewhere with recent events in the org when an organization is selected"): who is editing what right
 * now, the notes of its workspace as they change, and the team's news - who joined, left, a new role, a rename - in
 * one list, newest first. Docked to the right of the notes on a wide window, and over them on a narrow one. A note's
 * line opens the note; the foot opens the organization's dashboard.
 */

/** How many lines the card shows. */
const MOST = 8;

interface Line {
  key: string;
  at: number;
  mark: ReactNode;
  words: string;
  note?: string;
  live?: boolean;
  /** The colour its mark wears: a kind of news's (core/notifications/kinds.ts `KIND_HUES`). */
  hue?: string;
}

export function HomeOrgEvents({ orgId, name, notes, onOpenNote, onOpen }: { orgId: string; name: string; notes: readonly Note[]; onOpenNote: (id: string) => void; onOpen: (orgId: string) => void }) {
  const feed = useNotifications();
  const seen = usePresence(orgId);
  const { of: filed } = useWorkspaces();
  const workspace = orgWorkspaceId(orgId);
  const lines = useMemo(() => {
    const editing: Line[] = seen
      .filter((each) => each.at)
      .map((each) => ({ key: `live-${each.client}`, at: Number.MAX_SAFE_INTEGER, mark: <span className={styles.dot} data-hue={each.hue ?? 'ink'} />, words: `${each.handle} is editing ${each.at!.title || 'a note'}`, note: each.at!.note, live: true }));
    const changed: Line[] = notes
      .filter((note) => filed[note.id] === workspace && !note.archivedAt)
      .map((note) => ({ key: `note-${note.id}`, at: note.updatedAt, mark: <FileText size={15} strokeWidth={2} aria-hidden="true" />, words: `${noteTitle(note.body) || 'An untitled note'} changed`, note: note.id }));
    const news: Line[] = feed.filter((n) => n.org?.id === orgId && NEWS.has(n.kind)).map((n) => ({ key: `news-${n.id}`, at: n.at, mark: MARKS[n.kind] ?? null, words: sentenceOf(n, null), hue: KIND_HUES[n.kind] }));
    return [...editing, ...[...changed, ...news].sort((a, b) => b.at - a.at)].slice(0, MOST);
  }, [seen, notes, filed, workspace, feed, orgId]);
  return (
    <aside className={styles.card} aria-labelledby="home-org-events" data-section="org-events">
      <h2 id="home-org-events" className={styles.heading}>
        <Activity size={15} aria-hidden="true" />
        Recent in {name}
      </h2>
      {lines.length ? (
        <ol className={styles.lines} aria-label={`Recent in ${name}`}>
          {lines.map((line) => (
            <li key={line.key} className={styles.line} data-live={line.live || undefined}>
              <span className={styles.mark} data-hue={line.hue}>{line.mark}</span>
              {line.note ? (
                <button type="button" className={styles.words} onClick={() => onOpenNote(line.note!)}>
                  {line.words}
                </button>
              ) : (
                <span className={styles.words}>{line.words}</span>
              )}
              <span className={styles.when}>{line.live ? 'now' : when(line.at)}</span>
            </li>
          ))}
        </ol>
      ) : (
        <p className={styles.none}>Nothing has happened here yet.</p>
      )}
      <button type="button" className={`app-word ${styles.more}`} onClick={() => onOpen(orgId)}>
        Open {name}
      </button>
    </aside>
  );
}

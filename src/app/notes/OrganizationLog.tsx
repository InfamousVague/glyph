import { useMemo, useRef, useState } from 'react';
import { ArrowLeft, FileText, ListFilter, Search, X } from '@glacier/icons';
import { useBack } from '../core/back.ts';
import { agoText } from '../core/markDetails.ts';
import { noteTitle } from '../core/noteTitle.ts';
import { useNotifications } from '../core/notifications/feed.ts';
import { sentenceOf, type Notification } from '../core/notifications/kinds.ts';
import { useOrgs } from '../core/orgs/orgs.ts';
import { usePreferences } from '../core/preferences.ts';
import type { Note } from '../core/store.ts';
import { useChangesAcross, type Change } from '../core/versions/log.ts';
import { useVersions } from '../core/versions/record.ts';
import { orgWorkspaceId, useWorkspaces } from '../core/workspaces.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Ghost } from '../art/Ghost.tsx';
import { Author, Change as Diff } from '../editor/VersionHistory.tsx';
import { authorName, clock, dayOf } from '../editor/versionWords.ts';
import { MARKS, NEWS } from './orgNews.tsx';
import styles from './OrganizationLog.module.css';

/**
 * An organization's audit log (Matt: "an "audit log" for organizations to be able to browse history of changes
 * across all files"): a page under its dashboard (OrganizationScreen.tsx) with every change to every note filed in
 * its workspace - each version kept of each note (core/versions/log.ts), since an organization's notes keep their
 * history by default (core/versions/record.ts) - and the team's own news from the feed between them, newest first
 * under the day it happened, on the version history's timeline (editor/VersionHistory.tsx).
 *
 * Each change is who, what they did (created, edited, named a version of) and to which note, when, "+3 −1" and the
 * first line it changed; the team's news is its sentence with the kind's mark where an author's initial would be.
 * Over the timeline a field narrows the log to a note, a person or a version's name, and three pills show
 * everything, the notes alone or the team alone. A change opened is what that version changed against the one
 * before, line by line as the history shows it, with the way to the note and to only that note's changes. The
 * figures under the tools say how much there is, and which of the workspace's notes keep no history.
 *
 * The notes are the person's own (docs/TEAMS.md: notes filed in an organization stay theirs for now), so the log is
 * their own changes on their devices, with what the team did around them; shared notes will bring the others' in.
 */

interface OrganizationLogProps {
  orgId: string;
  /** The notes this device holds (not the trash), of which those filed in the organization's workspace are logged. */
  notes: readonly Note[];
  /** The dashboard. */
  onBack: () => void;
  onOpenNote: (id: string) => void;
}

/** What the log shows: everything, the notes' changes alone, or the team's news alone. */
type Shown = 'all' | 'notes' | 'team';
const KINDS: readonly [Shown, string][] = [
  ['all', 'Everything'],
  ['notes', 'Notes'],
  ['team', 'Team'],
];

/** A line of the log: a change to a note, or a piece of the team's news. */
type Entry = { key: string; at: number; change: Change; news?: undefined } | { key: string; at: number; news: Notification; change?: undefined };

/** "Roadmap", "Roadmap and Standup", "Roadmap, Standup and Groceries". */
function listWords(words: readonly string[]): string {
  if (words.length <= 1) return words[0] ?? '';
  return `${words.slice(0, -1).join(', ')} and ${words[words.length - 1]}`;
}

const count = (n: number, one: string, many: string) => (n === 1 ? `1 ${one}` : `${n} ${many}`);

/** What a change did to its note, as the row says it. */
const didWords = (change: Change) => (change.first ? 'created' : change.added || change.removed ? 'edited' : 'named a version of');

export function OrganizationLog({ orgId, notes, onBack, onOpenNote }: OrganizationLogProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  const field = useRef<HTMLInputElement>(null);
  useWispEdge(scroller, `log:${orgId}`, topBar);
  const { list } = useOrgs();
  const { of: filed } = useWorkspaces();
  const prefs = usePreferences();
  const feed = useNotifications();
  const row = list.find((each) => each.id === orgId) ?? null;
  const name = row?.name ?? 'the organization';

  // The notes filed in its workspace, the archived among them: their changes happened too.
  const workspaceId = orgWorkspaceId(orgId);
  const here = useMemo(() => notes.filter((note) => filed[note.id] === workspaceId), [notes, filed, workspaceId]);
  const ids = useMemo(() => here.map((note) => note.id), [here]);
  const titles = useMemo(() => new Map(here.map((note) => [note.id, noteTitle(note.body) || 'Untitled'])), [here]);
  const read = useChangesAcross(ids);
  const news = useMemo(() => feed.filter((n) => n.org?.id === orgId && NEWS.has(n.kind)), [feed, orgId]);
  // Switched off from their More (core/versions/record.ts): their changes since are not here, and the page says so.
  const off = useMemo(() => here.filter((note) => prefs.versions[note.id] === false), [here, prefs.versions]);

  const [shown, setShown] = useState<Shown>('all');
  const [query, setQuery] = useState('');
  const [only, setOnly] = useState<string | null>(null);
  const [opened, setOpened] = useState<Change | null>(null);
  useBack(true, () => (opened ? setOpened(null) : onBack()));
  // A change opened, or the log again, starts at the top; the list's own place is not kept, as the history's is not.
  const open = (change: Change | null) => {
    setOpened(change);
    if (scroller.current) scroller.current.scrollTop = 0;
  };

  const q = query.trim().toLowerCase();
  const entries = useMemo(() => {
    const all: Entry[] = [];
    if (shown !== 'team') for (const change of read.changes) all.push({ key: `${change.noteId}:${change.n}`, at: change.at, change });
    if (shown !== 'notes' && !only) for (const n of news) all.push({ key: n.id, at: n.at, news: n });
    all.sort((a, b) => b.at - a.at);
    return all.filter((entry) => {
      if (entry.change) {
        if (only && entry.change.noteId !== only) return false;
        if (!q) return true;
        return [titles.get(entry.change.noteId) ?? '', authorName(entry.change.by), entry.change.label ?? ''].some((words) => words.toLowerCase().includes(q));
      }
      return !q || sentenceOf(entry.news).toLowerCase().includes(q);
    });
  }, [read.changes, news, shown, only, q, titles]);
  const days = useMemo(() => {
    const out: { day: string; entries: Entry[] }[] = [];
    for (const entry of entries) {
      const day = dayOf(entry.at);
      const last = out[out.length - 1];
      if (last && last.day === day) last.entries.push(entry);
      else out.push({ day, entries: [entry] });
    }
    return out;
  }, [entries]);

  const people = useMemo(() => new Set(read.changes.map((change) => change.by)).size, [read.changes]);
  const reading = read.read < read.total;
  const narrowed = shown !== 'all' || q !== '' || only !== null;
  const figures = reading
    ? `Reading the history… ${read.read} of ${count(read.total, 'note', 'notes')}`
    : `${count(read.changes.length, 'change', 'changes')} across ${count(here.length, 'note', 'notes')}${people ? ` · ${count(people, 'person', 'people')}` : ''}${narrowed ? ` · ${count(entries.length, 'line', 'lines')} shown` : ''}`;
  const asides = [
    off.length ? `History is off for ${listWords(off.slice(0, 3).map((note) => titles.get(note.id) ?? 'Untitled'))}${off.length > 3 ? ` and ${count(off.length - 3, 'more', 'more')}` : ''}.` : null,
    read.damaged ? (read.damaged === 1 ? 'One version couldn’t be read, and is left out.' : `${read.damaged} versions couldn’t be read, and are left out.`) : null,
  ].filter((words): words is string => words !== null);

  return (
    <div className={styles.screen} data-hue={row?.hue ?? 'ink'}>
      <header ref={topBar} className={`app-headerPane ${styles.topBar}`}>
        <button type="button" className={styles.back} onClick={onBack} aria-label={`Back to ${name}`}>
          <ArrowLeft size={20} aria-hidden="true" />
        </button>
        <h1 className={styles.title}>
          <span className={styles.titleHue} data-hue={row?.hue ?? 'ink'} aria-hidden="true" />
          <span className={styles.titleName}>{row?.name ?? 'Organization'}</span>
          <span className={styles.titleWhat}>Audit log</span>
        </h1>
      </header>
      <div ref={scroller} className={styles.scroll}>
        <div className={styles.page}>
          {opened ? (
            <Opened
              key={`${opened.noteId}:${opened.n}`}
              change={opened}
              title={titles.get(opened.noteId) ?? 'Untitled'}
              onBack={() => open(null)}
              onOpenNote={() => onOpenNote(opened.noteId)}
              onOnly={() => {
                setOnly(opened.noteId);
                setShown('all');
                open(null);
              }}
            />
          ) : (
            <>
              <div className={styles.tools}>
                <div className={styles.search} data-filled={q !== '' || undefined}>
                  <Search size={16} strokeWidth={2.2} className={styles.searchMark} aria-hidden="true" />
                  <input
                    ref={field}
                    type="search"
                    className={styles.field}
                    value={query}
                    onChange={(event) => setQuery(event.target.value)}
                    placeholder="Filter by note, person or name"
                    aria-label="Filter the log"
                    autoComplete="off"
                    autoCorrect="off"
                    autoCapitalize="off"
                    spellCheck={false}
                    enterKeyHint="search"
                  />
                  {q ? (
                    <button
                      type="button"
                      className={styles.clear}
                      aria-label="Clear the filter"
                      onClick={() => {
                        setQuery('');
                        field.current?.focus();
                      }}
                    >
                      <X size={14} strokeWidth={2.4} aria-hidden="true" />
                    </button>
                  ) : null}
                </div>
                <div className={styles.kinds} role="group" aria-label="What the log shows">
                  {KINDS.map(([value, words]) => (
                    <button key={value} type="button" className={styles.pill} aria-pressed={shown === value} onClick={() => setShown(value)}>
                      {words}
                    </button>
                  ))}
                  {only ? (
                    <button type="button" className={styles.pill} data-only onClick={() => setOnly(null)} aria-label={`Only ${titles.get(only) ?? 'one note'}; press for every note`}>
                      <FileText size={13} strokeWidth={2.2} aria-hidden="true" />
                      {titles.get(only) ?? 'One note'}
                      <X size={13} strokeWidth={2.4} aria-hidden="true" />
                    </button>
                  ) : null}
                </div>
              </div>
              <p className={styles.figures} role="status">
                {figures}
              </p>
              {asides.map((words) => (
                <p key={words} className={styles.aside}>
                  {words}
                </p>
              ))}
              {days.length ? (
                <div className={styles.timeline}>
                  {days.map(({ day, entries: those }) => (
                    <section key={day} aria-label={day}>
                      <h2 className={styles.dayName}>{day}</h2>
                      <ol className={styles.entries}>
                        {those.map((entry) => (entry.change ? <ChangeLine key={entry.key} change={entry.change} title={titles.get(entry.change.noteId) ?? 'Untitled'} onOpen={open} /> : <NewsLine key={entry.key} n={entry.news} />))}
                      </ol>
                    </section>
                  ))}
                </div>
              ) : reading ? null : (
                <div className={styles.empty}>
                  <Ghost scene={narrowed ? 'search-nothing' : 'empty-workspace'} size="small" className={styles.emptyArt} />
                  <p className={styles.emptyLead}>{narrowed ? 'Nothing matches.' : 'Nothing has changed here yet.'}</p>
                  <p className={styles.emptyHint}>{narrowed ? 'Try other words, or show everything again.' : `Every version of a note filed in ${name}, and what the team does, shows here as it happens.`}</p>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

/** A change on the timeline: its author's ring, who did what to which note, when, its name, how much and the first line. */
function ChangeLine({ change, title, onOpen }: { change: Change; title: string; onOpen: (change: Change) => void }) {
  const did = didWords(change);
  return (
    <li className={styles.entry}>
      <button type="button" className={styles.entryButton} onClick={() => onOpen(change)} aria-label={`${authorName(change.by)} ${did} ${title}, version ${change.n}${change.label ? `, ${change.label}` : ''}, ${agoText(change.at)}`}>
        <Author by={change.by} />
        <span className={styles.entryBody}>
          <span className={styles.entryHead}>
            <span className={styles.who}>{authorName(change.by)}</span>
            <span className={styles.did}>{did}</span>
            <span className={styles.noteName}>{title}</span>
            <span className={styles.when}>{clock(change.at)}</span>
            {change.label ? <span className={styles.label}>{change.label}</span> : null}
          </span>
          <span className={styles.entryWhat}>
            <span className={styles.counts}>{change.first ? 'First version' : change.added || change.removed ? `+${change.added} −${change.removed}` : 'Named'}</span>
            {change.peek ? (
              <span className={styles.peek} data-kind={change.peek.kind}>
                {change.peek.kind === 'add' ? '+ ' : '− '}
                {change.peek.text}
              </span>
            ) : null}
          </span>
        </span>
        <span className={styles.number}>v{change.n}</span>
      </button>
    </li>
  );
}

/** A piece of the team's news on the same line: the kind's mark in a ring, its sentence as the drawer words it, when. */
function NewsLine({ n }: { n: Notification }) {
  return (
    <li className={styles.entry}>
      <div className={styles.newsRow}>
        <span className={styles.newsRing} aria-hidden="true">
          {MARKS[n.kind] ?? null}
        </span>
        <span className={styles.entryBody}>
          <span className={styles.entryHead}>
            <span className={styles.newsWords}>{sentenceOf(n)}</span>
            <span className={styles.when}>{clock(n.at)}</span>
          </span>
        </span>
      </div>
    </li>
  );
}

/**
 * A change opened: what that version changed against the one before, read from the note's file now (the log keeps
 * only each change's line), with the way to the note and to only its changes. Mounted afresh for each change opened.
 */
function Opened({ change, title, onBack, onOpenNote, onOnly }: { change: Change; title: string; onBack: () => void; onOpenNote: () => void; onOnly: () => void }) {
  const read = useVersions(change.noteId);
  const versions = read?.versions ?? [];
  const version = versions.find((each) => each.n === change.n && each.at === change.at) ?? null;
  const before = version ? (versions[version.n - 2]?.text ?? null) : null;
  return (
    <div>
      <button type="button" className={styles.toLog} onClick={onBack}>
        <ArrowLeft /> The log
      </button>
      <h2 className={styles.openedTitle}>
        {title}
        <span className={styles.openedVersion}>{` · Version ${change.n}${change.label ? ` · ${change.label}` : ''}`}</span>
      </h2>
      <div className={styles.byline}>
        <Author by={change.by} />
        <span>
          <span className={styles.who}>{authorName(change.by)}</span>
          {` ${didWords(change)} it · ${new Date(change.at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}`}
        </span>
      </div>
      <h3 className={styles.heading}>{change.first ? 'The note as it began' : 'What this version changed'}</h3>
      {read === null ? (
        <p className={styles.quiet}>Reading the version…</p>
      ) : !version ? (
        <p className={styles.quiet}>This version is not in the note’s file any more.</p>
      ) : change.first && !version.text.trim() ? (
        <p className={styles.quiet}>It began empty.</p>
      ) : (
        <Diff from={before} to={version.text} label="What this version changed" same="The same words as the version before, named." />
      )}
      <div className={styles.openedActions}>
        <button type="button" className={styles.action} onClick={onOpenNote}>
          <FileText size={15} strokeWidth={2.1} aria-hidden="true" />
          Open the note
        </button>
        <button type="button" className={styles.action} onClick={onOnly}>
          <ListFilter size={15} strokeWidth={2.1} aria-hidden="true" />
          Only this note
        </button>
      </div>
    </div>
  );
}

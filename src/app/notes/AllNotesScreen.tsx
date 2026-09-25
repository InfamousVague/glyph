import { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowLeft, Search, X } from '@glacier/icons';
import type { Note } from '../core/store.ts';
import { inWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import { useBack } from '../core/back.ts';
import { useGlideToTop } from '../core/glideToTop.ts';
import { isAndroid } from '../core/platform.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { Ghost } from '../art/Ghost.tsx';
import { ArchiveBox } from '../art/Icons.tsx';
import { bookIndex, placeOf } from '../book/book.ts';
import { useGists } from '../format/gist.ts';
import { NoteCard } from './NoteCard.tsx';
import { WorkspaceBar } from './WorkspaceBar.tsx';
import { WorkspaceSheet } from './WorkspaceSheet.tsx';
import { archivedCount, browseNotes, readSort, SORTS, writeSort, type AllNotesSort } from './allNotes.ts';
import styles from './AllNotesScreen.module.css';

/**
 * Every note, as a page of cards (Matt: "Browsing all notes is super hard there is no good UI it just opens in the
 * sidebar, I'd like a grid view of all the notes in the 'all notes' section").
 *
 * The home page's "All notes" used to open the sidebar, which is a tree for jumping to a note you already know by name;
 * for looking through what there is, it was a column of small rows over the page. This is a page of its own: the cards
 * the home page draws (notes/NoteCard.tsx), in its grid - one to a row on a phone, three or four on the Fold opened out,
 * four in a desktop window - with a search over the notes' words in the bar, the workspace pills choosing which notes, the order
 * (last touched, or by name), and the archive shown when asked for. A tap on a card opens the note; the arrow, the
 * phone's back gesture and the tab row's house all go home.
 *
 * The rules - what the search finds, the order, the archive - are notes/allNotes.ts, which the tests read.
 */

interface AllNotesScreenProps {
  notes: Note[];
  loading: boolean;
  onOpen: (id: string) => void;
  /** Home. */
  onBack: () => void;
}

/** How many of the cards on the page have their gist written (format/gist.ts): the first screens of them, not every note there is. */
const GISTED = 24;

export function AllNotesScreen({ notes, loading, onOpen, onBack }: AllNotesScreenProps) {
  const scroller = useRef<HTMLDivElement>(null);
  const topBar = useRef<HTMLElement>(null);
  const field = useRef<HTMLInputElement>(null);
  useWispEdge(scroller, 'all-notes', topBar);
  useBack(true, onBack);
  const spaces = useWorkspaces();
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<AllNotesSort>(readSort);
  const [archived, setArchived] = useState(false);
  const workspace = spaces.current?.id ?? null;
  // Another workspace, order or archive chosen: the page glides back to its top rather than jumping there.
  useGlideToTop(scroller, `${workspace ?? 'all'}|${sort}|${archived ? 'archive' : ''}`);
  const inSpace = useMemo(() => inWorkspace(notes, workspace), [notes, workspace]);
  const shown = useMemo(() => browseNotes(inSpace, { query, sort, archived }), [inSpace, query, sort, archived]);
  const inArchive = useMemo(() => archivedCount(inSpace), [inSpace]);
  /** Every page's book, for the cards' marks (book/book.ts). */
  const inBooks = useMemo(() => bookIndex(notes), [notes]);
  const gisted = useMemo(() => shown.slice(0, GISTED), [shown]);
  const gists = useGists(gisted);
  // The order chosen is kept for next time.
  useEffect(() => writeSort(sort), [sort]);

  const live = inSpace.filter((n) => !n.archivedAt).length;
  const searched = query.trim() !== '';

  return (
    <div className={styles.screen}>
      <header ref={topBar} className={`app-headerPane ${styles.topBar}`}>
        <button type="button" className={styles.back} onClick={onBack} aria-label="Back to home">
          <ArrowLeft size={20} aria-hidden="true" />
        </button>
        <h1 className={styles.saidOnly}>All notes</h1>
        {/* The search, the page's main tool, in the bar where it stays as the cards scroll under it. */}
        <div className={styles.search} data-filled={searched || undefined}>
          <Search size={16} strokeWidth={2.2} className={styles.searchMark} aria-hidden="true" />
          <input
            ref={field}
            type="search"
            className={styles.field}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search your notes"
            aria-label="Search your notes"
            autoComplete="off"
            autoCorrect="off"
            autoCapitalize="off"
            spellCheck={false}
            enterKeyHint="search"
          />
          {searched ? (
            <button
              type="button"
              className={styles.clear}
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
      </header>
      <div ref={scroller} className={styles.scroll}>
        <div className={styles.page}>
          <WorkspaceBar onManage={setManage} />
          {/* The order, and the archive: one line of words over the cards. */}
          <div className={styles.controls}>
            <div className={styles.sorts} role="radiogroup" aria-label="Order">
              {SORTS.map((each) => (
                <button
                  key={each.id}
                  type="button"
                  role="radio"
                  aria-checked={sort === each.id}
                  className={styles.sortWord}
                  onClick={() => setSort(each.id)}
                >
                  {each.label}
                </button>
              ))}
            </div>
            <p className={styles.tally} aria-live="polite">
              {searched ? `${shown.length} of ${live + (archived ? inArchive : 0)}` : shown.length === 1 ? '1 note' : `${shown.length} notes`}
            </p>
            {inArchive ? (
              <button type="button" className={styles.archiveWord} aria-pressed={archived} onClick={() => setArchived((was) => !was)}>
                <ArchiveBox className={styles.archiveMark} />
                Archived · {inArchive}
              </button>
            ) : null}
          </div>

          {!loading && !searched && live === 0 && !archived ? (
            <div className={styles.empty}>
              <Ghost scene={spaces.current ? 'empty-workspace' : 'no-notes'} size="lead" className={styles.emptyArt} />
              <p className={styles.emptyLead}>{spaces.current ? `Nothing in ${spaces.current.name} yet.` : 'A blank page.'}</p>
              <p className={styles.emptyHint}>{isAndroid ? 'Write it, or hold the side key and say it.' : 'Write it, or tap Speak and say it.'}</p>
            </div>
          ) : searched && shown.length === 0 ? (
            <div className={styles.empty}>
              <Ghost scene="search-nothing" size="lead" className={styles.emptyArt} />
              <p className={styles.emptyLead}>Nothing has “{query.trim()}”.</p>
              <p className={styles.emptyHint}>{archived || !inArchive ? 'Try fewer words.' : 'Try fewer words, or look in the archive.'}</p>
            </div>
          ) : null}

          {shown.length ? (
            <ol className={styles.cards} aria-label="Notes">
              {shown.map((note, i) => (
                <NoteCard key={note.id} note={note} index={i} onOpen={onOpen} gist={gists[note.id]} place={placeOf(inBooks, note)} dense />
              ))}
            </ol>
          ) : null}
        </div>
      </div>
      <WorkspaceSheet which={manage} onClose={() => setManage(null)} />
    </div>
  );
}

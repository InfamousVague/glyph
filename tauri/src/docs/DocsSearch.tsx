import { useCallback, useEffect, useId, useMemo, useRef, useState, type KeyboardEvent } from 'react';
import { flushSync } from 'react-dom';
import { Search, X } from '@glacier/icons';
import type { SiteTarget } from '../read/Site.tsx';
import { DOCS_BASE, docsSearchIndex, type DocsIndex } from './book.ts';
import { DOCS } from './content.ts';
import { prepare, searchDocs, type Part, type Prepared } from './search.ts';
import styles from './DocsSearch.module.css';

/**
 * The docs' search box, in the bar (Matt, 2026-10-26: "add the ability to search the book"): results as you type,
 * across every chapter, each its chapter, its section's heading and a few words round what was found, the found words
 * marked; Enter or a click opens the section at its heading with the words marked there too (reveal.ts).
 *
 * `/` or ⌘K (Ctrl-K) comes to it from anywhere on the page, the arrows go through the results, Enter opens one and
 * Escape closes them, then leaves the box. A combobox over a listbox, as a screen reader expects one: the results are
 * options, the one the arrows are on is the active descendant, and how many there are is said as they change.
 *
 * On a phone the box is a button in the bar, which opens it across the bar, the results under it the page's width.
 *
 * The index is /docs/search.json, written by the build (book.ts `docsSearchIndex`), fetched the first time the box
 * is used. Where it cannot be fetched (offline, or the dev server, which has none) the same index is made here from
 * the book the page already holds (content.ts), so the search never needs the network.
 */

let ready: Promise<Prepared> | null = null;

function loadIndex(): Promise<Prepared> {
  ready ??= fetch(`${DOCS_BASE}search.json`)
    .then((r) => (r.ok ? (r.json() as Promise<DocsIndex>) : Promise.reject(new Error(String(r.status)))))
    .then((index) => (index.v === 1 && Array.isArray(index.sections) ? index : docsSearchIndex(DOCS)))
    .catch(() => docsSearchIndex(DOCS))
    .then(prepare);
  return ready;
}

/** Typing somewhere a `/` is a letter: a field, or anything editable. The docs' own pages are read-only. */
function typing(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  return target.closest('input, textarea, select, [contenteditable="true"]') !== null;
}

function Marked({ parts }: { parts: Part[] }) {
  return (
    <>
      {parts.map((part, i) =>
        part.hit ? (
          <mark key={i} className={styles.hit}>
            {part.text}
          </mark>
        ) : (
          <span key={i}>{part.text}</span>
        ),
      )}
    </>
  );
}

export function DocsSearch({ open }: { open: (slug: string, target: SiteTarget) => void }) {
  const [query, setQuery] = useState('');
  const [index, setIndex] = useState<Prepared | null>(null);
  const [shown, setShown] = useState(false);
  // On a phone, whether the box is open across the bar.
  const [wide, setWide] = useState(false);
  const [active, setActive] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLUListElement>(null);
  const id = useId();
  const listId = `${id}-results`;

  const hits = useMemo(() => (index && query.trim() ? searchDocs(index, query) : []), [index, query]);
  const showing = shown && query.trim().length > 0;

  const begin = () => {
    void loadIndex().then(setIndex);
  };

  /**
   * The box opened and the caret in it at once, in the tap or the key that asked: a phone's keyboard comes up only
   * for a field focused while its tap is being handled, so the box is drawn first (flushSync), then focused.
   */
  const focusBox = useCallback(() => {
    flushSync(() => setWide(true));
    void loadIndex().then(setIndex);
    input.current?.focus();
    input.current?.select();
  }, []);

  // `/` and ⌘K or Ctrl-K come to the box.
  useEffect(() => {
    const key = (event: globalThis.KeyboardEvent) => {
      const k = event.key.toLowerCase();
      const command = k === 'k' && (event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey;
      const slash = event.key === '/' && !event.metaKey && !event.ctrlKey && !event.altKey && !typing(event.target);
      if (!command && !slash) return;
      event.preventDefault();
      focusBox();
    };
    addEventListener('keydown', key);
    return () => removeEventListener('keydown', key);
  }, [focusBox]);

  // The active result kept in view as the arrows move.
  useEffect(() => {
    list.current?.querySelector<HTMLElement>(`[data-at="${active}"]`)?.scrollIntoView({ block: 'nearest' });
  }, [active]);

  const choose = (at: number) => {
    const hit = hits[at];
    if (!hit) return;
    open(hit.slug, { anchor: hit.anchor, find: query.trim() });
    setShown(false);
    setWide(false);
    input.current?.blur();
  };

  const close = () => {
    setShown(false);
    setWide(false);
  };

  const keys = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      setShown(true);
      if (!hits.length) return;
      const step = event.key === 'ArrowDown' ? 1 : -1;
      setActive((at) => (at + step + hits.length) % hits.length);
    } else if (event.key === 'Enter') {
      event.preventDefault();
      choose(active);
    } else if (event.key === 'Escape') {
      event.preventDefault();
      if (showing) setShown(false);
      else if (query) setQuery('');
      else {
        close();
        input.current?.blur();
      }
    } else if (event.key === 'Home' && showing && hits.length && event.ctrlKey) {
      setActive(0);
    }
  };

  const said = !showing ? '' : !index ? 'Searching…' : hits.length ? `${hits.length === 30 ? '30 or more' : hits.length} ${hits.length === 1 ? 'result' : 'results'}` : `Nothing in the docs matches “${query.trim()}”.`;

  return (
    <div className={styles.search} data-wide={wide ? '' : undefined}>
      <button
        type="button"
        className={styles.opener}
        aria-label="Search the docs"
        onClick={focusBox}
      >
        <Search size={16} aria-hidden="true" />
      </button>
      <div className={styles.field}>
        <Search className={styles.glass} size={16} aria-hidden="true" />
        <input
          ref={input}
          className={styles.input}
          type="search"
          role="combobox"
          aria-label="Search the docs"
          aria-expanded={showing}
          aria-controls={listId}
          aria-autocomplete="list"
          aria-activedescendant={showing && hits[active] ? `${id}-hit-${active}` : undefined}
          placeholder="Search the docs"
          autoComplete="off"
          spellCheck={false}
          enterKeyHint="search"
          value={query}
          onFocus={() => {
            begin();
            setShown(true);
          }}
          onBlur={(event) => {
            // A tap on a result moves the focus there first: let the tap open it.
            if (event.relatedTarget instanceof Node && list.current?.contains(event.relatedTarget)) return;
            setShown(false);
            if (!query) setWide(false);
          }}
          onChange={(event) => {
            setQuery(event.target.value);
            setActive(0);
            setShown(true);
          }}
          onKeyDown={keys}
        />
        <kbd className={styles.key} aria-hidden="true">
          /
        </kbd>
        <button
          type="button"
          className={styles.cancel}
          aria-label="Close search"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() => {
            setQuery('');
            close();
            input.current?.blur();
          }}
        >
          <X size={16} aria-hidden="true" />
        </button>
      </div>
      <div className={styles.panel} hidden={!showing}>
        <p className={styles.said} role="status" aria-live="polite">
          {said}
        </p>
        <ul ref={list} id={listId} className={styles.results} role="listbox" aria-label="Search results">
          {showing
            ? hits.map((hit, at) => (
                <li
                  key={`${hit.slug}#${hit.anchor}`}
                  id={`${id}-hit-${at}`}
                  data-at={at}
                  className={styles.result}
                  role="option"
                  aria-selected={at === active}
                  tabIndex={-1}
                  onMouseDown={(event) => event.preventDefault()}
                  onMouseMove={() => setActive(at)}
                  onClick={() => choose(at)}
                >
                  <span className={styles.chapter}>
                    <Marked parts={hit.titleParts} />
                  </span>
                  {hit.heading ? (
                    <span className={styles.heading}>
                      <Marked parts={hit.headingParts} />
                    </span>
                  ) : null}
                  {hit.snippet.length ? (
                    <span className={styles.snippet}>
                      <Marked parts={hit.snippet} />
                    </span>
                  ) : null}
                </li>
              ))
            : null}
        </ul>
      </div>
    </div>
  );
}

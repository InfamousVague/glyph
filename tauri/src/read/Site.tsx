import { Fragment, useEffect, useMemo, useState, type MouseEvent, type ReactNode } from 'react';
import type { EditorView } from '@codemirror/view';
import { ChevronLeft, ChevronRight, Menu } from '@glacier/icons';
import { failureText } from '../app/core/failure.ts';
import { Editor } from '../app/editor/Editor.tsx';
import { CanvasView } from '../app/canvas/CanvasView.tsx';
import { canvasOf, isCanvasBody } from '../app/canvas/jsonCanvas.ts';
import { BookView } from '../app/book/BookView.tsx';
import { chapterParts, chaptersOf } from '../app/book/book.ts';
import { usePreferences } from '../app/core/preferences.ts';
import type { NoteView } from '../app/editor/viewMode.ts';
import { lendImages } from '../app/core/images.ts';
import { sameTitle } from '../app/editor/wikiLinks.ts';
import { authorsOf } from '../app/core/authors.ts';
import { lookOf } from '../app/core/look.ts';
import { Byline } from '../app/authors/Byline.tsx';
import type { Shared } from '../app/share/share.ts';
import { drawnBody } from './drawn.ts';
import { INSTALL_URL } from './places.ts';
import { readSite, readSiteAddress, sitePath, siteSlugs } from './site.ts';
import { useSystemDark } from './systemDark.ts';
import styles from './Site.module.css';

/**
 * A note or a notebook published as a site (docs/SITES.md): the reader page at `/s/<id>`, read as a small website.
 *
 * The site's title over its pages; a notebook's pages listed down the side in the notebook's order (on a phone, behind
 * Pages in the bar); each page at an address of its own, which a link, a reload and the browser's Back all keep; the
 * app's own editor, canvas and index drawing each page read-only, so it reads as it does in Ghost.md, marks and
 * pictures and all; `[[links]]` between pages of the site going to those pages; Previous and Next at a page's foot;
 * light or dark as the reader's system is; and Made with Ghost.md at the bottom.
 *
 * What the reader page's shared link offers and this does not: no question of where to read, no Save a copy, no
 * download. A site is a thing to read, passed round as an address, and the person who published it chose that.
 */

type State = { kind: 'loading' } | { kind: 'failed'; title: string; message: string } | { kind: 'ready'; shared: Shared; place: SitePlace };

/**
 * Where a site's pages are: how an address names a page, and a page's address. A published site's are `/s/<id>/<slug>`
 * with its key after the # ([sitePlace]); the public docs' are `/docs/<slug>` (src/docs), with a way home in the bar.
 */
export interface SitePlace {
  /** The slug a path asks for, null for the first page. */
  slugAt: (pathname: string) => string | null;
  /** A page's address, by its slug ('' for the first page). */
  path: (slug: string) => string;
  /** What the browser's tab says, for the site's first page (null) or another by its title. */
  title: (page: string | null) => string;
  /** A link to the site's home, its icon before the title in the bar: the docs' to ghostmarkdown.com. */
  home?: { href: string; label: string; icon: string };
  /** How every page is drawn, whatever this browser's Ghost.md preference says: the docs' formatted, marks folded away. */
  display?: NoteView;
  /**
   * Something more in the bar, after the title: the docs' search (src/docs/DocsSearch.tsx), handed the way to open a
   * page, by its slug, at a heading with words marked.
   */
  bar?: (open: (slug: string, target: SiteTarget) => void) => ReactNode;
  /**
   * Headings as places, the docs' (src/docs/reveal.ts): `#<anchor>` after a page's address scrolls to that heading,
   * and words a search found are marked under it, by this, which is handed the page's editor and gives back what
   * takes the marks away. Never a published site's: the part after its # is its key.
   */
  reveal?: (view: EditorView, target: SiteTarget) => () => void;
}

/** A place on a page: a heading by its anchor ('' for the top), and the words a search found there, to mark. */
export interface SiteTarget {
  anchor: string;
  find: string;
}

/** The heading an address names after its #, and the words the search that went there found (its history entry's). */
function targetAt(): (SiteTarget & { n: number }) | null {
  const raw = location.hash.replace(/^#/, '');
  const find = (history.state as { find?: unknown } | null)?.find;
  if (!raw && typeof find !== 'string') return null;
  let anchor = raw;
  try {
    anchor = decodeURIComponent(raw);
  } catch {
    // A # the page did not write is read as it is.
  }
  return { anchor, find: typeof find === 'string' ? find : '', n: 0 };
}

/** A published site's place: `/s/<id>/<page>`, its key carried after the # as it came. */
function sitePlace(id: string, siteTitle: string): SitePlace {
  return {
    slugAt: (pathname) => readSiteAddress(pathname, '')?.slug ?? null,
    path: (slug) => sitePath(id, slug, location.hash),
    title: (page) => (page === null ? `${siteTitle} · Ghost.md` : `${page} · ${siteTitle}`),
  };
}

/** The page an address asks for: its place among the slugs, the first for none, -1 for one the site does not have. */
function pageAt(slugs: string[], place: SitePlace, pathname: string): number {
  const asked = place.slugAt(pathname);
  if (asked === null) return 0;
  return slugs.indexOf(asked);
}

export function Site() {
  const [state, setState] = useState<State>({ kind: 'loading' });
  const isDark = useSystemDark();

  useEffect(() => {
    const address = readSiteAddress(location.pathname, location.hash);
    if (!address?.key) {
      setState({ kind: 'failed', title: 'Nothing to read here', message: 'This address is missing the part after the # that opens it. Ask for the link again.' });
      return;
    }
    readSite(address.id, address.key).then(
      (shared) => {
        lendImages(shared.pictures ?? {});
        setState({ kind: 'ready', shared, place: sitePlace(address.id, shared.title) });
      },
      (failure: unknown) => setState({ kind: 'failed', title: 'Nothing to read here', message: failureText(failure) }),
    );
  }, []);

  if (state.kind === 'loading') return <main className={styles.alone}><p className={styles.quiet}>Opening…</p></main>;
  if (state.kind === 'failed') {
    return (
      <main className={styles.alone}>
        <h1 className={styles.aloneTitle}>{state.title}</h1>
        <p className={styles.quiet}>{state.message}</p>
        <Foot />
      </main>
    );
  }
  return <Pages shared={state.shared} dark={isDark} place={state.place} />;
}

function Foot() {
  return (
    <footer className={styles.foot}>
      Made with{' '}
      <a className={styles.made} href={INSTALL_URL}>
        Ghost.md
      </a>
    </footer>
  );
}

/** A site's pages, read: a published site's (above), or the public docs' (src/docs/main.tsx), told where by `place`. */
export function Pages({ shared, dark, place }: { shared: Shared; dark: boolean; place: SitePlace }) {
  const slugs = useMemo(() => siteSlugs(shared), [shared]);
  const [page, setPage] = useState(() => pageAt(slugs, place, location.pathname));
  const [listOpen, setListOpen] = useState(false);
  // Where on the page to go once it is drawn (place.reveal), and the editor drawing it, with the page it was made for.
  const [target, setTarget] = useState(() => (place.reveal ? targetAt() : null));
  const [view, setView] = useState<{ view: EditorView; page: number } | null>(null);
  const { noteView } = usePreferences();
  // A notebook opens on its index, drawn as the app draws one; its pages are listed when it has any written.
  const book = shared.kind === 'book';
  const isBook = book && shared.pages.length > 1;

  // The browser's Back and Forward go between the pages read, as between the pages of any site.
  useEffect(() => {
    const back = () => {
      setPage(pageAt(slugs, place, location.pathname));
      setTarget(place.reveal ? targetAt() : null);
    };
    addEventListener('popstate', back);
    return () => removeEventListener('popstate', back);
  }, [slugs, place]);

  const current = page >= 0 ? shared.pages[page] : undefined;
  useEffect(() => {
    document.title = place.title(!current || page === 0 ? null : current.title);
  }, [current, page, place]);

  const canvas = current && isCanvasBody(current.body) ? canvasOf(current.body) : null;
  const indexOf = (title: string) => shared.pages.findIndex((p) => sameTitle(p.title, title));
  const href = (at: number) => place.path(slugs[at] ?? '');
  const go = (at: number, to?: SiteTarget) => {
    if (at < 0 || at >= shared.pages.length) return;
    const there = to && place.reveal ? to : null;
    history.pushState(there?.find ? { find: there.find } : null, '', there?.anchor ? `${href(at)}#${encodeURIComponent(there.anchor)}` : href(at));
    setPage(at);
    setListOpen(false);
    setTarget(there ? { ...there, n: performance.now() } : null);
    if (!there) window.scrollTo({ top: 0 });
  };
  const openAt = (slug: string, to: SiteTarget) => go(slug ? slugs.indexOf(slug) : 0, to);

  // A heading asked for, gone to once the page's editor is drawn; and again for each search that asks, the same page's too.
  const reveal = place.reveal;
  const drawn = view && view.page === page ? view.view : null;
  useEffect(() => (reveal && drawn && target ? reveal(drawn, target) : undefined), [reveal, drawn, target]);
  /** A link's click, kept on this page: the address changes, nothing is fetched. A click that opens a tab is the browser's. */
  const follow = (at: number) => (event: MouseEvent<HTMLAnchorElement>) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    go(at);
  };
  const open = (title: string) => go(indexOf(title));
  const known = (title: string) => indexOf(title) >= 0;
  const bodyOf = (title: string) => shared.pages[indexOf(title)]?.body ?? null;
  const titles = () => shared.pages.map((p) => p.title);
  // The part of the index each page is in (book.ts `chapterParts`), for the list down the side.
  const parts = useMemo(() => {
    const index = shared.pages[0]?.body ?? '';
    const chapters = chaptersOf(index);
    const named = chapterParts(index, chapters);
    return chapters.map((chapter, i) => ({ title: chapter.title, part: named[i] ?? null }));
  }, [shared]);
  const partOf = (title: string) => parts.find((c) => sameTitle(c.title, title))?.part ?? null;

  const list = isBook ? (
    <ol className={styles.list}>
      {shared.pages.map((p, at) => {
        // A part's heading over the first of its pages there is: a part none of whose pages is written is not listed.
        const part = at > 0 ? (partOf(p.title) ?? null) : null;
        const opens = part !== null && (at === 1 || partOf(shared.pages[at - 1]!.title) !== part);
        return (
          <Fragment key={`${at}:${p.title}`}>
            {opens ? (
              <li className={styles.part} role="presentation">
                {part}
              </li>
            ) : null}
            <li>
              <a className={styles.item} href={href(at)} aria-current={at === page ? 'page' : undefined} onClick={follow(at)}>
                {at === 0 ? 'Contents' : p.title}
              </a>
            </li>
          </Fragment>
        );
      })}
    </ol>
  ) : null;

  return (
    <div className={styles.site} data-book={isBook ? '' : undefined}>
      <header className={styles.bar}>
        {place.home ? (
          <a className={styles.home} href={place.home.href} aria-label={place.home.label} title={place.home.label}>
            <img src={place.home.icon} width={24} height={24} alt="" />
          </a>
        ) : null}
        <a className={styles.siteTitle} href={href(0)} onClick={follow(0)}>
          {shared.title}
        </a>
        {place.bar?.(openAt)}
        {isBook ? (
          <button type="button" className={styles.pagesButton} aria-expanded={listOpen} aria-controls="site-pages" onClick={() => setListOpen(!listOpen)}>
            <Menu size={16} aria-hidden="true" />
            Pages
          </button>
        ) : null}
      </header>
      {isBook && listOpen ? (
        <nav id="site-pages" className={styles.dropped} aria-label="Pages of this site">
          {list}
        </nav>
      ) : null}
      <div className={styles.body}>
        {isBook ? (
          <nav className={styles.side} aria-label="This site’s pages">
            {list}
          </nav>
        ) : null}
        <main className={styles.main}>
          {!current ? (
            <article className={styles.missing}>
              <h1 className={styles.aloneTitle}>That page isn’t in this site</h1>
              <p className={styles.quiet}>
                It may have been renamed or taken out when the site was last published.{' '}
                <a className={styles.made} href={href(0)} onClick={follow(0)}>
                  Go to the first page
                </a>
                .
              </p>
            </article>
          ) : book && page === 0 ? (
            <article className={styles.note}>
              <h1 className={styles.title}>{shared.title}</h1>
              <BookView body={current.body} title={shared.title} known={(t) => indexOf(t) > 0} open={open} titles={titles} bodyOf={bodyOf} onChange={readOnly} readOnly dark={dark} videos="shared" parts />
            </article>
          ) : canvas ? (
            <article className={styles.note}>
              <h1 className={styles.title}>{current!.title}</h1>
              <Byline authors={authorsOf(current!.body)} />
              <div className={styles.canvas}>
                <CanvasView canvas={canvas} dark={dark} wiki={{ known, open, body: bodyOf, titles }} videos="shared" />
              </div>
            </article>
          ) : (
            <article className={styles.note} data-look={lookOf(current.body) ?? undefined}>
              <Byline authors={authorsOf(current.body)} />
              <Editor
                key={`${page}:${current.title}`}
                value={drawnBody(current.body)}
                onChange={readOnly}
                dark={dark}
                assist={false}
                readOnly
                display={place.display ?? noteView}
                wiki={{ known, open }}
                places="ask"
                videos="shared"
                look={lookOf(current.body)}
                grow
                onView={reveal ? (made) => setView(made ? { view: made, page } : null) : undefined}
              />
            </article>
          )}
          {isBook && current && page > 0 ? (
            <nav className={styles.turn} aria-label="Next and previous pages">
              <a className={styles.turnEnd} href={href(page - 1)} onClick={follow(page - 1)}>
                <ChevronLeft size={16} aria-hidden="true" />
                <span className={styles.turnWords}>
                  <span className={styles.turnSide}>Previous</span>
                  <span className={styles.turnTitle}>{page - 1 === 0 ? 'Contents' : shared.pages[page - 1]!.title}</span>
                </span>
              </a>
              {page + 1 < shared.pages.length ? (
                <a className={styles.turnEnd} data-next="" href={href(page + 1)} onClick={follow(page + 1)}>
                  <span className={styles.turnWords}>
                    <span className={styles.turnSide}>Next</span>
                    <span className={styles.turnTitle}>{shared.pages[page + 1]!.title}</span>
                  </span>
                  <ChevronRight size={16} aria-hidden="true" />
                </a>
              ) : (
                <span />
              )}
            </nav>
          ) : null}
          <Foot />
        </main>
      </div>
    </div>
  );
}

function readOnly(): void {
  // Nothing typed here comes back: the site is read-only.
}

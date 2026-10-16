import { useEffect, useMemo, useState, type MouseEvent } from 'react';
import { ChevronLeft, ChevronRight, Menu } from '@glacier/icons';
import { failureText } from '../app/core/failure.ts';
import { Editor } from '../app/editor/Editor.tsx';
import { CanvasView } from '../app/canvas/CanvasView.tsx';
import { canvasOf, isCanvasBody } from '../app/canvas/jsonCanvas.ts';
import { BookView } from '../app/book/BookView.tsx';
import { usePreferences } from '../app/core/preferences.ts';
import { lendImages } from '../app/core/images.ts';
import { sameTitle } from '../app/editor/wikiLinks.ts';
import { authorsOf } from '../app/core/authors.ts';
import { lookOf } from '../app/core/look.ts';
import { Byline } from '../app/authors/Byline.tsx';
import type { Shared } from '../app/share/share.ts';
import { drawnBody } from './drawn.ts';
import { INSTALL_URL } from './places.ts';
import { readSite, readSiteAddress, sitePath, siteSlugs } from './site.ts';
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

const dark = () => typeof matchMedia !== 'undefined' && matchMedia('(prefers-color-scheme: dark)').matches;

type State = { kind: 'loading' } | { kind: 'failed'; title: string; message: string } | { kind: 'ready'; shared: Shared };

/** The page an address asks for: its place among the slugs, the first for none, -1 for one the site does not have. */
function pageAt(slugs: string[], pathname: string): number {
  const asked = readSiteAddress(pathname, '')?.slug ?? null;
  if (asked === null) return 0;
  return slugs.indexOf(asked);
}

export function Site() {
  const [state, setState] = useState<State>({ kind: 'loading' });
  const [isDark, setDark] = useState(dark);

  useEffect(() => {
    document.documentElement.dataset.theme = isDark ? 'dark' : 'light';
    const query = matchMedia('(prefers-color-scheme: dark)');
    const change = () => setDark(query.matches);
    query.addEventListener('change', change);
    return () => query.removeEventListener('change', change);
  }, [isDark]);

  useEffect(() => {
    const address = readSiteAddress(location.pathname, location.hash);
    if (!address?.key) {
      setState({ kind: 'failed', title: 'Nothing to read here', message: 'This address is missing the part after the # that opens it. Ask for the link again.' });
      return;
    }
    readSite(address.id, address.key).then(
      (shared) => {
        lendImages(shared.pictures ?? {});
        setState({ kind: 'ready', shared });
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
  return <Pages shared={state.shared} dark={isDark} />;
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

function Pages({ shared, dark }: { shared: Shared; dark: boolean }) {
  const slugs = useMemo(() => siteSlugs(shared), [shared]);
  const [page, setPage] = useState(() => pageAt(slugs, location.pathname));
  const [listOpen, setListOpen] = useState(false);
  const { noteView } = usePreferences();
  const id = readSiteAddress(location.pathname, location.hash)!.id;
  // A notebook opens on its index, drawn as the app draws one; its pages are listed when it has any written.
  const book = shared.kind === 'book';
  const isBook = book && shared.pages.length > 1;

  // The browser's Back and Forward go between the pages read, as between the pages of any site.
  useEffect(() => {
    const back = () => setPage(pageAt(slugs, location.pathname));
    addEventListener('popstate', back);
    return () => removeEventListener('popstate', back);
  }, [slugs]);

  const current = page >= 0 ? shared.pages[page] : undefined;
  useEffect(() => {
    document.title = !current || page === 0 ? `${shared.title} · Ghost.md` : `${current.title} · ${shared.title}`;
  }, [current, page, shared.title]);

  const canvas = current && isCanvasBody(current.body) ? canvasOf(current.body) : null;
  const indexOf = (title: string) => shared.pages.findIndex((p) => sameTitle(p.title, title));
  const href = (at: number) => sitePath(id, slugs[at] ?? '', location.hash);
  const go = (at: number) => {
    if (at < 0 || at >= shared.pages.length) return;
    history.pushState(null, '', href(at));
    setPage(at);
    setListOpen(false);
    window.scrollTo({ top: 0 });
  };
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

  const list = isBook ? (
    <ol className={styles.list}>
      {shared.pages.map((p, at) => (
        <li key={`${at}:${p.title}`}>
          <a className={styles.item} href={href(at)} aria-current={at === page ? 'page' : undefined} onClick={follow(at)}>
            {at === 0 ? 'Contents' : p.title}
          </a>
        </li>
      ))}
    </ol>
  ) : null;

  return (
    <div className={styles.site} data-book={isBook ? '' : undefined}>
      <header className={styles.bar}>
        <a className={styles.siteTitle} href={href(0)} onClick={follow(0)}>
          {shared.title}
        </a>
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
              <BookView body={current.body} title={shared.title} known={(t) => indexOf(t) > 0} open={open} titles={titles} bodyOf={bodyOf} onChange={readOnly} readOnly dark={dark} videos="shared" />
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
                display={noteView}
                wiki={{ known, open }}
                places="ask"
                videos="shared"
                look={lookOf(current.body)}
                grow
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

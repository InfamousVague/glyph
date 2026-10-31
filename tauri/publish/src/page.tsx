import type { ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { linkTargets } from '../../src/app/core/properties.ts';
import { Rendered, type SiteDraw } from '../../src/read/Rendered.tsx';
import { plainLine } from '../../src/docs/book.ts';
import { CanvasStill } from './canvas.tsx';
import type { PublishConfig } from './config.ts';
import { fenceFor, type FenceContext } from './fences.tsx';
import { headingId, relativeHref, type Resolver } from './links.ts';
import type { Folder, Library, Page } from './library.ts';
import { forDrawing } from './words.ts';
import meetingStyles from '../../src/read/MeetingRead.module.css';
import styles from './site.module.css';

/**
 * A page of the site, drawn whole with React's server renderer: the chrome (a bar with the site's name and the search,
 * the folder tree down the side, breadcrumbs over the words, Made with Ghost.md at the foot) round the note drawn by
 * the reader's own renderer (read/Rendered.tsx, handed the site's resolutions: links.ts, fences.tsx). A ticket's or a
 * notebook's front matter is a small properties block over its words; a canvas is drawn still (canvas.tsx); a meeting
 * is Summary | Transcript as the share page draws it (MeetingRead.tsx), a toggle made of two radio buttons so it needs
 * no script, with the tape as an `<audio>` where `recordings/<id>.wav` is in the repository.
 *
 * Nothing on a page runs but the search (client/search.js, the site's own file), and nothing is fetched from anywhere
 * but the site: its styles, its fonts and its pictures are all in the output.
 */

export interface SiteAssets {
  /** Stylesheets, from the site's root. */
  css: string[];
  /** The search's script, from the site's root. */
  search: string;
}

export interface SiteContext {
  library: Library;
  config: PublishConfig;
  resolver: Resolver;
  assets: SiteAssets;
  title: string;
  fences: Omit<FenceContext, 'page'>;
}

/** The keys a page never shows: the library's, the ones a share strips for privacy (lib/share/carried.dart), the site's own. */
const HIDDEN_KEYS = new Set(['title', 'location', 'place', 'private', 'id', 'created', 'updated', 'pinned', 'archived', 'source', 'meeting']);

function Head({ ctx, page, title, description, root }: { ctx: SiteContext; page: Page | null; title: string; description: string | null; root: string }) {
  const canonical = ctx.config.baseUrl ? `${ctx.config.baseUrl}/${page ? page.href : ''}` : null;
  return (
    <head>
      <meta charSet="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>{title}</title>
      {description ? <meta name="description" content={description} /> : null}
      {ctx.config.robots === 'noindex' ? <meta name="robots" content="noindex, nofollow" /> : null}
      {canonical ? <link rel="canonical" href={canonical} /> : null}
      <link rel="alternate" type="application/atom+xml" title={ctx.title} href={`${root}feed.xml`} />
      <meta name="generator" content="ghost-publish" />
      {ctx.assets.css.map((href) => (
        <link key={href} rel="stylesheet" href={`${root}${href}`} />
      ))}
    </head>
  );
}

function FolderTree({ folder, ctx, current, from }: { folder: Folder; ctx: SiteContext; current: Page | null; from: string }) {
  const holds = (f: Folder): boolean => !!current && (f.pages.includes(current) || f.folders.some(holds));
  return (
    <>
      {folder.pages.length ? (
        <ul className={styles.list}>
          {folder.pages.map((page) => (
            <li key={page.file}>
              <a className={styles.item} href={relativeHref(from, page.href)} aria-current={page === current ? 'page' : undefined} data-pinned={page.pinned ? '' : undefined} data-kind={page.kind}>
                {page.title}
              </a>
            </li>
          ))}
        </ul>
      ) : null}
      {folder.folders.map((child) => (
        <details key={child.path.join('/')} className={styles.folder} open={folder.path.length === 0 || holds(child) ? true : undefined}>
          <summary>{child.name}</summary>
          <FolderTree folder={child} ctx={ctx} current={current} from={from} />
        </details>
      ))}
    </>
  );
}

function Crumbs({ page, from }: { page: Page; from: string }) {
  const crumbs: ReactNode[] = [
    <a key="home" href={relativeHref(from, 'index.html')}>
      Home
    </a>,
  ];
  page.folder.forEach((name, i) => {
    crumbs.push(<span key={`s${i}`} aria-hidden="true">{' › '}</span>);
    crumbs.push(<span key={i}>{name}</span>);
  });
  return (
    <nav className={styles.crumbs} aria-label="Where this page is">
      {crumbs}
    </nav>
  );
}

/** A property's value: its `[[links]]` as links, anything else as its words. */
function propertyValue(value: string, page: Page, ctx: SiteContext): ReactNode {
  if (!value.includes('[[')) return value;
  const links = linkTargets(value);
  return links.map((target, i) => {
    const href = ctx.resolver.hrefOf(page, target, null);
    return (
      <span key={i}>
        {i > 0 ? ', ' : ''}
        {href ? <a href={href}>{target}</a> : target}
      </span>
    );
  });
}

function Properties({ page, ctx }: { page: Page; ctx: SiteContext }) {
  const shown = Object.entries(page.front.page).filter(([key]) => !HIDDEN_KEYS.has(key));
  if (!shown.length) return null;
  return (
    <dl className={styles.properties} aria-label="Properties">
      {shown.map(([key, value]) => (
        <div key={key}>
          <dt>{key}</dt>
          <dd>{propertyValue(value, page, ctx)}</dd>
        </div>
      ))}
    </dl>
  );
}

function siteDraw(page: Page, ctx: SiteContext): SiteDraw {
  const ids = new Map<string, number>();
  return {
    hrefOf: (title, anchor) => ctx.resolver.hrefOf(page, title, anchor),
    fileHref: (target) => ctx.resolver.fileHref(page, target),
    fence: fenceFor({ ...ctx.fences, page }),
    headingId: (text) => {
      const base = headingId(text);
      const n = (ids.get(base) ?? 0) + 1;
      ids.set(base, n);
      return n === 1 ? base : `${base}-${n}`;
    },
  };
}

function Words({ page, body, ctx }: { page: Page; body: string; ctx: SiteContext }) {
  return <Rendered body={forDrawing(body)} site={siteDraw(page, ctx)} bodyOf={(title) => ctx.resolver.pageOf(page, title)?.text ?? null} />;
}

function Meeting({ page, ctx }: { page: Page; ctx: SiteContext }) {
  const transcript = page.transcript!;
  const tape = page.id ? ctx.resolver.fileHref(page, `recordings/${page.id}.wav`) : null;
  const summary = transcript.summary(page.title);
  const meta = ['Meeting', ...(transcript.speakers.length ? [transcript.speakers.join(', ')] : [])].join(' · ');
  return (
    <article className={`${meetingStyles.meeting} ${styles.meeting}`} data-meeting="">
      <h1 className={meetingStyles.title}>{page.title}</h1>
      <p className={meetingStyles.when}>{meta}</p>
      <Properties page={page} ctx={ctx} />
      <div className={styles.segmented} role="tablist" aria-label="Summary or transcript">
        <input type="radio" name="meeting-view" id="view-summary" defaultChecked />
        <label htmlFor="view-summary" role="tab">
          Summary
        </label>
        <input type="radio" name="meeting-view" id="view-transcript" />
        <label htmlFor="view-transcript" role="tab">
          Transcript
        </label>
      </div>
      {tape ? <audio className={styles.tape} controls preload="none" src={tape} aria-label="The recording" /> : null}
      <section className={styles.summaryPane} data-pane="summary">
        {summary.trim() ? <Words page={page} body={summary} ctx={ctx} /> : <p className={meetingStyles.empty}>No summary yet.</p>}
      </section>
      <section className={styles.transcriptPane} data-pane="transcript">
        {transcript.turns.length ? (
          <ol className={meetingStyles.turns} aria-label="Transcript">
            {transcript.turns.map((turn, i) => (
              <li key={i} className={meetingStyles.turn}>
                <p className={meetingStyles.who}>
                  {turn.speaker ? <strong className={meetingStyles.name}>{turn.speaker}</strong> : null}
                  {turn.at ? <span className={meetingStyles.at}>{turn.at}</span> : null}
                </p>
                <p className={meetingStyles.words}>{turn.text}</p>
              </li>
            ))}
          </ol>
        ) : (
          <p className={meetingStyles.empty}>This meeting has no transcript yet.</p>
        )}
      </section>
    </article>
  );
}

function Shell({ ctx, current, from, children }: { ctx: SiteContext; current: Page | null; from: string; children: ReactNode }) {
  const root = relativeHref(from, 'index.html').replace(/index\.html$/, '');
  return (
    <body className={styles.site} data-root={root}>
      <input type="checkbox" id="menu" className={styles.menuBox} aria-hidden="true" />
      <header className={styles.bar}>
        <label htmlFor="menu" className={styles.menuButton} aria-label="Pages">
          <span aria-hidden="true">☰</span> Pages
        </label>
        <a className={styles.siteTitle} href={`${root}index.html`}>
          {ctx.title}
        </a>
        <form className={styles.search} role="search" action={`${root}index.html`} method="get">
          <input type="search" name="q" placeholder="Search" aria-label="Search the site" autoComplete="off" data-index={`${root}search.json`} />
        </form>
      </header>
      <div className={styles.body}>
        <nav className={styles.side} aria-label="Pages">
          <FolderTree folder={ctx.library.tree} ctx={ctx} current={current} from={from} />
        </nav>
        <main className={styles.main}>
          <div className={styles.results} id="search-results" hidden />
          {children}
          <footer className={styles.foot}>
            Made with{' '}
            <a className={styles.made} href="https://ghostmarkdown.com">
              Ghost.md
            </a>
          </footer>
        </main>
      </div>
      <script src={`${root}${ctx.assets.search}`} defer />
    </body>
  );
}

/** A page in a sentence, for its description and the home page's cards (src/docs/book.ts `docsSummary`'s rule). */
export function summaryOf(page: Page): string {
  const words: string[] = [];
  for (const line of page.body.split('\n')) {
    const plain = line.trim();
    if (!plain) {
      if (words.length) break;
      continue;
    }
    if (/^(#|[-*+] |\d+\. |\||```|~~~|!\[|<|\{)/.test(plain)) {
      if (words.length) break;
      continue;
    }
    words.push(plainLine(plain));
  }
  const text = words.join(' ').replace(/\s+/g, ' ').trim();
  return text.length > 160 ? `${text.slice(0, 157).replace(/\s+\S*$/, '')}…` : text;
}

function document(head: ReactNode, body: ReactNode): string {
  return `<!doctype html>\n${renderToStaticMarkup(
    <html lang="en">
      {head}
      {body}
    </html>,
  )}\n`;
}

/** A note's page. */
export function renderPage(page: Page, ctx: SiteContext): string {
  const description = summaryOf(page) || null;
  const title = `${page.title} · ${ctx.title}`;
  const root = relativeHref(page.href, 'index.html').replace(/index\.html$/, '');
  let inside: ReactNode;
  if (page.kind === 'canvas' && page.canvas) {
    inside = (
      <article data-kind="canvas">
        <Crumbs page={page} from={page.href} />
        <h1 className={styles.title}>{page.title}</h1>
        <Properties page={page} ctx={ctx} />
        <CanvasStill canvas={page.canvas} page={page} resolver={ctx.resolver} />
      </article>
    );
  } else if (page.kind === 'meeting' && page.transcript) {
    inside = (
      <>
        <Crumbs page={page} from={page.href} />
        <Meeting page={page} ctx={ctx} />
      </>
    );
  } else {
    inside = (
      <article data-kind={page.kind}>
        <Crumbs page={page} from={page.href} />
        <Properties page={page} ctx={ctx} />
        <Words page={page} body={page.body} ctx={ctx} />
      </article>
    );
  }
  return document(
    <Head ctx={ctx} page={page} title={title} description={description} root={root} />,
    <Shell ctx={ctx} current={page} from={page.href}>
      {inside}
    </Shell>,
  );
}

const when = new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });

function Card({ page, from }: { page: Page; from: string }) {
  const summary = summaryOf(page);
  return (
    <li className={styles.card} data-kind={page.kind}>
      <a href={relativeHref(from, page.href)}>{page.title}</a>
      <span className={styles.cardMeta}>
        {page.folder.length ? page.folder.join(' › ') : 'Library'} · {when.format(new Date(page.updatedAt))}
      </span>
      {summary ? <p>{summary}</p> : null}
    </li>
  );
}

/** The home page: the pinned notes, then the most recently changed. */
export function renderHome(ctx: SiteContext): string {
  const pinned = ctx.library.pages.filter((page) => page.pinned).sort((a, b) => a.title.localeCompare(b.title));
  const recent = [...ctx.library.pages].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, ctx.config.recent);
  return document(
    <Head ctx={ctx} page={null} title={ctx.title} description={ctx.config.description} root="" />,
    <Shell ctx={ctx} current={null} from="index.html">
      <article data-kind="home">
        <h1 className={styles.title}>{ctx.title}</h1>
        {ctx.config.description ? <p className={styles.quiet}>{ctx.config.description}</p> : null}
        {pinned.length ? (
          <section>
            <h2 className={styles.homeHeading}>Pinned</h2>
            <ul className={styles.cards}>
              {pinned.map((page) => (
                <Card key={page.file} page={page} from="index.html" />
              ))}
            </ul>
          </section>
        ) : null}
        <section>
          <h2 className={styles.homeHeading}>Recent</h2>
          <ul className={styles.cards}>
            {recent.map((page) => (
              <Card key={page.file} page={page} from="index.html" />
            ))}
          </ul>
        </section>
      </article>
    </Shell>,
  );
}

/** The site's path on its host: `/` at a domain's root, `/<repo>/` on GitHub Pages' project sites. */
function sitePath(ctx: SiteContext): string {
  if (!ctx.config.baseUrl) return '/';
  try {
    return new URL(ctx.config.baseUrl).pathname.replace(/\/?$/, '/');
  } catch {
    return '/';
  }
}

/** The page a missing address lands on. Its links are from the site's path, since it is served for any address under it. */
export function renderNotFound(ctx: SiteContext): string {
  const base = sitePath(ctx);
  const absolute: SiteContext = { ...ctx, assets: { css: ctx.assets.css.map((href) => `${base}${href}`), search: ctx.assets.search } };
  const html = document(
    <Head ctx={{ ...absolute, config: { ...ctx.config, baseUrl: null } }} page={null} title={`Not found · ${ctx.title}`} description={null} root="" />,
    <body className={styles.site}>
      <main className={`${styles.main} ${styles.alone}`}>
        <h1 className={styles.title}>Nothing to read here</h1>
        <p className={styles.quiet}>There is no page at this address. It may have been renamed or moved.</p>
        <p>
          <a href={`${base}index.html`}>Back to {ctx.title}</a>
        </p>
      </main>
    </body>,
  );
  return html;
}

import { isProbablyReaderable, Readability } from '@mozilla/readability';
import type { ClipMode } from './kinds.ts';
import { markTasks, toMarkdown, type PictureRef } from './markdown.ts';

/**
 * What a page holds, read in the page itself (src/content.ts runs this in the tab, in the extension's own world, when
 * the person asks for a clip): the words of the mode they chose as Markdown, the pictures those words show, and what
 * the page says about itself. Nothing here leaves the tab but what is answered.
 *
 * The page is never changed: Readability and the conversion work on copies, and a full page is copied element by
 * element, leaving out what the person cannot see (`checkVisibility`), so a menu that is closed is not clipped.
 */

export { MODES, type ClipMode } from './kinds.ts';

/** What a page answers for a mode. */
export interface Extract {
  mode: ClipMode;
  url: string;
  title: string;
  markdown: string;
  pictures: PictureRef[];
  /** The page's own description and preview picture, for a bookmark. */
  description?: string;
  image?: string;
  siteName?: string;
  /** Said when the page answered something other than what was asked: an article that was not there, so the whole page. */
  notice?: 'no-article';
}

export interface Peek {
  url: string;
  title: string;
  /** Whether the person has selected something: the popup starts on Selection then. */
  selected: boolean;
  /** Whether Readability thinks the page has an article. */
  readable: boolean;
}

/** Something the person must do before a mode can clip, said in the popup. */
export class ClipRefused extends Error {
  constructor(readonly reason: 'no-selection' | 'empty' | 'not-a-page') {
    super(reason === 'no-selection' ? 'Select something on the page first.' : reason === 'empty' ? 'There is nothing on this page to clip.' : 'This page can’t be clipped.');
  }
}

function meta(doc: Document, ...names: string[]): string {
  for (const name of names) {
    const el = doc.querySelector(`meta[property="${name}"], meta[name="${name}"]`);
    const value = el?.getAttribute('content')?.trim();
    if (value) return value;
  }
  return '';
}

function absolute(href: string, base: string): string {
  try {
    const url = new URL(href, base);
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.href : '';
  } catch {
    return '';
  }
}

/**
 * The page's own name for itself: its first heading where the document's title holds it ("Sorting in place" of
 * "Sorting in place - Reference", without the site's name), else the document's title, else the heading, else where
 * it is.
 */
export function pageTitle(doc: Document, url: string): string {
  const heading = doc.querySelector('h1')?.textContent?.replace(/\s+/g, ' ').trim() ?? '';
  const titled = doc.title?.replace(/\s+/g, ' ').trim() ?? '';
  const said = (heading && titled.toLowerCase().includes(heading.toLowerCase()) ? heading : '') || titled || heading || meta(doc, 'og:title');
  if (said) return said.replace(/\s+/g, ' ');
  try {
    return new URL(url).hostname;
  } catch {
    return 'Clipped page';
  }
}

export function peek(win: Window): Peek {
  const doc = win.document;
  const selection = win.getSelection();
  const selected = Boolean(selection && !selection.isCollapsed && selection.toString().trim());
  return { url: win.location.href, title: pageTitle(doc, win.location.href), selected, readable: readerable(doc) };
}

/** Characters of text past which Readability's find is an article even where its quick test said no. */
const LONG_READ = 1500;

function readerable(doc: Document): boolean {
  try {
    return isProbablyReaderable(doc);
  } catch {
    return false;
  }
}

/** The article in the page by Readability, or null where it finds none. */
function article(doc: Document, url: string): Extract | null {
  const copy = doc.cloneNode(true) as Document;
  // Readability takes every input out of an article: a task list's boxes are said in words first.
  markTasks(copy);
  const parsed = new Readability<Element>(copy, { keepClasses: true, serializer: (el) => el as Element }).parse();
  // Readability finds something in nearly any page: an article is what Firefox's reader would offer, or a long read.
  if (!parsed?.content || (!readerable(doc) && (parsed.length ?? 0) < LONG_READ)) return null;
  const title = parsed.title?.trim() || pageTitle(doc, url);
  const { markdown, pictures } = toMarkdown(parsed.content, { base: doc.baseURI || url, title, doc });
  if (!markdown.trim()) return null;
  return {
    mode: 'article',
    url,
    title,
    markdown,
    pictures,
    ...(parsed.excerpt ? { description: parsed.excerpt.trim() } : {}),
    ...(parsed.siteName ? { siteName: parsed.siteName.trim() } : {}),
  };
}

/** A selection whose common ancestor is one of these spans several of a list's items or a table's cells. */
const ACROSS = new Set(['UL', 'OL', 'TABLE', 'THEAD', 'TBODY', 'TFOOT', 'TR']);

/** What the person selected, as a copy: every range, and a code block's own fence for words chosen inside one. */
function selection(win: Window): DocumentFragment | null {
  const chosen = win.getSelection();
  if (!chosen || chosen.isCollapsed || !chosen.rangeCount) return null;
  const doc = win.document;
  const out = doc.createDocumentFragment();
  for (let i = 0; i < chosen.rangeCount; i += 1) {
    const range = chosen.getRangeAt(i);
    const within = range.commonAncestorContainer;
    const element = within.nodeType === 1 ? (within as Element) : within.parentElement;
    const pre = element?.closest('pre');
    const parts = range.cloneContents();
    if (pre) {
      // The block and its code element, where the language is said, round the words chosen.
      const wrap = pre.cloneNode(false) as Element;
      const code = element?.closest('code');
      if (code && pre.contains(code)) {
        const inner = code.cloneNode(false) as Element;
        inner.appendChild(parts);
        wrap.appendChild(inner);
      } else wrap.appendChild(parts);
      out.appendChild(wrap);
      continue;
    }
    // Words chosen across a list's items or a table's cells keep the list or the table they were in.
    const holder = element?.closest('ul, ol, table');
    if (holder && element && ACROSS.has(element.nodeName)) {
      const wrap = holder.cloneNode(false) as Element;
      if (element.nodeName === 'TR') {
        const row = doc.createElement('tr');
        row.appendChild(parts);
        wrap.appendChild(row);
      } else wrap.appendChild(parts);
      out.appendChild(wrap);
      continue;
    }
    out.appendChild(parts);
  }
  return out;
}

/** The whole body, copied without what the person cannot see. */
function visibleCopy(doc: Document): Element {
  const LIMIT = 60_000;
  let count = 0;
  const copy = (node: Node): Node | null => {
    count += 1;
    if (count > LIMIT) return null;
    if (node.nodeType === 3) return node.cloneNode(false);
    if (node.nodeType !== 1) return null;
    const el = node as Element;
    const seen = typeof (el as HTMLElement).checkVisibility === 'function' ? (el as HTMLElement).checkVisibility({ checkVisibilityCSS: true } as CheckVisibilityOptions) : true;
    // An element with no box of its own (display: contents) answers false and still shows its children.
    const contents = !seen && doc.defaultView?.getComputedStyle(el).display === 'contents';
    if (!seen && !contents) return null;
    const shallow = el.cloneNode(false) as Element;
    for (const child of Array.from(el.childNodes)) {
      const kept = copy(child);
      if (kept) shallow.appendChild(kept);
    }
    return shallow;
  };
  return (copy(doc.body) as Element | null) ?? (doc.body.cloneNode(true) as Element);
}

function bookmark(doc: Document, url: string): Extract {
  const title = meta(doc, 'og:title', 'twitter:title') || pageTitle(doc, url);
  const description = meta(doc, 'og:description', 'twitter:description', 'description');
  const image = absolute(meta(doc, 'og:image', 'og:image:url', 'twitter:image', 'twitter:image:src') || doc.querySelector('link[rel="image_src"]')?.getAttribute('href') || '', doc.baseURI || url);
  const canonical = absolute(doc.querySelector('link[rel="canonical"]')?.getAttribute('href') ?? '', url);
  const siteName = meta(doc, 'og:site_name', 'application-name');
  return {
    mode: 'bookmark',
    url: canonical && new URL(canonical).hostname === new URL(url).hostname ? canonical : url,
    title,
    markdown: '',
    pictures: image ? [{ url: image, alt: title }] : [],
    ...(description ? { description } : {}),
    ...(image ? { image } : {}),
    ...(siteName ? { siteName } : {}),
  };
}

/** The page read for a mode. A screenshot is the browser's to take, not the page's: the page only names itself. */
export function extract(win: Window, mode: ClipMode): Extract {
  const doc = win.document;
  const url = win.location.href;
  if (!doc.body) throw new ClipRefused('not-a-page');
  const base = doc.baseURI || url;
  const title = pageTitle(doc, url);
  if (mode === 'screenshot') return { mode, url, title, markdown: '', pictures: [] };
  if (mode === 'bookmark') return bookmark(doc, url);
  if (mode === 'selection') {
    const chosen = selection(win);
    if (!chosen || !win.getSelection()?.toString().trim()) throw new ClipRefused('no-selection');
    const { markdown, pictures } = toMarkdown(chosen, { base, doc });
    if (!markdown.trim() && !pictures.length) throw new ClipRefused('no-selection');
    return { mode, url, title, markdown, pictures };
  }
  if (mode === 'article') {
    const found = article(doc, url);
    if (found) return found;
  }
  const { markdown, pictures } = toMarkdown(visibleCopy(doc), { base, title, doc });
  if (!markdown.trim() && !pictures.length) throw new ClipRefused('empty');
  return { mode: 'page', url, title, markdown, pictures, ...(mode === 'article' ? { notice: 'no-article' as const } : {}) };
}

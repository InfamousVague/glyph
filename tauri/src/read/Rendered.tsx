import { createElement, useEffect, useMemo, useState, type ReactNode } from 'react';
import { GFM, parser } from '@lezer/markdown';
import type { SyntaxNode } from '@lezer/common';
import { frontMatterOffset } from '../app/core/frontMatter.ts';
import { noteTitle } from '../app/core/noteTitle.ts';
import { titleKey } from '../app/core/titleKey.ts';
import { IMAGE_READY, imageUrl } from '../app/core/images.ts';
import { wikiLinksIn, type WikiLink } from '../app/editor/wikiLinks.ts';
import { MOST_EMBED_DEPTH, embedOf, sectionOf, type Embed } from './embeds.ts';
import styles from './Rendered.module.css';

/**
 * A shared page drawn as a page (readMode.ts, Read; Matt, 2026-10-29: "make code view a segmented toggle that's off by
 * default on the web preview page"): headings, lists, to-dos, quotes, tables, links, pictures and code, in the page's
 * own type, where Markdown shows its source in the app's editor.
 *
 * Parsed by the parser the app's editor already speaks (@lezer/markdown with GFM, the setext rule taken out as
 * editor/language.ts takes it out), so the two views read a note the same way, and drawn as React elements from the
 * tree: no HTML string is ever made, so nothing in a note runs. A note's own HTML is shown as the text it is, an HTML
 * comment not at all. A link opens in a new tab, and only `http:`, `https:` and `mailto:` are links; a picture is drawn
 * from the share (`image/<name>`, lent by the page: core/images.ts), and one from elsewhere is a link to it rather than
 * a request the reader never asked for. A `[[wiki link]]` to a page the share has opens it; any other is its words.
 * The front matter is not drawn: what it says that a reader wants (a byline, a place) the page draws itself.
 *
 * An embed on a line of its own, `![[Note#Heading]]` (embeds.ts), is drawn as the app draws it, a quoted card with the
 * page's title and the section in it, when that page is in the same share; any other is a "from [[Note]]" placeholder.
 * Two levels at most, and a page that would draw itself, or a page it is drawn inside of, is the placeholder too.
 */

const markdown = parser.configure([GFM, { remove: ['SetextHeading'] }]);

/** Where a link may go. */
function safeHref(url: string): string | null {
  const trimmed = url.trim();
  return /^(https?:|mailto:)/i.test(trimmed) ? trimmed : null;
}

const ENTITIES: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', copy: '©', mdash: '—', ndash: '–', hellip: '…' };

function entity(text: string): string {
  const numeric = /^&#(x?)([0-9a-f]+);$/i.exec(text);
  if (numeric) {
    const code = parseInt(numeric[2]!, numeric[1] ? 16 : 10);
    return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : text;
  }
  return ENTITIES[text.slice(1, -1)] ?? text;
}

interface Draw {
  text: string;
  known: (title: string) => boolean;
  open: (title: string) => void;
  /** A page of the share's words by its title, for an embed; null for one the share does not have. */
  bodyOf: (title: string) => string | null;
  /** How many embeds deep these words are, and the pages they are drawn inside of, by their titles' keys. */
  depth: number;
  within: ReadonlySet<string>;
}

const SKIPPED = new Set(['HeaderMark', 'EmphasisMark', 'CodeMark', 'LinkMark', 'QuoteMark', 'ListMark', 'TaskMarker', 'StrikethroughMark', 'CodeInfo', 'LinkTitle', 'LinkLabel', 'URL']);

function children(node: SyntaxNode): SyntaxNode[] {
  const out: SyntaxNode[] = [];
  for (let child = node.firstChild; child; child = child.nextSibling) out.push(child);
  return out;
}

/** A `[[wiki link]]`: a page of the share opens; anything else is its words. */
function wiki(link: WikiLink, d: Draw, key: string): ReactNode {
  const shown = d.text.slice(link.from + 2, link.to - 2).trim();
  return d.known(link.title) ? (
    <button key={key} type="button" className={styles.wiki} onClick={() => d.open(link.title)}>
      {shown}
    </button>
  ) : (
    <span key={key} className={styles.wikiPlain}>
      {shown}
    </span>
  );
}

/**
 * The inline content of `node` between `from` and `to`: its words, and the marks in them drawn. A `[[wiki link]]` is
 * not Markdown, and the parser reads its inner brackets as a link of their own, so the wiki links are found in the
 * words first and each is drawn whole over whatever the parser made of it; one inside a node (code, a link's words) is
 * that node's.
 */
function inline(node: SyntaxNode, d: Draw, key: string, from = node.from, to = node.to): ReactNode[] {
  const out: ReactNode[] = [];
  const links = wikiLinksIn(d.text.slice(from, to), from);
  let at = from;
  let next = 0;
  const words = (until: number) => {
    if (until > at) out.push(d.text.slice(at, until));
    at = Math.max(at, until);
  };
  const wikisBefore = (end: number, inside?: SyntaxNode) => {
    while (next < links.length && links[next]!.from < end) {
      const link = links[next]!;
      if (inside && link.from >= inside.from && link.to <= inside.to) break;
      next += 1;
      if (link.from < at) continue;
      words(link.from);
      out.push(wiki(link, d, `${key}w${link.from}`));
      at = link.to;
    }
  };
  for (const child of children(node)) {
    if (child.to <= from || child.from >= to) continue;
    wikisBefore(child.to, child);
    // A wiki link inside the child is the child's to draw.
    while (next < links.length && links[next]!.from >= child.from && links[next]!.to <= child.to) next += 1;
    // Covered by a wiki link drawn already: gone with it.
    if (child.from < at) continue;
    words(child.from);
    out.push(inlineNode(child, d, `${key}.${child.from}`));
    at = child.to;
  }
  wikisBefore(to);
  words(to);
  return out;
}

/** What a link or a picture says: its words between `[` and `]`. */
function bracketed(node: SyntaxNode): { from: number; to: number } {
  const marks = children(node).filter((c) => c.name === 'LinkMark');
  return { from: marks[0]?.to ?? node.from, to: marks[1]?.from ?? node.to };
}

function inlineNode(node: SyntaxNode, d: Draw, key: string): ReactNode {
  const slice = (n: SyntaxNode) => d.text.slice(n.from, n.to);
  switch (node.name) {
    case 'Emphasis':
      return <em key={key}>{inline(node, d, key)}</em>;
    case 'StrongEmphasis':
      return <strong key={key}>{inline(node, d, key)}</strong>;
    case 'Strikethrough':
      return <del key={key}>{inline(node, d, key)}</del>;
    case 'InlineCode': {
      const marks = children(node).filter((c) => c.name === 'CodeMark');
      return <code key={key}>{d.text.slice(marks[0]?.to ?? node.from, marks[1]?.from ?? node.to)}</code>;
    }
    case 'Link': {
      const url = children(node).find((c) => c.name === 'URL');
      const href = url ? safeHref(slice(url)) : null;
      const inner = bracketed(node);
      const content = inline(node, d, key, inner.from, inner.to);
      return href ? (
        <a key={key} href={href} target="_blank" rel="noopener noreferrer">
          {content}
        </a>
      ) : (
        <span key={key}>{content}</span>
      );
    }
    case 'Image': {
      const url = children(node).find((c) => c.name === 'URL');
      const inner = bracketed(node);
      const alt = d.text.slice(inner.from, inner.to);
      const target = url ? slice(url).trim() : '';
      if (target.startsWith('image/')) return <Picture key={key} name={target.slice('image/'.length)} alt={alt} />;
      const href = safeHref(target);
      return href ? (
        <a key={key} href={href} target="_blank" rel="noopener noreferrer">
          {alt || href}
        </a>
      ) : (
        <span key={key}>{alt}</span>
      );
    }
    case 'Autolink': {
      const url = children(node).find((c) => c.name === 'URL');
      const href = url ? safeHref(slice(url)) : null;
      return href ? (
        <a key={key} href={href} target="_blank" rel="noopener noreferrer">
          {slice(url!)}
        </a>
      ) : (
        <span key={key}>{slice(node)}</span>
      );
    }
    case 'URL': {
      // A bare address in the words (GFM's autolink).
      const text = slice(node);
      const href = safeHref(/^www\./i.test(text) ? `https://${text}` : text);
      return href ? (
        <a key={key} href={href} target="_blank" rel="noopener noreferrer">
          {text}
        </a>
      ) : (
        <span key={key}>{text}</span>
      );
    }
    case 'Escape':
      return <span key={key}>{slice(node).slice(1)}</span>;
    case 'Entity':
      return <span key={key}>{entity(slice(node))}</span>;
    case 'HardBreak':
      return <br key={key} />;
    case 'HTMLTag':
    case 'Comment':
      // The note's own HTML is not run: a tag is its text, a comment nothing.
      return node.name === 'Comment' ? null : <span key={key}>{slice(node)}</span>;
    default:
      return SKIPPED.has(node.name) ? null : <span key={key}>{inline(node, d, key)}</span>;
  }
}

/** A table's cells, and how each column is aligned by its delimiter row. */
function table(node: SyntaxNode, d: Draw, key: string): ReactNode {
  const rows = children(node);
  const delimiter = rows.find((r) => r.name === 'TableDelimiter');
  const aligns = delimiter
    ? d.text
        .slice(delimiter.from, delimiter.to)
        .replace(/^\s*\|/, '')
        .replace(/\|\s*$/, '')
        .split('|')
        .map((cell): 'left' | 'right' | 'center' | undefined => {
          const c = cell.trim();
          return c.startsWith(':') && c.endsWith(':') ? 'center' : c.endsWith(':') ? 'right' : c.startsWith(':') ? 'left' : undefined;
        })
    : [];
  const cells = (row: SyntaxNode, header: boolean) =>
    children(row)
      .filter((c) => c.name === 'TableCell')
      .map((cell, i) => createElement(header ? 'th' : 'td', { key: `${key}c${cell.from}`, style: aligns[i] ? { textAlign: aligns[i] } : undefined }, inline(cell, d, `${key}c${cell.from}`)));
  const head = rows.find((r) => r.name === 'TableHeader');
  return (
    <div key={key} className={styles.tableWrap}>
      <table>
        {head ? (
          <thead>
            <tr>{cells(head, true)}</tr>
          </thead>
        ) : null}
        <tbody>
          {rows
            .filter((r) => r.name === 'TableRow')
            .map((row) => (
              <tr key={`${key}r${row.from}`}>{cells(row, false)}</tr>
            ))}
        </tbody>
      </table>
    </div>
  );
}

/** `at`, past any spaces there. */
function skipSpace(text: string, at: number): number {
  let next = at;
  while (text[next] === ' ' || text[next] === '\t') next += 1;
  return next;
}

function blocks(node: SyntaxNode, d: Draw, key: string): ReactNode[] {
  return children(node).map((child) => block(child, d, `${key}.${child.from}`));
}

/** The link's mark (Lucide's `link-2`), drawn in the words' own ink. */
function LinkMark() {
  return (
    <svg className={styles.embedMark} viewBox="0 0 24 24" width="1em" height="1em" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M9 17H7A5 5 0 0 1 7 7h2" />
      <path d="M15 7h2a5 5 0 1 1 0 10h-2" />
      <line x1="8" x2="16" y1="12" y2="12" />
    </svg>
  );
}

/** An embed: its section drawn in a quoted card where its page is in the share, else where it is from. */
function embedded(embed: Embed, d: Draw, key: string): ReactNode {
  const named = titleKey(embed.title);
  const written = `[[${embed.title}${embed.anchor ? `#${embed.anchor}` : ''}]]`;
  const body = d.bodyOf(embed.title);
  if (body === null || d.depth >= MOST_EMBED_DEPTH || d.within.has(named) || d.within.has(titleKey(noteTitle(body)))) {
    return (
      <p key={key} className={styles.embedFrom} data-embed-from="">
        from <span className={styles.embedName}>{written}</span>
      </p>
    );
  }
  const section = sectionOf(body, embed.anchor);
  const label = `${embed.title}${embed.anchor ? ` › ${embed.anchor}` : ''}`;
  let inside: ReactNode;
  if (section === null) {
    inside = <p className={styles.embedQuiet}>{`${embed.title} has ${embed.anchor!.startsWith('^') ? `no line named ${embed.anchor}` : `no heading “${embed.anchor}”`}.`}</p>;
  } else if (section.trim() === '') {
    inside = <p className={styles.embedQuiet}>{`${embed.title} has no words yet.`}</p>;
  } else {
    const inner: Draw = { ...d, text: section, depth: d.depth + 1, within: new Set([...d.within, named, titleKey(noteTitle(body))]) };
    inside = blocks(markdown.parse(section).topNode, inner, `${key}e`);
  }
  return (
    <blockquote key={key} className={styles.embed} data-embed="" aria-label={`From ${label}`}>
      <div className={styles.embedHead}>
        <LinkMark />
        {d.known(embed.title) ? (
          <button type="button" className={styles.embedTitle} onClick={() => d.open(embed.title)}>
            {label}
          </button>
        ) : (
          <span className={styles.embedTitle}>{label}</span>
        )}
      </div>
      {inside}
    </blockquote>
  );
}

function block(node: SyntaxNode, d: Draw, key: string): ReactNode {
  const heading = /^ATXHeading(\d)$/.exec(node.name);
  if (heading) {
    // The words after `# `, not the space that parts them from it.
    const mark = children(node).find((c) => c.name === 'HeaderMark' && c.from === node.from);
    return createElement(`h${heading[1]}`, { key }, inline(node, d, key, skipSpace(d.text, mark ? mark.to : node.from)));
  }
  switch (node.name) {
    case 'Paragraph': {
      const embed = embedOf(d.text.slice(node.from, node.to));
      return embed ? embedded(embed, d, key) : <p key={key}>{inline(node, d, key)}</p>;
    }
    case 'BulletList':
      return <ul key={key}>{blocks(node, d, key)}</ul>;
    case 'OrderedList': {
      const first = children(node)[0];
      const mark = first ? children(first).find((c) => c.name === 'ListMark') : undefined;
      const start = mark ? parseInt(d.text.slice(mark.from, mark.to), 10) : 1;
      return (
        <ol key={key} start={Number.isFinite(start) && start !== 1 ? start : undefined}>
          {blocks(node, d, key)}
        </ol>
      );
    }
    case 'ListItem': {
      const task = children(node).some((c) => c.name === 'Task');
      return (
        <li key={key} className={task ? styles.task : undefined} data-task={task ? '' : undefined}>
          {blocks(node, d, key)}
        </li>
      );
    }
    case 'Task': {
      const marker = children(node).find((c) => c.name === 'TaskMarker');
      const done = marker ? /x/i.test(d.text.slice(marker.from, marker.to)) : false;
      return (
        <p key={key} data-done={done ? '' : undefined}>
          <input type="checkbox" checked={done} disabled readOnly aria-label={done ? 'Done' : 'To do'} />
          <span>{inline(node, d, key, skipSpace(d.text, marker ? marker.to : node.from))}</span>
        </p>
      );
    }
    case 'Blockquote':
      return <blockquote key={key}>{blocks(node, d, key)}</blockquote>;
    case 'FencedCode':
    case 'CodeBlock': {
      const info = children(node).find((c) => c.name === 'CodeInfo');
      const code = children(node)
        .filter((c) => c.name === 'CodeText')
        .map((c) => d.text.slice(c.from, c.to))
        .join('\n');
      return (
        <pre key={key} className={styles.code} data-lang={info ? d.text.slice(info.from, info.to) : undefined}>
          <code>{code}</code>
        </pre>
      );
    }
    case 'HorizontalRule':
      return <hr key={key} />;
    case 'Table':
      return table(node, d, key);
    case 'ListMark':
    case 'QuoteMark':
    case 'LinkReference':
    case 'CommentBlock':
    case 'ProcessingInstructionBlock':
      return null;
    case 'HTMLBlock':
      // Shown as the text it is: nothing a note holds runs here.
      return (
        <p key={key} className={styles.raw}>
          {d.text.slice(node.from, node.to)}
        </p>
      );
    default:
      return <p key={key}>{d.text.slice(node.from, node.to)}</p>;
  }
}

/** A picture the share carries, drawn once the page has lent it. */
function Picture({ name, alt }: { name: string; alt: string }) {
  const [, redraw] = useState(0);
  useEffect(() => {
    const ready = () => redraw((n) => n + 1);
    window.addEventListener(IMAGE_READY, ready);
    return () => window.removeEventListener(IMAGE_READY, ready);
  }, []);
  const src = imageUrl(name);
  return src ? <img className={styles.picture} src={src} alt={alt} loading="lazy" /> : <span className={styles.missing}>{alt || 'A picture that isn’t in the share.'}</span>;
}

/** The page's words, drawn (see the header). */
export function Rendered({
  body,
  known = () => false,
  open = () => undefined,
  bodyOf = () => null,
}: {
  body: string;
  known?: (title: string) => boolean;
  open?: (title: string) => void;
  /** The share's pages' words by title, for its embeds (see the header). */
  bodyOf?: (title: string) => string | null;
}) {
  const text = useMemo(() => body.slice(frontMatterOffset(body)), [body]);
  const tree = useMemo(() => markdown.parse(text), [text]);
  const own = titleKey(noteTitle(body));
  return <div className={styles.rendered}>{blocks(tree.topNode, { text, known, open, bodyOf, depth: 0, within: new Set(own ? [own] : []) }, 'b')}</div>;
}

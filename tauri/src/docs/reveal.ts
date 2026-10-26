import type { EditorView } from '@codemirror/view';
import { docsHeadings } from './book.ts';
import { fold, matchRanges, queryTerms } from './search.ts';

/**
 * Where a search result lands (Matt, 2026-10-26: "add the ability to search the book"): the page scrolled to the
 * section's heading, `/docs/<page>#<anchor>`, and the words searched for marked in it.
 *
 * The page is the app's own editor, read-only (read/Site.tsx), so nothing is written into its lines: the heading is
 * found in the text the editor holds by the same rule the index was made by (book.ts `docsHeadings`), the window
 * scrolls to where the editor measures it, and the words are marked with the browser's own highlights (`CSS.highlights`, the `docs-find` rule
 * in docs.css), ranges laid over the editor's text and laid again whenever the editor redraws a line, as it does
 * when a line comes into view. A browser without highlights still lands on the heading.
 *
 * Gives back what takes the marks away again, for the next search or the next page.
 */

/** What a link or a search asks the page for: a heading by its anchor ('' for the page's top), and words to mark. */
export interface Target {
  anchor: string;
  find: string;
}

/**
 * How far under the window's top a heading's line lands: its words just clear of the docs' bar, which stays at the
 * top, since a heading's line carries its own room above its words.
 */
const BAR = 40;

/** The most words marked on a page. */
const MARKS = 60;

const HIGHLIGHT = 'docs-find';

interface Highlights {
  set(name: string, value: unknown): void;
  delete(name: string): void;
}

function highlights(): { registry: Highlights; make: (ranges: Range[]) => unknown } | null {
  const registry = (globalThis.CSS as unknown as { highlights?: Highlights } | undefined)?.highlights;
  const Make = (globalThis as unknown as { Highlight?: new (...ranges: Range[]) => unknown }).Highlight;
  if (!registry || !Make) return null;
  return { registry, make: (ranges) => new Make(...ranges) };
}

export function reveal(view: EditorView, target: Target): () => void {
  const doc = view.state.doc;
  const text = doc.toString();
  const headings = docsHeadings(text);
  const at = target.anchor ? headings.findIndex((h) => h.anchor === target.anchor) : -1;
  const heading = at >= 0 ? headings[at]! : null;
  const from = heading ? doc.line(heading.line + 1).from : 0;
  const next = at >= 0 ? headings[at + 1] : headings[0];
  const to = next ? doc.line(next.line + 1).from : doc.length;

  // The words searched for, in the section first, and anywhere on the page where the section has none of them.
  const terms = queryTerms(target.find);
  let ranges = terms.length ? matchRanges(fold(text.slice(from, to)), terms).map(([a, b]) => [a + from, b + from] as [number, number]) : [];
  if (!ranges.length && terms.length) ranges = matchRanges(fold(text), terms);
  ranges = ranges.slice(0, MARKS);

  const scroll = () => {
    if (!heading && !ranges.length) {
      window.scrollTo({ top: 0 });
      return;
    }
    // The heading at the top, unless the first word found is too far under it to be seen there: then that word.
    const first = ranges[0]?.[0];
    const far = first !== undefined && (!heading || view.lineBlockAt(first).top - view.lineBlockAt(from).top > window.innerHeight * 0.6);
    const pos = far ? first : from;
    // The window is what scrolls (the editor grows with its page), so it is scrolled here from the editor's measure of
    // the line, read when the editor reads its layout. Not CodeMirror's own scrollIntoView, which under the docs' bar
    // that stays at the top went round its measuring loop (a console warning) for a heading near a page's top.
    view.requestMeasure({
      read: (v) => v.lineBlockAt(pos).top + v.documentTop + window.scrollY,
      write: (y) => window.scrollTo({ top: Math.max(0, far ? y - window.innerHeight / 2 : y - BAR) }),
    });
  };

  const marks = highlights();
  let frame = 0;
  const paint = () => {
    frame = 0;
    if (!marks) return;
    const laid: Range[] = [];
    for (const [a, b] of ranges) {
      // Only the lines the editor has drawn have text to lay a range on.
      if (a < view.viewport.from || b > view.viewport.to) continue;
      try {
        const start = view.domAtPos(a);
        const end = view.domAtPos(b);
        const range = document.createRange();
        range.setStart(start.node, start.offset);
        range.setEnd(end.node, end.offset);
        if (!range.collapsed) laid.push(range);
      } catch {
        // A word under a mark the editor draws as something else (a link's chip, a widget) is not marked.
      }
    }
    marks.registry.set(HIGHLIGHT, marks.make(laid));
  };
  const later = () => {
    if (!frame) frame = requestAnimationFrame(paint);
  };
  const redrawn = new MutationObserver(later);
  redrawn.observe(view.contentDOM, { childList: true, subtree: true, characterData: true });

  scroll();
  later();
  // Lines above the heading are measured as they are drawn, which can move it: scroll again once they are, and
  // once the page's faces have loaded.
  const settle = window.setTimeout(() => {
    scroll();
    later();
  }, 250);
  void document.fonts?.ready.then(() => later());

  return () => {
    window.clearTimeout(settle);
    if (frame) cancelAnimationFrame(frame);
    redrawn.disconnect();
    marks?.registry.delete(HIGHLIGHT);
  };
}

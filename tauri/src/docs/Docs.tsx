import { Pages, type SitePlace } from '../read/Site.tsx';
import { useSystemDark } from '../read/systemDark.ts';
import { docsPath, docsSlugAt, docsTitle } from './book.ts';
import { DOCS } from './content.ts';
import { DocsSearch } from './DocsSearch.tsx';
import { reveal } from './reveal.ts';

/**
 * Ghost.md Docs at ghostmarkdown.com/docs (book.ts): the book drawn as a published site is (read/Site.tsx), its pages
 * down the side, each at `/docs/<slug>`, drawn formatted, with the website's icon in the bar for the way home, and
 * the book's search in the bar (DocsSearch.tsx), which opens a page at a heading, `/docs/<slug>#<anchor>` (reveal.ts).
 */
const PLACE: SitePlace = {
  slugAt: docsSlugAt,
  path: docsPath,
  title: (page) => docsTitle(DOCS, page),
  home: { href: 'https://ghostmarkdown.com/', label: 'Ghost.md', icon: '/icon.png' },
  // Docs are read, not edited: the marks folded into what they do, as the app's Formatted view draws a note.
  display: 'formatted',
  bar: (open) => <DocsSearch open={open} />,
  reveal,
};

export function Docs() {
  const dark = useSystemDark();
  return <Pages shared={DOCS} dark={dark} place={PLACE} />;
}

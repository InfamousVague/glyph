import { CHAPTER_ABOUT, CHAPTERS, LESSONS, type Chapter, type Lesson } from '../app/academy/lessons.ts';
import { markGroups } from '../app/guide/marks.ts';

/**
 * ghostmarkdown.com's formatting reference (landing/reference.html): every mark a note can carry, on one page to look
 * things up on (Matt: "add a separate page on the website as a easy to follow reference sheet for all of the
 * formatting base markdown and our custom formatting").
 *
 * Written from the Academy's lessons (academy/lessons.ts), which teach every row of the app's cheat sheet and are held
 * to it by their tests, so the page says what the app does: each mark's name, its characters, what it does in a line
 * or two, and an example to copy. Standard Markdown first, the marks any Markdown app reads the same way (`standard`),
 * then Ghost.md's own, in the Academy's chapters. reference.test.ts writes the page from here and fails while the page
 * on disk is not what this would write.
 */

const escape = (text: string) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** A section's id, for the contents' links: its name in lowercase words joined by dashes. */
const slug = (name: string) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');

/** A Lucide icon from the site's sprite (landing/icons.svg, scripts/landing-icons.mjs), by its Lucide name. */
const icon = (name: string, className = 'i') => `<svg class="${className}" aria-hidden="true"><use href="icons.svg#i-${name}"/></svg>`;

/** A Lucide component's name as Lucide writes it: `ListTodo` is `list-todo`, `Heading1` is `heading-1`. */
const lucideName = (component: { displayName?: string } | undefined) =>
  (component?.displayName ?? '')
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/([a-zA-Z])(\d)/g, '$1-$2')
    .toLowerCase();

/** A lesson that goes further with another's mark has no cheat-sheet row of its own, so no icon of its own either. */
const OWN_ICONS: Readonly<Record<string, string>> = {
  boardHeight: 'move-vertical',
  notebookKey: 'key-round',
  queryWhere: 'funnel',
  queryShow: 'layout-dashboard',
  queryGroup: 'sigma',
};

/** Each lesson's icon: its cheat-sheet row's (guide/marks.ts), the one the app shows beside the mark. */
function iconOf(lesson: Lesson): string {
  const own = OWN_ICONS[lesson.id];
  if (own) return own;
  const row = markGroups()
    .flatMap((group) => group.rows)
    .find((one) => one.name === lesson.rows[0]);
  return lucideName(row?.icon as { displayName?: string } | undefined) || 'type';
}

/** Each section's icon, by its id. */
const SECTION_ICONS: Readonly<Record<string, string>> = {
  markdown: 'heading',
  'more-markdown': 'square-code',
  'lines-that-do-more': 'list-checks',
  'links-and-places': 'link',
  'boards-and-to-dos': 'layout-grid',
  'tickets-and-queries': 'ticket',
  'marks-and-effects': 'highlighter',
};

function row(lesson: Lesson): string {
  return `          <article class="ref-row" id="${slug(lesson.title)}">
            <div class="ref-name">
              <h3>${icon(iconOf(lesson), 'i ref-icon')}<span>${escape(lesson.title)}</span></h3>
              <code class="ref-symbol">${escape(lesson.symbol)}</code>
            </div>
            <p class="ref-what">${escape(lesson.teach)}</p>
            <div class="ref-example">
              <pre><code>${escape(lesson.example)}</code></pre>
              <button type="button" class="ref-copy" data-copy-text="${escape(lesson.example)}" aria-label="Copy the example for ${escape(lesson.title)}">${icon('copy')}<span>Copy</span></button>
            </div>
          </article>`;
}

interface Section {
  id: string;
  title: string;
  lead: string;
  lessons: Lesson[];
}

function section(part: Section): string {
  return `        <section class="ref-section" id="${part.id}" aria-labelledby="${part.id}-title">
          <header class="ref-head">
            <h2 id="${part.id}-title">${icon(SECTION_ICONS[part.id] ?? 'type')}<span>${escape(part.title)}</span></h2>
            <p>${escape(part.lead)}</p>
          </header>
${part.lessons.map(row).join('\n')}
        </section>`;
}

/** The page's sections: standard Markdown, then each of the Academy's chapters with what is left of it. */
export function referenceSections(): Section[] {
  const standard: Section = {
    id: 'markdown',
    title: 'Standard Markdown',
    lead: 'What every Markdown app reads the same way: write these anywhere and they keep their meaning.',
    lessons: LESSONS.filter((lesson) => lesson.standard),
  };
  const own = CHAPTERS.map((chapter: Chapter) => ({
    id: slug(chapter),
    title: chapter,
    lead: CHAPTER_ABOUT[chapter],
    lessons: LESSONS.filter((lesson) => lesson.chapter === chapter && !lesson.standard),
  })).filter((part) => part.lessons.length);
  return [standard, ...own];
}

/** The whole page, as landing/reference.html holds it. */
export function referencePage(): string {
  const sections = referenceSections();
  const [standard, ...own] = sections;
  const chip = (part: Section) => `<li><a href="#${part.id}">${icon(SECTION_ICONS[part.id] ?? 'type')}<span>${escape(part.title)}</span></a></li>`;
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <title>Formatting reference · Ghost.md</title>
    <meta name="description" content="Every mark a Ghost.md note can carry, on one page: standard Markdown, then to-dos with due days and people, tickets, boards, queries, maths and the rest, each with an example to copy." />
    <link rel="icon" type="image/png" href="favicon.png" />
    <link rel="apple-touch-icon" href="apple-touch-icon.png" />
    <meta name="theme-color" content="#0b0b0b" />
    <!--
      Written by src/landing/reference.ts from the Academy's lessons (src/app/academy/lessons.ts): change a lesson, then
      WRITE_REFERENCE=1 npx vitest run src/landing/reference.test.ts writes this page again. Do not edit it by hand.
    -->
    <link rel="preload" href="fonts/inter.woff2" as="font" type="font/woff2" crossorigin />
    <link rel="stylesheet" href="glacier/tokens.css" />
    <link rel="stylesheet" href="site.css" />
    <link rel="stylesheet" href="home.css" />
    <link rel="stylesheet" href="reference.css" />
    <script src="theme.js"></script>
    <script src="reference.js" defer></script>
  </head>
  <body>
    <a class="skip" href="#main">Skip to the page</a>

    <header class="bar">
      <nav class="bar-in" aria-label="Ghost.md">
        <a class="brand" href="/"><img src="icon.png" width="32" height="32" alt="" /><span>Ghost.md</span></a>
        <ul class="bar-links">
          <li><a href="/#organise">Organise</a></li>
          <li><a href="/#plan">Plan</a></li>
          <li><a href="/#ai">AI</a></li>
          <li><a href="reference.html" aria-current="page">Formatting</a></li>
        </ul>
        <a class="pill pill-ink bar-cta" href="/#download">${icon('download')}<span>Download</span></a>
      </nav>
    </header>

    <main id="main" class="wrap ref">
      <header class="ref-top">
        <p class="eyebrow">${icon('book-open')}Reference</p>
        <h1>Every mark a note can carry.</h1>
        <p class="lead">A note is plain Markdown. Type a mark's characters and Ghost.md draws what they mean; in any other app they still read as words. Standard Markdown comes first, then what Ghost.md adds.</p>
        <nav class="ref-contents" aria-label="On this page">
          <ul>${[standard!, ...own].map(chip).join('')}</ul>
        </nav>
      </header>

${sections.map(section).join('\n\n')}

      <p class="fine center ref-foot">Learn them one at a time, by typing each, in the app's Academy: Settings › About › Ghost.md Academy. The marks in Marks and effects come with the Marks plugin, on unless you switch it off.</p>
    </main>

    <footer class="foot">
      <div class="wrap foot-in">
        <p class="brand"><img src="icon.png" width="28" height="28" alt="" /><span>Ghost.md</span></p>
        <ul>
          <li><a href="/">Home</a></li>
          <li><a href="privacy.html">Privacy</a></li>
          <li><a href="delete-account.html">Delete your account</a></li>
        </ul>
      </div>
    </footer>
  </body>
</html>
`;
}

import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { build, type BuildResult } from '../src/build.ts';
import { parseArgs } from '../src/cli.ts';
import { configFrom, DEFAULTS } from '../src/config.ts';
import { readFrontMatter } from '../src/frontMatter.ts';
import { byPinnedThenTitle, readLibrary } from '../src/library.ts';
import { headingId, relativeHref, resolver } from '../src/links.ts';
import { turnOf } from '../src/meeting.ts';

/*
 * ghost-publish over the fixture library (publish/fixtures/library): a folder with Inbox, two workspaces one of them
 * nested, an organization, a trashed note, a private note, tickets in both front-matter shapes, a notebook, a canvas
 * with a .canvas sidecar, a meeting with turns and its tape, and a note that links every way a note can. The site is
 * built once into a temporary folder and every test reads it.
 */

const here = import.meta.dirname;
const FIXTURE = join(here, '..', 'fixtures', 'library');
const TODAY = '2026-10-31';

let out: string;
let assets: string;
let result: BuildResult;

const read = (href: string) => readFileSync(join(out, ...href.split('/')), 'utf8');
const has = (href: string) => existsSync(join(out, ...href.split('/')));

function* files(dir: string): Generator<string> {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* files(path);
    else yield path;
  }
}

beforeAll(() => {
  const scratch = mkdtempSync(join(tmpdir(), 'ghost-publish-'));
  out = join(scratch, 'site');
  // The bundle's assets stand in for: one stylesheet and the search script, as dist/assets holds after a build.
  assets = join(scratch, 'assets');
  mkdirSync(assets, { recursive: true });
  writeFileSync(join(assets, 'site.css'), 'body { color: black; }\n');
  copyFileSync(join(here, '..', 'client', 'search.js'), join(assets, 'search.js'));
  result = build({ library: FIXTURE, out, assets: { dir: assets, css: ['assets/site.css'], search: 'assets/search.js' }, today: TODAY });
});

afterAll(() => {
  rmSync(join(out, '..'), { recursive: true, force: true });
});

describe('the front matter, both shapes', () => {
  it('reads two blocks as the library’s and the page’s', () => {
    const front = readFrontMatter('---\nid: 4e5f6a7b-8c9d-4e0f-1a2b-3c4d5e6f7a8b\npinned: true\n---\n---\ntype: ticket\nid: GHO-1\nstatus: In progress\n---\n# Fix\n\nWords.\n');
    expect(front.blocks).toBe(2);
    expect(front.managed).toEqual({ id: '4e5f6a7b-8c9d-4e0f-1a2b-3c4d5e6f7a8b', pinned: 'true' });
    expect(front.page).toEqual({ type: 'ticket', id: 'GHO-1', status: 'In progress' });
    expect(front.body).toBe('# Fix\n\nWords.\n');
  });

  it('reads one merged block, the library’s id as the library’s and the ticket’s key as the page’s', () => {
    const front = readFrontMatter('---\nid: 5f6a7b8c-9d0e-4f1a-2b3c-4d5e6f7a8b9c\ncreated: 2026-09-29T09:00:00Z\ntype: ticket\nissue: GHO-2\nstatus: To do\n---\n# Pricing\n');
    expect(front.blocks).toBe(1);
    expect(front.managed).toEqual({ id: '5f6a7b8c-9d0e-4f1a-2b3c-4d5e6f7a8b9c', created: '2026-09-29T09:00:00Z' });
    expect(front.page).toEqual({ type: 'ticket', issue: 'GHO-2', status: 'To do' });
    // An old one-block ticket whose `id:` is its key keeps it as the page's.
    expect(readFrontMatter('---\ntype: ticket\nid: GHO-7\n---\n# T\n').page.id).toBe('GHO-7');
  });

  it('reads none where there is none', () => {
    expect(readFrontMatter('# Plain\n\nWords.')).toEqual({ managed: {}, page: {}, body: '# Plain\n\nWords.', blocks: 0 });
  });
});

describe('the library', () => {
  it('counts the pages: every .md outside dot folders, .trash/, orgs/ and README.md, less the private one', () => {
    // Welcome, Trip plan, Launch, Fix the login loop, Pricing page, Done thing, Work/Plan, Home/Plan, Acme brief, Roadmap, Standup.
    expect(result.pages).toBe(11);
    expect(result.config.title).toBe('Fixture Library');
    expect(result.config.description).toBe('Notes from a fixture library.');
    expect(result.config.recent).toBe(5);
  });

  it('leaves out the private note, the trashed note, the organization and the README', () => {
    const everything = [...files(out)].filter((path) => path.endsWith('.html')).map((path) => readFileSync(path, 'utf8')).join('\n');
    expect(everything).not.toContain('pelican');
    expect(everything).not.toContain('albatross');
    expect(everything).not.toContain('Team note');
    expect(everything).not.toContain('Anyone who can read this repository');
    expect(has('inbox/private-thoughts.html')).toBe(false);
  });

  it('publishes an organization when the config says so, and only the folders named', () => {
    const library = readLibrary(FIXTURE, configFrom({ orgs: true }));
    expect(library.pages.some((page) => page.title === 'Team note')).toBe(true);
    const only = readLibrary(FIXTURE, configFrom({ folders: ['workspaces/Home'] }));
    expect(only.pages.map((page) => page.file)).toEqual(['workspaces/Home/Plan.md']);
    const byName = readLibrary(FIXTURE, configFrom({ orgs: ['Nobody'] }));
    expect(byName.pages.some((page) => page.folder[0] === 'orgs')).toBe(false);
  });

  it('knows what each page is', () => {
    const library = readLibrary(FIXTURE, DEFAULTS);
    const kind = (title: string) => library.pages.find((page) => page.title === title)?.kind;
    expect(kind('Welcome')).toBe('note');
    expect(kind('Fix the login loop')).toBe('ticket');
    expect(kind('Pricing page')).toBe('ticket');
    expect(kind('Launch')).toBe('notebook');
    expect(kind('Roadmap')).toBe('canvas');
    expect(kind('Standup')).toBe('meeting');
    expect(library.pages.find((page) => page.title === 'Pricing page')?.issue).toBe('GHO-2');
    expect(library.pages.find((page) => page.title === 'Fix the login loop')?.issue).toBe('GHO-1');
    expect(library.pages.find((page) => page.title === 'Trip plan')?.aliases).toEqual(['Trip', 'The cabin trip']);
  });

  it('orders the sidebar: Inbox, then the workspaces, pinned first then by title in each', () => {
    const library = readLibrary(FIXTURE, DEFAULTS);
    expect(library.tree.folders.map((folder) => folder.name)).toEqual(['Inbox', 'workspaces']);
    const inbox = library.tree.folders[0]!;
    expect(inbox.pages.map((page) => page.title)).toEqual(['Welcome', 'Trip plan']);
    const workspaces = library.tree.folders[1]!;
    expect(workspaces.folders.map((folder) => folder.name)).toEqual(['Home', 'Work']);
    const work = workspaces.folders[1]!;
    expect(work.pages.map((page) => page.title)).toEqual(['Fix the login loop', 'Done thing', 'Launch', 'Plan', 'Pricing page', 'Roadmap', 'Standup']);
    expect(work.folders.map((folder) => folder.name)).toEqual(['Clients']);
    const sorted = [...work.pages].sort(byPinnedThenTitle).map((page) => page.title);
    expect(sorted[0]).toBe('Fix the login loop');
  });

  it('gives each page an address from its folders and title', () => {
    const library = readLibrary(FIXTURE, DEFAULTS);
    const href = (title: string, folder: string) => library.pages.find((page) => page.title === title && page.folder.join('/') === folder)?.href;
    expect(href('Welcome', 'Inbox')).toBe('inbox/welcome.html');
    expect(href('Acme brief', 'workspaces/Work/Clients')).toBe('workspaces/work/clients/acme-brief.html');
    expect(href('Plan', 'workspaces/Work')).toBe('workspaces/work/plan.html');
    expect(href('Plan', 'workspaces/Home')).toBe('workspaces/home/plan.html');
  });
});

describe('links', () => {
  it('walks from one address to another', () => {
    expect(relativeHref('inbox/welcome.html', 'inbox/trip-plan.html')).toBe('trip-plan.html');
    expect(relativeHref('inbox/welcome.html', 'workspaces/work/plan.html')).toBe('../workspaces/work/plan.html');
    expect(relativeHref('workspaces/work/clients/acme-brief.html', 'index.html')).toBe('../../../index.html');
    expect(relativeHref('index.html', 'image/a.jpg')).toBe('image/a.jpg');
  });

  it('names a heading', () => {
    expect(headingId('Milestones')).toBe('milestones');
    expect(headingId('## The **plan**, 2026')).toBe('the-plan-2026');
    expect(headingId('^venue')).toBe('venue');
  });

  it('resolves every form of wiki link from the welcome page', () => {
    const library = readLibrary(FIXTURE, DEFAULTS);
    const links = resolver(library);
    const welcome = library.pages.find((page) => page.title === 'Welcome')!;
    expect(links.hrefOf(welcome, 'Trip plan', null)).toBe('trip-plan.html');
    expect(links.hrefOf(welcome, 'trip PLAN', null)).toBe('trip-plan.html');
    expect(links.hrefOf(welcome, 'Trip', null)).toBe('trip-plan.html');
    expect(links.hrefOf(welcome, 'The cabin trip', null)).toBe('trip-plan.html');
    expect(links.hrefOf(welcome, 'Launch', 'Milestones')).toBe('../workspaces/work/launch.html#milestones');
    expect(links.hrefOf(welcome, 'GHO-1', null)).toBe('../workspaces/work/fix-the-login-loop.html');
    expect(links.hrefOf(welcome, 'GHO-2', null)).toBe('../workspaces/work/pricing-page.html');
    expect(links.hrefOf(welcome, 'Work/Plan', null)).toBe('../workspaces/work/plan.html');
    expect(links.hrefOf(welcome, 'Nowhere', null)).toBeNull();
    expect(links.hrefOf(welcome, 'Welcome', 'Plan')).toBe('#plan');
  });

  it('disambiguates a shared title by the linking page’s folder', () => {
    const library = readLibrary(FIXTURE, DEFAULTS);
    const links = resolver(library);
    const fix = library.pages.find((page) => page.title === 'Fix the login loop')!;
    const home = library.pages.find((page) => page.title === 'Plan' && page.folder[1] === 'Home')!;
    expect(links.hrefOf(fix, 'Plan', null)).toBe('plan.html');
    expect(links.pageOf(home, 'Plan')).toBe(home);
    const welcome = library.pages.find((page) => page.title === 'Welcome')!;
    // From the Inbox neither is nearer: the first by path, Home's.
    expect(links.hrefOf(welcome, 'Plan', null)).toBe('../workspaces/home/plan.html');
  });

  it('writes them into the page', () => {
    const html = read('inbox/welcome.html');
    expect(html).toContain('<a class="_wiki_');
    expect(html).toContain('href="trip-plan.html">Trip plan</a>');
    expect(html).toContain('href="trip-plan.html">the trip</a>');
    expect(html).toContain('href="trip-plan.html">Trip</a>');
    expect(html).toContain('href="../workspaces/work/launch.html#milestones">Launch#Milestones</a>');
    expect(html).toContain('href="../workspaces/work/fix-the-login-loop.html">GHO-1</a>');
    expect(html).toContain('href="../workspaces/work/plan.html">Work/Plan</a>');
    expect(html).toContain('<span title="No page called “Nowhere”">Nowhere</span>');
    // The embed is drawn in place, from the trip's Packing section, with a link to the page.
    expect(html).toContain('aria-label="From Trip plan › Packing"');
    expect(html).toContain('A torch');
    // The heading the link lands on has its id.
    expect(read('workspaces/work/launch.html')).toContain('<h2 id="milestones">Milestones</h2>');
  });

  it('resolves and copies the files the notes link, and says where a missing one was', () => {
    const html = read('inbox/welcome.html');
    expect(html).toContain('src="../image/aaaa1111-0000-4000-8000-000000000001.jpg"');
    expect(html).toContain('href="../file/report.pdf">in a file</a>');
    expect(has('image/aaaa1111-0000-4000-8000-000000000001.jpg')).toBe(true);
    expect(has('file/report.pdf')).toBe(true);
    expect(html).toContain('>gone</span>');
    expect(result.files).toBe(3);
  });
});

describe('pages', () => {
  it('shows a ticket’s properties and hides the library’s keys, in both shapes', () => {
    const two = read('workspaces/work/fix-the-login-loop.html');
    expect(two).toContain('<dt>status</dt><dd>In progress</dd>');
    expect(two).toContain('<dt>assignee</dt><dd>Sam</dd>');
    expect(two).toContain('<dt>blocked-by</dt><dd><span><a href="pricing-page.html">GHO-2</a></span></dd>');
    expect(two).not.toContain('4e5f6a7b-8c9d-4e0f-1a2b-3c4d5e6f7a8b');
    expect(two).not.toContain('<dt>created</dt>');
    expect(two).not.toContain('<dt>pinned</dt>');
    const one = read('workspaces/work/pricing-page.html');
    expect(one).toContain('<dt>issue</dt><dd>GHO-2</dd>');
    expect(one).toContain('<dt>priority</dt><dd>highest</dd>');
    expect(one).not.toContain('5f6a7b8c-9d0e-4f1a-2b3c-4d5e6f7a8b9c');
    expect(one).not.toContain('<dt>source</dt>');
    // A place is never published (lib/share/carried.dart strips it from a share too).
    expect(read('inbox/trip-plan.html')).not.toContain('51.5074');
  });

  it('runs a query at build time', () => {
    const html = read('inbox/welcome.html');
    expect(html).toContain('data-fence="query"');
    expect(html).toContain('Tickets: 2 · run on 2026-10-31');
    expect(html).toContain('GHO-1');
    expect(html).toContain('GHO-2');
    expect(html).not.toContain('GHO-3');
    expect(html).toContain('href="../workspaces/work/fix-the-login-loop.html">GHO-1</a>');
  });

  it('draws the gantt as the reader’s list, the form read-only, the board as lanes, and the rules and comments behind toggles', () => {
    const html = read('inbox/welcome.html');
    expect(html).toContain('aria-label="Gantt chart: Waitlist launch"');
    expect(html).toContain('Design the waitlist');
    expect(html).toContain('data-fence="form"');
    expect(html).toContain('<strong>Summary</strong> — a line, required');
    expect(html).toContain('one of Annoying, Blocking');
    expect(html).toContain('Button: Send report');
    expect(html).not.toContain('<input type="text"');
    expect(html).toContain('data-fence="board"');
    expect(html).toContain('<h4>To do</h4><ul><li>Book the venue</li></ul>');
    expect(html).toContain('<li data-done="">Pick the weekend</li>');
    expect(html).toMatch(/<details class="_fenceDetails_[^"]*" data-fence="rules"><summary>2 rules<\/summary>/);
    expect(html).toMatch(/<details class="_fenceDetails_[^"]*" data-fence="comments"><summary>1 comment<\/summary>/);
    expect(html).toContain('Is this the right place for the button?');
    expect(html).toContain('Yes, leave it.');
    // The button is inert: no ghost: link.
    expect(html).not.toContain('href="ghost:');
    expect(html).toContain('<span>Done</span>');
    // The app's bookkeeping in the prose is not printed: the comment's anchor, the items' anchors.
    expect(html).toContain('when you are through.</p>');
    expect(html).toContain('<span>Book the venue</span>');
    expect(html).not.toContain('^venue');
  });

  it('draws the canvas still, from its sidecar', () => {
    const html = read('workspaces/work/roadmap.html');
    expect(html).toContain('<svg viewBox=');
    expect(html).toContain('aria-label="Canvas: Roadmap"');
    expect(html).toContain('Ship the waitlist');
    expect(html).toContain('Q4');
    expect(html).toContain('href="fix-the-login-loop.html"');
    expect(html).toContain('href="https://ghostmarkdown.com"');
    expect(html).toContain('<summary>4 cards</summary>');
    expect(html).not.toContain('The sidecar wins');
    expect(html).toContain('marker-end="url(#canvas-arrow)"');
  });

  it('draws the meeting as Summary | Transcript with its tape', () => {
    const html = read('workspaces/work/standup.html');
    expect(html).toContain('data-meeting=""');
    expect(html).toContain('Meeting · Sam Lee, Alex Kim');
    expect(html).toContain('id="view-summary" name="meeting-view" checked=""');
    expect(html).toContain('id="view-transcript" name="meeting-view"/>');
    expect(html).toContain('Beta goes to the waitlist first.');
    expect(html).toContain('>Sam Lee</strong><span class="_at_');
    expect(html).toContain('>0:04</span>');
    expect(html).toContain('the token refreshes twice.');
    expect(html).toContain('<audio class="_tape_');
    expect(html).toContain('src="../../recordings/7c9e6679-7425-40de-944b-e07fc1f90ae7.wav"');
    expect(has('recordings/7c9e6679-7425-40de-944b-e07fc1f90ae7.wav')).toBe(true);
    // The transcript is not in the summary pane.
    const summary = html.slice(html.indexOf('data-pane="summary"'), html.indexOf('data-pane="transcript"'));
    expect(summary).not.toContain('0:21');
  });

  it('reads a turn each way it is written', () => {
    expect(turnOf('**Sam Lee (0:04):** Morning.')).toEqual({ speaker: 'Sam Lee', at: '0:04', text: 'Morning.' });
    expect(turnOf('(1:02:03) Someone.')).toEqual({ speaker: null, at: '1:02:03', text: 'Someone.' });
    expect(turnOf('**Sam Lee:** Sorry.')).toEqual({ speaker: 'Sam Lee', at: null, text: 'Sorry.' });
    expect(turnOf('Plain words.')).toEqual({ speaker: null, at: null, text: 'Plain words.' });
  });

  it('has the chrome: a sidebar with the current page, breadcrumbs, the title and the foot', () => {
    const html = read('workspaces/work/clients/acme-brief.html');
    expect(html).toContain('<title>Acme brief · Fixture Library</title>');
    expect(html).toContain('aria-current="page"');
    expect(html).toContain('href="../../../inbox/welcome.html"');
    expect(html).toContain('<summary>Clients</summary>');
    expect(html).toContain('Home</a><span aria-hidden="true"> › </span><span>workspaces</span><span aria-hidden="true"> › </span><span>Work</span><span aria-hidden="true"> › </span><span>Clients</span>');
    expect(html).toContain('Made with');
    expect(html).toContain('<link rel="canonical" href="https://notes.example.com/workspaces/work/clients/acme-brief.html"/>');
    expect(html).toContain('data-pinned=""');
  });

  it('matches its snapshot', () => {
    expect(read('workspaces/work/fix-the-login-loop.html')).toMatchSnapshot();
  });
});

describe('the site', () => {
  it('has a home page with the pinned notes then the recent ones, a 404, a sitemap, a feed and robots', () => {
    const home = read('index.html');
    expect(home).toContain('<h1 class="_title_');
    expect(home).toContain('Fixture Library</h1>');
    expect(home).toContain('Notes from a fixture library.');
    const pinned = home.slice(home.indexOf('>Pinned<'), home.indexOf('>Recent<'));
    expect(pinned).toContain('>Welcome</a>');
    expect(pinned).toContain('>Fix the login loop</a>');
    expect(pinned).not.toContain('>Trip plan</a>');
    const recent = home.slice(home.indexOf('>Recent<'));
    expect(recent.match(/<li class="_card_/g)?.length).toBe(5);
    expect(recent.indexOf('>Welcome</a>')).toBeLessThan(recent.indexOf('>Standup</a>'));
    expect(has('404.html')).toBe(true);
    expect(read('404.html')).toContain('Nothing to read here');
    expect(read('404.html')).toContain('<link rel="stylesheet" href="/assets/site.css"/>');
    const sitemap = read('sitemap.xml');
    expect(sitemap).toContain('<loc>https://notes.example.com/inbox/welcome.html</loc>');
    expect(sitemap.match(/<url>/g)?.length).toBe(12);
    const feed = read('feed.xml');
    expect(feed).toContain('<feed xmlns="http://www.w3.org/2005/Atom">');
    expect(feed.match(/<entry>/g)?.length).toBe(5);
    expect(feed).toContain('<title>Welcome</title>');
    expect(read('robots.txt')).toContain('Sitemap: https://notes.example.com/sitemap.xml');
  });

  it('indexes every page for the search, words and all, and no fences', () => {
    const index = JSON.parse(read('search.json')) as { title: string; href: string; folder: string; text: string; kind: string }[];
    expect(index).toHaveLength(11);
    const welcome = index.find((entry) => entry.title === 'Welcome')!;
    expect(welcome.href).toBe('inbox/welcome.html');
    expect(welcome.folder).toBe('Inbox');
    expect(welcome.text).toContain('This library is a fixture for the publisher.');
    expect(welcome.text).toContain('Trip plan');
    expect(welcome.text).not.toContain('from: tickets');
    expect(welcome.text).not.toContain('c1 matt');
    const roadmap = index.find((entry) => entry.title === 'Roadmap')!;
    expect(roadmap.kind).toBe('canvas');
    expect(roadmap.text).toContain('Ship the waitlist');
    expect(index.some((entry) => entry.text.includes('pelican'))).toBe(false);
    expect(has('assets/search.js')).toBe(true);
    expect(read('inbox/welcome.html')).toContain('<script src="../assets/search.js" defer=""></script>');
  });

  it('fetches nothing from anywhere but itself', () => {
    for (const path of files(out)) {
      if (!/\.(html|css|js)$/.test(path)) continue;
      const text = readFileSync(path, 'utf8');
      // What a browser fetches: scripts, stylesheets, pictures, sound and film. A canonical link is the page's own name, not a fetch.
      for (const match of text.matchAll(/<(?:script|img|audio|video|source)\b[^>]*\bsrc="([^"]*)"|<link rel="stylesheet" href="([^"]*)"/g)) {
        expect(match[1] ?? match[2], `${path}: ${match[0]}`).not.toMatch(/^(https?:)?\/\//);
      }
      for (const match of text.matchAll(/url\(\s*['"]?([^'")]+)/g)) expect(match[1], path).not.toMatch(/^(https?:)?\/\//);
      expect(text).not.toMatch(/cdn\.|unpkg\.com|jsdelivr|googleapis|cloudflare/i);
    }
  });

  it('writes well-formed pages', () => {
    for (const path of files(out)) {
      if (!path.endsWith('.html')) continue;
      const html = readFileSync(path, 'utf8');
      expect(html.startsWith('<!doctype html>\n<html lang="en">'), path).toBe(true);
      expect(html.match(/<html\b/g)?.length, path).toBe(1);
      expect(html.match(/<\/html>/g)?.length, path).toBe(1);
      expect(html.match(/<head>/g)?.length, path).toBe(1);
      expect(html.match(/<body\b/g)?.length, path).toBe(1);
      expect(html, path).toContain('<meta charSet="utf-8"/>');
      expect(html, path).toContain('<meta name="viewport" content="width=device-width, initial-scale=1"/>');
      expect(html, path).toMatch(/<title>[^<]+<\/title>/);
      expect(html, path).not.toContain('undefined');
      expect(html, path).not.toContain('[object Object]');
      expect(html, path).not.toContain('NaN');
    }
  });
});

describe('the command line', () => {
  it('reads its arguments', () => {
    expect(parseArgs(['./', '--out', 'site'])).toMatchObject({ library: './', out: 'site' });
    expect(parseArgs(['lib', '--title', 'Notes', '--base', 'https://n.example', '--noindex', '--today', '2026-01-01'])).toMatchObject({ library: 'lib', title: 'Notes', baseUrl: 'https://n.example', robots: 'noindex', today: '2026-01-01' });
    expect(parseArgs(['-h']).help).toBe(true);
    expect(() => parseArgs(['--out'])).toThrow('wants a value');
    expect(() => parseArgs(['a', 'b'])).toThrow('One library');
  });

  it('respects noindex', () => {
    const scratch = mkdtempSync(join(tmpdir(), 'ghost-publish-noindex-'));
    try {
      build({ library: FIXTURE, out: join(scratch, 'site'), assets: { dir: assets, css: ['assets/site.css'], search: 'assets/search.js' }, today: TODAY, config: { robots: 'noindex', title: 'Quiet' } });
      const home = readFileSync(join(scratch, 'site', 'index.html'), 'utf8');
      expect(home).toContain('<meta name="robots" content="noindex, nofollow"/>');
      expect(home).toContain('<title>Quiet</title>');
      expect(readFileSync(join(scratch, 'site', 'robots.txt'), 'utf8')).toContain('Disallow: /');
    } finally {
      rmSync(scratch, { recursive: true, force: true });
    }
  });

  it('refuses to write over the library', () => {
    expect(() => build({ library: FIXTURE, out: FIXTURE, assets: { dir: assets, css: [], search: 'assets/search.js' } })).toThrow('over the library');
  });
});

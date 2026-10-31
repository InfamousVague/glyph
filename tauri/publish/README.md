# ghost-publish

A Ghost.md Library folder (a clone of its git repository, docs/MARKDOWN_FIRST.md §6) as a static website: every note a
page drawn by the reader's own renderer (src/read/Rendered.tsx), `[[wiki links]]` resolved, a sidebar from the folders,
a home page, search, light and dark as the system is, hosted anywhere that serves files. Matt, 2026-10-31 (§11,
decision 4): "build the publisher now".

## Running it

From `tauri/`, with the app's `node_modules` installed:

```
npm run build:publish                                  # once: publish/dist/ghost-publish.js and its assets
npm run publish:site -- ~/Library ./site               # or:
node publish/bin/ghost-publish.mjs <Library> --out site [--title …] [--base https://…] [--noindex] [--today YYYY-MM-DD]
```

`bin/ghost-publish.mjs` builds the bundle itself when `dist/` is missing and Vite is beside it. The bundle is one file
with no dependencies (React's server renderer, lezer and the app's modules all in it), so a copy of `publish/` with its
`dist/` runs with Node alone: `node ghost-publish/bin/ghost-publish.mjs ./ --out site`.

Tests: `npm run test:publish` (publish/test, over publish/fixtures/library). The reader's own suite, `npx vitest run
src/read`, proves the renderer still draws the share page as it did.

## What a page gets

| In the note | On the site |
|---|---|
| Front matter, both shapes (§2: the library's block then the page's, or one merged block with `issue:`) | The page's keys as a small properties block over the words; the library's (`id`, `created`, `updated`, `pinned`, `archived`, `source`) hidden; `location`/`place` never shown (as a share strips them) |
| `[[Note]]`, `[[Note|alias]]`, `[[Note#Heading]]`, `[[Note#^line]]`, `[[GHO-12]]`, `[[Folder/Note]]`, `aliases:` | A link to the page (by title, case and punctuation aside, across folders; a shared title goes to the page in the same folder, then the nearest), with the heading's id; a name no page has is its words with the name in a `title` |
| `![[Note#Heading]]` | The section drawn in place, as the share page does (src/read/embeds.ts) |
| `![](image/…)`, `[x](file/…)`, `![](video/…)`, `recordings/<id>.wav` | The file copied to the same path and linked; only files some page links are copied |
| A canvas (`<Title>.canvas` beside the note, else the note's own JSON Canvas) | One still SVG: cards where they sit, groups behind them, edges with arrows; a file card links to its page; the cards listed under it |
| A meeting (`meeting: true`, or a `## Transcript` / `## Captions` section) | Summary \| Transcript as the share page draws it, a two-radio toggle with no script; the tape as `<audio>` when `recordings/<id>.wav` is in the repository |
| ```` ```gantt ```` | The reader's readable list (src/read/gantt.ts) |
| ```` ```query ```` | Run at build time over every page with the app's engine (src/app/core/query, the one the web editor ran) and drawn as the table, list, board, calendar or count it asks for, rows linking to their notes; "today" is the build's day (`--today` fixes it) |
| ```` ```form ```` | A read-only list of its fields and a line saying a form takes answers through a Ghost.md share link |
| ```` ```rules ````, ```` ```comments ```` | Hidden behind a `<details>` toggle; comments read as threads with replies and resolutions |
| ```` ```board ```` | Lanes as headings, each card's words looked up by its anchor |
| ```` ```mermaid ````, any other fence | A code block (the site carries no script but its own search) |
| `[Label](ghost:…)` | Inert words, as on the reader page |
| `[^c1]`, ` ^anchor` | Not printed |
| `private: true` | The note is left out |
| `.trash/`, dot folders, `README.md` at the root | Never published |

Every address is relative to the page, so the site works at a domain's root, under GitHub Pages' `/<repo>/`, or opened
from a folder. Nothing is fetched from anywhere but the site: the fonts (Inter, JetBrains Mono) and styles are in
`assets/`, and the search (`assets/search.js`, `search.json`) runs in the browser.

## Config

`publish.json` at the library's root, or the `publish` key of `.glyph/config.json`; `publish.json` wins key by key,
and the command line over both.

| Key | What it does | Default |
|---|---|---|
| `title` | The site's name | the folder's name |
| `description` | A line under the title on the home page | none |
| `baseUrl` | Where it will live: canonical links, `sitemap.xml`, `feed.xml`, `robots.txt` | none (relative only) |
| `folders` | Folders to publish, by path from the root (`["Inbox", "workspaces/Work"]`) | every personal folder |
| `orgs` | `true` for every organization, or the names under `orgs/` to publish | `false` |
| `robots` | `"noindex"` asks search engines to stay out (meta tag and `robots.txt`) | indexable |
| `recent` | How many notes the home page lists after the pinned ones, and the feed carries | 20 |

`.trash/` is never published whatever the config says. Per note, `private: true` in the front matter keeps it off.

## Output

`site/` (or `--out`): `index.html` (pinned notes, then recent by `updated:` or the file's time), `<folder>/<slug>.html`
for every note, `404.html`, `sitemap.xml`, `feed.xml` (Atom), `search.json`, `robots.txt`, `assets/` (styles, fonts,
the search script), and `image/`, `file/`, `video/`, `recordings/` holding only what some page linked.

## Hosting

**GitHub Pages.** `templates/github-pages.yml` is the workflow the Back up to git plugin commits as
`.github/workflows/ghost-pages.yml`: on a push to `main` it sets up Node, runs the vendored ghost-publish with the Pages
base URL and deploys `site/` with `actions/deploy-pages`. Turn Pages on once in Settings › Pages with "GitHub Actions"
as the source. A private repository's Pages are public unless the plan says otherwise: the config's `folders` and
`private: true` are what keep a note off the web.

**Cloudflare Pages.** Connect the repository; build command `node .glyph/publish/bin/ghost-publish.mjs ./ --out site
--base https://<project>.pages.dev` (or the custom domain), build output directory `site`, no framework preset, Node 20
or newer (`NODE_VERSION=22` in the environment variables). Every push to the production branch redeploys; `404.html` is
served for missing paths as it is.

**Netlify.** New site from Git; build command `node .glyph/publish/bin/ghost-publish.mjs ./ --out site --base
https://<site>.netlify.app`, publish directory `site`; set `NODE_VERSION` to 22 in the site's environment. Netlify
serves `404.html` for a missing path on its own. Or skip the build and drag a locally built `site/` onto Netlify Drop.

**Anywhere else** (the Caddy block in scripts/deploy-landing.mjs, S3, a folder on a disk): copy `site/` as it is; there
is nothing to run.

## Installing: vendored, not published

ghost-publish is not on npm, and the recommendation is to keep it that way for now: the git plugin (docs/MARKDOWN_FIRST.md
§10) copies `publish/bin/`, `publish/dist/` and `publish/templates/` into a library's repository as `.glyph/publish/`
when "Publish as a website" is turned on, so a repository builds with the renderer that matched the app that wrote it,
with Node alone, and nothing is fetched at build time that was not committed. A library built with a newer app gets the
newer copy on its next backup. The workflow and the recipes above run that copy; the day a `ghost-publish` package is
published, the run line becomes `npx ghost-publish ./ --out site` and nothing else changes.

In this repository, `npm run publish:site -- <Library> --out site` is the same command.

## What is left

- Block anchors: `[[Note#^line]]` lands on the page, not the line (the page gives headings ids, not list items).
- Queries run with the TypeScript engine, which reads the on-disk shape of today; a merged-block ticket's `issue:` is
  handed to it as `id:` (publish/src/fences.tsx `queryText`). When the Dart engine and the TypeScript one diverge, the
  site's answer is the TypeScript one.
- Mermaid is a code block. Drawing it would mean carrying mermaid.js (about 3 MB) in every site; not worth it until asked.
- `<details>` in a note is raw text, as on the reader page (§7's proposal to teach Rendered.tsx the two tags stands).
- The home page's "recent" order falls back to file times where a note has no `updated:` key; in a CI checkout every
  file's time is the checkout's, so until `updated:` is a managed key (§11, decision 5) a fresh clone's recent list is by
  title. The tests give every fixture note an `updated:`.

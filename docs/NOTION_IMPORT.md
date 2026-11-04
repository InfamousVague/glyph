# Import from Notion

Matt, 2026-11-04: "Add functionality in the notion plugin to import a whole notion into ghost since we should have 1 to
1 functionality".

Settings › Plugins › Notion, once signed in: **Import from Notion**. It brings in every page and database Notion shares
with Ghost.md as plain Markdown files in the Library (docs/MARKDOWN_FIRST.md): a person could open the folder in any
other app and read it.

## Getting the whole Notion

Notion's OAuth shares only what the person picks on Notion's consent page. Picking the top-level pages (or every
teamspace page) shares everything under them. The section says how many pages and databases are shared ("142 pages and
6 databases shared"), and **Choose more pages** runs the sign-in again. Notion's page is where more pages are picked.

## Running it

- **Import everything** goes into a new workspace called **Notion** (`Notion 2` where that name is taken), or into the
  folder or organization picked under **Where it goes**. In Simple that choice waits behind **More**, and the import
  itself stays.
- It runs as the app's job `notion-import` (lib/core/background_jobs.dart): the ring and the tray show "142 of 380
  pages" and the page it is on, with **Stop**. On Android the foreground service keeps it going with the screen off.
  The import keeps running when the page is closed.
- At the end the page and the tray chip say what came in, what was renamed and what was left out.
- **Sync again** (once it has run) brings in new and changed pages, into the same place.

## The shape

| Notion | Ghost.md |
| --- | --- |
| A page with sub-pages | A folder, its page `<Title>/index.md`, the sub-pages inside in Notion's order (`order:`) |
| A page without | `<Title>.md` |
| A database | A folder whose `index.md` is a notebook (`book: true`): a ```` ```query ```` table of the rows, a board by its status (or first select) where it has one, and `## Rows` listing each row as `[[Row]]` |
| A row | A note in the database's folder, its properties its front matter, its page content its body |
| A database inline in a page | Its folder inside the page's folder, `[[Tasks]]` where it was on the page |
| Page icon (emoji) | `icon: 🚀` (a custom emoji `":name:"`) |
| Page cover | `banner:`, the picture downloaded into the picture store |
| Created / last edited | The note's own dates |
| Where it came from | `notion-id:`, `notion-url:`, `notion-edited:` |

Titles are made unique across the import, so each `[[link]]` opens the page it meant. The oldest page keeps the plain
title and the next is `Plans 2`.

## Blocks

| Notion block | Markdown |
| --- | --- |
| Heading 1–3 | `#`–`###`. A toggle heading is the heading with its blocks under it (a heading folds in Ghost.md) |
| Paragraph | Its words. Blocks indented under it follow it, not indented (Markdown has no indented paragraph) |
| Bulleted / numbered / to-do | `-`, `1.` counted per run, `- [ ]` / `- [x]`, nested as deep as Notion has them |
| Toggle | `<details><summary>…</summary> … </details>` (lib/editor/view/section_folds.dart draws it as a toggle) |
| Quote | `>`, its children inside |
| Callout | `> [!NOTE]` / `[!TIP]` / `[!WARNING]` / `[!CAUTION]` / `[!IMPORTANT]` by its emoji, with the emoji kept in its words |
| Code | Fenced with its language (`c++` → `cpp`, `plain text` → none; `mermaid` draws). The caption is italic under it |
| Equation | `$$ … $$` |
| Divider | `---` |
| Table | A GFM table. With no header row in Notion, an empty header row |
| Image | Notion's own: downloaded, `![caption](image/…)`. External: `![caption](https://…)`, left as its link |
| File, PDF, audio, video | Notion's own: downloaded, `[name](file/…)`. External: the bare link alone on its line (a YouTube link draws its player) |
| Bookmark, embed, link preview | The bare link alone on its line, so Ghost.md draws its card, or `[caption](url)` |
| Sub-page, sub-database, link to page | `[[Title]]` on its own line |
| Synced block | Its content (a copy reads as its original) |
| Columns | Their blocks in order, left to right |
| Table of contents, breadcrumb, template button, unsupported | Left out and named in the report |

Rich text: bold `**`, italic `*`, strikethrough `~~`, code `` ` ``, a coloured background as a highlight `==…==`
(`==…==(green)` where the kit has that colour), links `[words](url)`, a link to an imported page `[[Title]]`
(`[[Title|words]]` where the words differ), inline equations `$…$`. A soft line break is a hard break (two spaces).
Underline and coloured text have no Markdown and stay plain words. Characters that would turn into Markdown (`*`,
`` ` ``, `[[`, `==`, `~~`, and a paragraph starting `#`, `>`, `- `, `1. `) are escaped.

Mentions: a person becomes their name (no `@`), a page or database becomes `[[Title]]`, a date becomes `2026-11-04` (`→ the end`), a link becomes its link.

## Properties

Each key is in the form the queries read (tauri/docs/QUERIES.md: lower case, a space a dash, so `Due Date` is
`due-date`). A key the library or the page uses itself (`created`, `title`, `type`, `icon`…) is written as
`notion-<key>`.

| Notion | Front matter |
| --- | --- |
| Title | `title:` and the heading |
| Text | Its words with their Markdown marks, quoted where needed |
| Number, checkbox | `3`, `true` |
| Select, status | The option's name |
| Multi-select | A list written across. The first one (or one called Tags) is `tags:`, each a tag (a space becomes a dash) |
| Date | Its day. `<key>-end:` for a range's end, `<key>-at:` for the full moment where it has a time |
| Person, created by, edited by | Their names, a list |
| Relation | `["[[Row]]", …]`. A row not shared is reported |
| URL, email, phone | As written |
| Files | The files, downloaded, as a list of their links (external ones as their links) |
| Formula, rollup | The value Notion had worked out at the import, as a plain value (a rollup array as a list) |
| Unique ID | `TASK-12` |
| Created / last edited time | The note's own dates, not repeated |
| Button | Left out |

## Again, and resumable

Each note's front matter is the map from Notion to Ghost.md. A run reads `notion-id:` off every note in the library:

- A page whose `last_edited_time` equals the note's `notion-edited:` is left alone. Its blocks are not even asked for.
- A changed page is written again in place: the same note id, and wherever the person has moved it since.
- A page that has gained sub-pages becomes a folder.
- A new page is made where its parent is.
- A database's index is written again when its rows changed.
- Nothing is deleted. A page gone from Notion stays, and the report counts it.

A run that was stopped or cut short is finished by running it again. The plugin's storage key `glyph-notion-import`
keeps only where the last run went (workspace id, name, time), for **Sync again**. Because the map lives in the files,
a sync after a reinstall, or from another device, still updates rather than duplicates.

## Limits and what is not 1:1

- **Database views are not in Notion's public API.** The index guesses: a table always, plus a board when there is a
  status (or select) property. Calendar, timeline and gallery views, their filters and their sorts do not come over.
- **Comments are not imported.** They need one more request per page (the `comments` route, not on the client's
  allowed list) and a mapping to Ghost.md's comment threads. The report says they stay in Notion.
- **Rate limit.** Requests start at least 340 ms apart (under Notion's ~3 a second). A 429 waits its `Retry-After`,
  and a 5xx or a network blip backs off 1, 2, 4, 8 s, up to six tries. Every list is paged (search, database query,
  block children) and nested blocks are read as deep as they go. A sub-page's blocks are read as their own page.
- **Files** are downloaded as their page is written, since Notion's signed links expire after about an hour. The
  plugin may fetch only from `*.s3.us-west-2.amazonaws.com`, `notion.so` and `images.unsplash.com` (manifest hosts).
  External pictures stay as their links. A cover from another site, or an icon that is a picture, is left out and
  counted.
- **A changed page re-downloads its pictures.** The earlier copies remain in the picture store until the trash's sweep.
- **`last_edited_time` is to the minute**, so an edit within the same minute as an import is picked up on the
  following change.
- **A sub-page sitting in a column or toggle of an unchanged page** is placed by its own parent. If that page wasn't
  read this time, a new one goes at the top of the import.
- **Paragraph indents** flatten, and a mentioned person becomes plain words, not `@sam`.
- **No glyph-api changes.** Everything runs on the device with the existing OAuth token (client.dart `notionAnswer`,
  refreshed once on a 401).

## Code

- `lib/importer/notion/notion_source.dart`: the reader (paging, pace, back-off, downloads), `notionIdOf`,
  `notionLinkId`.
- `lib/importer/notion/notion_markdown.dart`: blocks and rich text as Markdown.
- `lib/importer/notion/notion_properties.dart`: properties as front matter, the database's queries.
- `lib/importer/notion/notion_import.dart`: the tree, titles, paths, the re-run.
- `lib/importer/import_target.dart`: `begin(named:, into:)`, `note(id:)` to update in place. `import_paths.dart`
  `placeIn`.
- `lib/plugins/notion/notion_import_job.dart`: the job on the app's record. `notion_import_section.dart`: the page's
  section.
- Tests: `test/importer/notion/` (a fake Notion), `test/plugins/notion/import_section_test.dart`.

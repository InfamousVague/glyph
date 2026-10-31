# Teamspaces: a Notion-like setup for teams, in Markdown

Matt, 2026-10-31: "Consider that now we have pretty deep notion functionality and docs functionality as well as ticket
and task management, think about how we can build better docs UIs and sidebar navigation for orgs and team members into
our app so we better are able to handle a notion like setup in teams". His choices, the same day:

| Question | Choice |
|---|---|
| Sidebar | A **space switcher** at the top (Personal, then each organization) scoping the tree; above the tree, fixed rows: Home, Search, My tickets, Triage, Updates; then sections: **Favorites**, **Teamspace** (the organization's pages) or **Private** (your own), **Shared with me**. |
| Hierarchy on disk | **Folder + `index.md`**: a page with sub-pages is a folder whose `index.md` is the page itself (Obsidian's folder-notes convention); notebooks keep their index notes and their chapters are their sub-pages. |
| Team docs open in | **A per-space setting**: each teamspace says read-first or edit-first in its Home page's front matter (`docs: read` or `docs: edit`; personal space is edit-first). |
| Build first | All four: the sidebar and page tree, the doc page UI, the teamspace home and members, presence. |

Everything stays markdown-first (docs/MARKDOWN_FIRST.md): what describes the library lives in the files, what is one
person's (favorites, folds, which space is chosen) lives in their synced settings or on the device.

## The page tree (shared model)

`lib/core/page_tree.dart` is the one model every surface reads (the sidebar, breadcrumbs, prev/next, "Pages in this
page", the publisher's sidebar if it adopts it later):

- **A page** is a note. Its **children** are, in order:
  1. if it is a folder's `index.md`: the notes and sub-folders in that folder (a sub-folder appears as its own
     `index.md` page, or as a plain folder row when it has none);
  2. if it is a notebook (an index note with chapters): its chapters, in the index's order;
  3. nothing else (no `parent:` key; the folders on disk are the hierarchy).
- **Order** within a folder: an `order:` list in the folder's `index.md` front matter (titles or file names), then
  the rest by title. Dragging writes that list; dragging into another page moves the file into that folder (making it
  a folder page first if it was a plain note: `Plan.md` becomes `Plan/index.md`, its `.versions` and sidecars moved with it, links unchanged because links are by title).
- **A page's icon** is `icon:` in its front matter (an emoji or an icon-pack name), its cover the existing `banner`.
- **Roots** per space: Personal = `Inbox/` and `workspaces/<…>/`; an organization = `orgs/<Org>/` (its `Home.md` is
  the space's home page, and the rest of the folder its tree).

### Where reality differs (2026-10-31, the model's build)

- **`index.md` does not stay `index.md` in the app's own folder.** The Rust library names a file after its title and
  renames it at every save when the library is the app's own folder (library/mod.rs `follows_title`), so
  `Plan/index.md` titled Plan is written back as `Plan/Plan.md`. The tree therefore reads a folder's page as its
  `index.md`, else the note named as the folder (`Plan/Plan.md`, the other folder-notes convention), and at an
  organization's top `Home.md` or a note saying `type: teamspace`. A folder page retitled in the own folder
  (`Plan/Roadmap.md`) is a plain folder's child until the writer side changes: `follows_title` should leave
  `index.md` and an organization's `Home.md` alone (a library change, so after every device reads both). A chosen
  folder (an Obsidian vault) keeps `index.md` already. The new organization's home template says `title: Home` so its
  file stays `Home.md`. **Writer side done 2026-10-31**: `follows_title` (library/mod.rs `is_folder_page`) leaves a
  file named `index.md` in any folder, and `orgs/<Org>/Home.md`, alone whatever they are titled; builds before it
  still rename, and the tree still reads `Plan/Plan.md` for them.
- **Pinned pages are `pins:`.** `pinned` is one of the library's own keys (a note's pin, `pinned: true`;
  front_matter.dart `libraryKeys`): with one front matter block (docs/MARKDOWN_FIRST.md §9 slice 7) the library would
  read a `pinned:` list as the pin and drop it at the next unpinned write. The settings read `pins:`, and `pinned:`
  where it is a list; the template writes neither until a page is pinned.
- **An organization's notes** are at `orgs/<folder>/[<sub>/…]`, the folder being the organization workspace's name
  cleaned (note_folders.dart `folderFor`), sub-folders being ordinary workspaces with `parent` set (GHST-107). A
  folder under `orgs/` that no organization on the device answers to is in no space (as folder_adopter.dart waits for
  it). Personal is everything else: `Inbox/`, the workspaces' folders in the workspaces' order, then a chosen vault's
  other folders and loose files. Personal's top has no page, so it has no `order:`.
- **Docs default to edit** for an organization with no `Home.md`, or one whose `docs:` says neither word; Personal is
  always edit.
- **The home's queries read the whole library**: the query grammar has no folder to read from yet.
- **A move** goes through the library's own (`apply` with a new path moves the `.versions` and `.canvas` beside the
  note; the recording's sidecar is keyed by id), then files the note in its new folder's workspace so a later folder
  rename cannot pull it back out (folder_adopter.dart `fileByFolder`). A folder is moved by the workspaces' own move,
  and nothing moves across spaces by a drag (that is filing into an organization, which shares).

## The sidebar

Built (2026-10-31): the same sidebar (lib/notes/note_tree.dart, the card the tab row's icon opens on every width)
drawn as spaces when the root hands it a `SidebarSpaces` (lib/notes/space_pages.dart; drawing in
lib/notes/note_tree_spaces.dart). The wide window's docked column is still simple mode's list (Matt, 2026-10-24) and
was left as it is.

- **Switcher** over the tools: Personal, then each organization with its hue and mark; pressed, the spaces list under
  it in place. The choice is the device's (`glyph-sidebar-space`).
- **Fixed rows**: Home (Personal's home page; an organization's own page), Search (the palette), My tickets, Triage
  (once there are tickets) and Updates (the bell's card).
- **Favorites**: note ids in the synced preferences (`favorites`, carried in `Preferences.more` as the smart notebooks
  are; lib/core/favorites.dart), those of the space shown; added from a page's … menu or the note's right-click menu.
- **Private / Teamspace**: the space's page tree, shut until unfolded (folds per device, `glyph-tree-pages-open`), each
  row its `icon:` (emoji, shortcode or a Lucide name) or the folder, notebook, canvas or page mark, the presence dot
  and the sync mark after its name. The + makes a page inside (a plain note made its folder's page first,
  `newPageIn`); the … has Open, Add to/Remove from Favorites, Rename… (in place on the row), Add a page inside, the
  folder's settings, Move to and Delete. A drag let go over a row's top or foot writes `order:`
  (`PageMover.setOrder`); over its middle it moves into it (`planMoveInto`, `PageMover.run`), a refusal said in a toast.
  Notes with no file yet are listed after Personal's pages.
- **Shared with me is not drawn**: nothing marks a note as shared to this person (a share link saves a plain copy,
  lib/share/share.dart `forkShared`); it waits for such a mark.
- **The rest**: Tags, the Market, the smart notebooks, the archive and the trash after the pages; in simple mode
  behind a More row that opens in place, with Triage. Rows are 44 tall where there is no mouse; + and … wait for the
  pointer on a desktop.

## Teamspace home

`orgs/<Org>/Home.md`: an ordinary note drawn as the space's home. Front matter carries the space's settings:

```yaml
---
type: teamspace
docs: read          # read | edit: how the space's pages open
pinned: ["[[Onboarding]]", "[[Roadmap]]"]
icon: 🏠
---
```

Its body is whatever the team writes, with query fences for recent changes and open tickets. A new organization gets one
made from a template. The dashboard screen (lib/orgs/ui/organization_screen.dart) becomes this page plus a members
strip and the settings cog.

## Members

A member's page is drawn, not stored: their tickets, the docs they own (`owner:` or verified `by:`), their recent edits
(from versions), their colour. Reached from the members strip, `@mentions` and the presence avatars.

## Follow a doc and Updates

`watchers:` (the tickets' key) works on any page; watching sends that page's changes to your Updates (the bell, as an
inbox with filters: Mentions, Tickets, Docs, Team). Auto-follow when you create, edit or are mentioned on a team page.

## Presence

Who is on a page now: avatars in the note's header and a dot beside the page's sidebar row, from the live channel the
team notes already use; nothing stored.

Built (2026-10-31): nothing new on the wire. Each organization's own room (lib/live/presence.dart) already says, sealed
under the org key, which note each member's device has open (`at`, said by lib/live/open.dart as a team note opens,
unsaid as it closes; the awareness renews every 15 s and forgets a device unheard for 30; a device whose app goes behind
another drops its socket and the relay says it left). `lib/team/presence.dart` (`PagePresence`) reads those rooms by
page, this account's own devices and the AIs left out; `lib/team/presence_avatars.dart` draws it: `PresenceAvatars`
in the bar (`AppShell.barChip`, every header version) and in simple mode's note header, `PresenceDot` and
`PresenceMarked` for sidebar rows, all reading the `PagePresenceScope` the root puts over the shell.

## The doc page

Built (2026-10-31): `lib/note/doc_page.dart`, drawn by the note's screen for a note that is a page of the tree (one in
an organization's space, or a personal note with a page above it or pages under it; a note in Inbox stays the plain
note it was). Crumbs (Space › the pages above › this page, each a way there; a phone folds the middle into …), the
`icon:` large over the title, "Edited 2 hr ago by ana · Owner: bo" under the title (a block after the title's line in
the editor, `lib/editor/items/after_title.dart`, from the last version and `owner:`), the outline beside the words from
960 wide (`LiveOutline`, quiet where there is no heading), "Pages in this page" as cards (one a row on a phone), and the
pages either side at the foot. A teamspace whose Home.md says `docs: read` opens its pages read-only and formatted, the
front matter folded away, with Edit (and Read again); the visit's choice, never stored; Personal always edits. On a
desktop Add icon and Add cover wait for the pointer over the head; on a phone and in simple mode they, the outline and
Page info are the More sheet's "This page" rows (behind More… in simple mode). The setting is written by
`withDocsMode(body, DocsMode)` in lib/core/page_tree.dart (and a page's icon by `withPageIcon`); the teamspace's
settings UI calls it over Home.md. A cover is the existing `banner:`; Remove cover writes `banner: none`.

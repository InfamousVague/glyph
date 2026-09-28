# Sharing a note or a notebook

A note or a notebook can be shared as a read-only link. Anyone with the link can read it, and nobody else can,
the server included. A reader can keep a copy: download it as Markdown, or save it into their own Ghost.md.

Matt's answers, 2026-09-22: "Anyone with the link, encrypted"; "Follows your edits"; "A small standalone page use
only components from the actual app this is more of a reader page"; and both "Download as Markdown" and "Save a
copy into their app".

## The link

    https://ghostmarkdown.com/read.html#<id>.<key>

The reader page is the release's own, served on ghostmarkdown.com as well as beside the app (docs/LANDING.md). A link
made before the move, `https://attack.fm/glyph/read.html#…`, still opens, since what opens a share is the part after
the `#`. On ghostmarkdown.com the page's "Save it in Ghost.md on the web" goes to the app on attack.fm, and "Get the
app" goes to the download page. The share service lets the page read it from there (`server/src/main.rs` `ORIGINS`).

- **The id** is 16 random bytes, base64url. The server stores the share under it.
- **The key** is 32 random bytes, base64url: the AES-GCM key the share is sealed with (`src/app/core/sync/crypto.ts`
  `sealBytes`, context `glyph/v1/share`). It sits after the `#`, which a browser never sends. The server only ever
  holds ciphertext and never sees a key.
- The link is the whole grant. Stopping a share deletes it on the server, so the link reads nothing from then on.
  A link can't be narrowed after it's sent: anyone who has it can read the share until it stops.

## What is shared

`src/app/share/share.ts` `sharedOf` builds `{ v: 1, kind, title, pages: [{ title, body }], at }`.

- **A note** is one page: its body as stored, front matter and all. A canvas note is shared the same way. One
  exception: where the note was written (`location:` and `place:`, core/geotag.ts, DESIGN §134) is left out of every
  page unless the note's "Share where it was written" is ticked on its sheet (`place: true` on the kept share). The
  opt-in is the design: a share follows every save, so a location added to a note shared last week, or one arriving
  by sync, would otherwise reach everyone holding the link, and the reader's copy and download would carry it.
  **The rule lives in the page that seals the share**, and every signed-in device follows every share: a device still
  on a page from before it (the Mac app until its next launch, a browser tab opened before the deploy, a binary too
  old to take the update) re-seals a tagged note's share with its whole body when the words change. So the pages that
  strip the tag go out, and every device is restarted or reloaded, before a shared note is tagged; a format gate on
  the share service (a newer page's version refusing an older page's write) is the lasting answer, not built yet.
- **The places written in the words** (`[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)`, the + beside the line's A
  place, core/placeRefs.ts, DESIGN §141) have a switch of their own, "Share the places in it" (`places: true` on the
  kept share), shown only when the pages hold one. Until it is ticked every `geo:` address leaves every page, however
  it is written (`withoutPlaces`): a line whose words are only places goes whole, with one blank line kept where it
  stood between two; a place inside other words keeps its words and loses its address; an autolink `<geo:…>` goes; a
  reference definition `[c]: geo:…` goes and its references keep their words. In fenced and inline code too, since
  the switch promises that none leaves. `geo:` written as plain words is words, and the tag in the front matter is the
  other switch's. A switch of its own rather than the tag's widened, because a tick given for where a note was written
  would otherwise seal every place added later, in every page of a shared notebook. The Copy the link hint says in one
  sentence what the link carries of each. The synced settings keep `places`; an older device's page drops the field
  when it rewrites the settings, which fails closed. The caveat above holds here more widely: a page from before this
  seals inline places whatever the ticks say, because it never stripped them, so every device is updated before a
  shared note gets a place. A share whose pages hold no `geo:` address is sent exactly as before, and its digest is
  unchanged.
- **A notebook** is its index first, then every page that has a note, in the index's order. A page with no note
  yet is left out, and the reader shows it as "not written yet".
- **A journal is shared an entry at a time** (DESIGN §142). A shared notebook is sent whole again a few seconds after
  any save of any of its pages, every picture read again each time, and a year of entries with photographs passes
  `SHARE_BYTES` and would lose pictures without a word. So a journal not shared says so on its More sheet, "A
  journal is shared an entry at a time. Open one to share it.", and an entry is shared as any note is, its place
  left out unless ticked. A notebook shared before it was kept as a journal goes on being shared as it was.
- **The pictures the pages show** travel in the share (`withPictures`): a reader has no account to fetch them from. A
  share with pictures is sealed as `GSP1`, four bytes giving the length of the JSON, the JSON with each picture's name
  and size, then the pictures' bytes; one without is its JSON alone, as before. Base64 inside the JSON would be
  encoded twice, since the sealed share reaches the server as base64url and the server's 6 MB limit counts that text.
  So the share holds about 4.4 MB before sealing (`SHARE_BYTES`): the pictures as kept if they fit, else each redrawn
  at 1024 px as a reading copy, else as many as fit in the order the pages show them. A picture the sharing device
  doesn't have is left out. Names are checked on opening, so a share cannot name a picture outside the store. A share
  whose words alone pass the limit is refused with a sentence saying so.
- **A film's poster** travels as one of those pictures, and the film never does: its line stays in the words, and the
  reader draws the still with "A video of 0:12. Only a still from it is shared." (`src/app/editor/videos.ts`,
  docs/DESIGN.md §141).

## Following edits

Every share is listed in the synced settings (`src/app/core/preferences.ts` `shares`): note id to share id, key, and a
digest of what was last sent, end-to-end encrypted with the rest of the settings, so every device lists every share,
keeps it up to date and can stop it. A device that kept its own list in `glyph-shares`, as builds before this did,
folds it in once. `followShares` listens for notes saved here and notes changed by sync, and, three seconds after the
last save, re-seals every share whose contents changed (a notebook's share changes when any of its pages does) and
sends it again, and does the same once a few seconds after launch. The digest is of what is sent, so ticking or
unticking "Share where it was written" or "Share the places in it" changes it, and the share goes again with or
without the location or the places. A share
never changes its link. A share also remembers which of its pictures this device lacked when it was sent (`lacked`),
and goes again once one of them is here - a picture that arrives by sync changes no page, so the digest alone would
never notice. Only those names are looked for, so a picture left out for room is not. Every share sent before this
reads as changed once (the digest's "p2"), so it goes out again with its pictures and that list.

Sharing needs an account (Settings › Account), since the server keeps a share with the account that made it.

## The server

`server/src/shares.rs`, beside sync, with its queries in `server/src/store/shares.rs`:

| Route | Who | Does |
| --- | --- | --- |
| `PUT /glyph/api/v1/shares/{id}` | the owner, signed in | stores or replaces the sealed blob |
| `DELETE /glyph/api/v1/shares/{id}` | the owner, signed in | removes it; another account's id does nothing |
| `GET /glyph/api/v1/shares/{id}` | anyone | the sealed blob, `Cache-Control: no-store` |
| `GET /glyph/api/v1/shares` | the owner, signed in | the owner's share ids, each with when it was last written (`updated`) |

| Limit | Value |
| --- | --- |
| One share | 6 MB sealed |
| Shares per account | 500 |
| Public reads per IP | 240 a minute |

The `shares` table cascades on the account, so deleting an account deletes its shares.

## The reader page

read.html is a second Vite entry (`src/read/`). It is built only from the app's own parts:

- **A note:** the note's editor, read-only, in the view a new app opens notes in (the preference's default, the
  marks dimmed on the page), with the same `grow` layout as the note screen.
- **A canvas:** the canvas, read-only, its note cards drawing the share's pages.
- **A notebook:** the app's own index (`src/app/book/BookView.tsx` with `readOnly`): the preface, numbers, canvas
  marks, "not written yet" and reading straight through. There are no grips, tools or adding. A page wears the bar
  the app gives it, stepping only between pages in the share. The banner says "A shared notebook."

Nothing on the page is drawn by code of its own, so a change to how the app draws a note or a notebook reaches it too.

It follows the system's light or dark setting. A slim banner across the top, sticky, holds the name, "Get the app"
(install.html beside it; on a phone the banner keeps only that link) and two small buttons for keeping what's shared:

- **Download as Markdown:** a note as its `.md`; a notebook, or a note with pictures, as a `.zip` of its pages with
  the pictures in an image folder beside them, where the pages' `image/<name>` links point (`src/app/share/zip.ts`,
  stored, not compressed).
- **Pictures** are drawn from the share: the page lends them to the editor as object URLs for as long as it is open
  (`src/app/core/images.ts` `lendImages`), and stores nothing, since the page shares its origin with the web app.
- **Save a copy:** on the web, a link to the app with `#fork=<id>.<key>`, which the app reads once on load
  (`src/app/shell/useForkLinks.ts`), removes from the address, and saves. In the phone or Mac app, **+ › From a shared
  link** takes the pasted link, or any text with it inside.

## A saved copy

`src/app/share/share.ts` `forkShared` saves each page as a new note owned by the reader. It does not follow the
original.

- A title that is already in the library gets "(shared)", then "(shared 2)" and so on.
- A notebook's index is rewritten to name the renamed copies, so the copy's pages are its own.
- The pictures are kept first, under their own names (`src/app/core/images.ts` `keepImage`), so the copy draws them,
  and the reader's sync sends them on with the notes that name them.

## Every share in one place

Settings › Account lists every shared note and notebook (`src/app/settings/SharedLinks.tsx`), from whichever device
shared it, with Copy and Stop. Two devices changing their settings at once can lose one's list, since the settings
sync as one blob and the later write wins. The share itself stays up, so the list also asks the server which shares
the account holds (`GET /glyph/api/v1/shares`). One no device lists, and not written for ten minutes, is counted and
can be taken down. The ten minutes are there because a share another device made just now may not have synced yet.

## Opening the app from a link

The reader page's save panel leads with "Open in the Ghost.md app": `ghostmd://fork#<id>.<key>`. The phone and Mac
apps register the scheme (tauri-plugin-deep-link, `src-tauri/tauri.conf.json`). `src-tauri/src/links.rs` keeps a link
that started or reached the app until the page asks for it (`links_take`, and the `glyph://link` event), since a link
that starts the app arrives before any page is listening. `src/app/share/appLinks.ts` saves the copy and opens it, as
the web app's `#fork=` does. An app from before this build doesn't answer the scheme, so the panel still says how to
paste the link under + › From a shared link.

# Published sites

A note or a notebook published as a small website: the same end-to-end sealed content as a shared link (docs/SHARING.md), read on the reader page as a site. The Flutter app publishes (`lib/share/sites.dart`, the rows in `lib/share/ui/site_rows.dart`, the list in `lib/settings/published_sites.dart`); the service keeps ciphertext (`server/src/sites.rs`); the reader page reads it (`tauri/src/read/Site.tsx`, `site.ts`).

## What a site is

- **What it holds** is a share's: `sharedOf` (a note, or a notebook's index and every page that has a note, in the notebook's order), with its pictures (`withPictures`, `GSP1`), sealed with `sealBytes` under a random 32-byte key made for the site alone, in its own context, **`glyph/v1/site`**, so a share's ciphertext is not a site's nor the reverse. A site never carries where a page was written, nor the places written in it.
- **Its address** is `https://ghostmarkdown.com/s/<id>#<key>`: a 128-bit id, and the key after the `#`, which a browser never sends. Each page has its own, `/s/<id>/<page>#<key>`, where `<page>` is the page's title as a slug (`slugOf`: lower case, accents off, letters and digits of any script, one `-` between; `-2` on a repeat; `page-<n>` for a title with none). The first page (the index, or the note) is the site's own address.
- **It is published by hand.** Publish and Publish again write it whole at the same id; an edit in between reaches it only then.
- **Its devices find it on the service.** Beside the sealed site the service keeps `meta`: `{ v, noteId, key, title, kind }` sealed under the ACCOUNT key with the context **`site:<id>`**. Any device of the account lists the sites with their links (`GET sites`, opened with the account key), so nothing is added to the synced settings, and a site cannot drop out of a list the way a share can.

## What the server, and the web server, see

The service sees what it sees of a share: the id, the owner, the size, when it was first and last published. It cannot open the site or its meta. The web server sees the path of an address someone opens directly, so **a page's name, its title as a slug, reaches it as written**; Caddy keeps no access log for ghostmarkdown.com. The words never reach it. The publish row says what a person must know: anyone with the link can read the site, and nobody else, the server included.

## Not indexed, and no option

The reader page carries `<meta name="robots" content="noindex, nofollow">`; Caddy adds `X-Robots-Tag: noindex, nofollow` on `/s/*`, and `GET /api/v1/sites/{id}` adds it too. An indexer could not read a site if it tried: the key is in the fragment. Allowing indexing would contradict the sealed design, so there is no setting for it.

## The reader page

`read.html` is served for every `/s/*` (Caddy `handle /s/* { rewrite * /read.html }` in `scripts/deploy-landing.mjs`; `vite preview` and the dev server do the same, `vite.config.ts` `siteAddresses`). Its assets are relative (`base: './'`), so the page writes `<base href="/">` first when its path starts with `/s/`. `main.tsx` draws `Site` for a site's path. It fetches `GET /api/v1/sites/<id>` once and goes from page to page itself (`history.pushState`), so a page's address is linkable, survives a reload, and Back works. A notebook's pages go down the side from 56rem (the Fold's inner screen) and behind **Pages** in the bar below it. `[[links]]` to pages of the site open them; others are drawn as not written. Previous and Next at a page's foot; Made with Ghost.md at the bottom. Light or dark follows the reader's system. No question of where to read, no Save a copy, no download: a site is for reading.

## Routes and limits

| | |
|---|---|
| `PUT /api/v1/sites/{id}` | `{ blob, meta }`, the owner's: published or published again; answers `{ id, updated }` (ms) |
| `DELETE /api/v1/sites/{id}` | unpublished |
| `GET /api/v1/sites` | the owner's: `{ sites: [{ id, meta, created, updated }] }` (ms) |
| `GET /api/v1/sites/{id}` | anyone: `{ blob, updated }`, `no-store`, `noindex`; 240 reads a minute per address |
| a site's blob | 6,000,000 base64url characters, as a share's |
| meta | 4,096 characters |
| sites per account | 100 |

Sites go with the account when it is deleted. Not on the iPhone yet (`publishingOffered`).

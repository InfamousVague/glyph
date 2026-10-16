# Features added for 2.1

Append-only: one section per feature agent, headed with its name.

## publish-email

### Publish a note or a notebook as a site

- **Where:** a note's or a notebook's More sheet (and the bar's Share), under **Site**, below the shared link's rows: Publish as a site, Copy the site's link, Publish again, Unpublish. Settings › Account › **Published sites** lists every site of the account with when it was last published, Copy and Unpublish.
- **What:** the shared link's sealed content (context `glyph/v1/site`), read on the reader page at `https://ghostmarkdown.com/s/<id>#<key>`, a page per address (`/s/<id>/<page-slug>#<key>`), the notebook's pages down the side in order, `[[links]]` and Previous/Next between its pages, pictures, light/dark by the system, Made with Ghost.md. Published by hand, never following saves. Its key is sealed beside it under the account key (`site:<id>`), so every device lists it. Never indexed (meta, header and API), and no option for it, since an indexer cannot read the fragment.
- **Files:** `server/src/sites.rs`, `server/src/store/sites.rs`, `server/src/sites_tests.rs`; `lib/share/sites.dart`, `lib/share/ui/site_rows.dart`, `lib/settings/published_sites.dart`; `tauri/src/read/Site.tsx`, `site.ts`, `Site.module.css`, `drawn.ts`; design in `tauri/docs/SITES.md`; guide chapter 21.
- **Not done:** a page's slug (its title) reaches the web server when someone opens that page's own address (said in SITES.md and the guide, not in the app's row). No site on the iPhone. Settings search does not find the two new cards.

### Email to a note

- **Where:** Settings › Account › **Email to a note**: Turn on an address, the address with Copy, Make a new address, Turn off. Shown only when the service takes mail. Each sync pass files what was mailed, before the notes step.
- **What:** `<16 base32 letters>@in.ghostmarkdown.com`, one an account. Mailgun posts each raw mail to `POST /api/v1/mail/inbound/mime` (HMAC of timestamp and token checked, a token taken once); the service reads it into subject, sender, Markdown body and files, seals it to the account's encryption public key (ECIES as the org-key wrap, context `inbound-mail:<id>`; the mail under that key, `mail:<id>`) and keeps only that. The device opens it with the core's existing `unwrap_with`, `seal_key_import`, `open`, writes the note with `store_apply` (Inbox, `from:` in front matter, pictures kept, other files named), and deletes the sealed copy. 30 mails an hour an address, 10 MB a mail, 200 waiting.
- **Files:** `server/src/mail.rs`, `server/src/mail/{mailgun,message,seal}.rs`, `server/src/store/mail.rs`, `server/src/mail_tests.rs`; `lib/mail/mail_in.dart`, `lib/mail/mail_note.dart`, `lib/mail/ui/mail_card.dart`; design and Matt's setup list in `tauri/docs/MAIL.md`; guide chapter 19.
- **Not done:** files that are not pictures are named, not kept (`MailPassContext.keepOther`, `notKeptLine`, is the seam for feat/files). Not on the iPhone. Nothing goes live until Mailgun, the DNS records and `GLYPH_MAILGUN_SIGNING_KEY` are set (tauri/docs/MAIL.md, "To go live").

Each section is one feature agent's, headed with its name, added to and never rewritten by another.

## clipper: the Ghost.md web clipper

**What it is.** A browser extension in `clipper/` (its own `package.json`, built with esbuild into `clipper/dist/chrome`
and `clipper/dist/firefox`, Manifest V3, one source) that saves what is on a web page into the person's Ghost.md:
Article (Readability), Selection, Full page, Bookmark (link, description, preview picture) and Screenshot (the visible
tab). The popup edits the title, adds tags, files the note in a personal workspace or a notebook, takes a comment, and
saves; a context menu item "Save selection to Ghost.md" and two shortcuts (Alt+Shift+G opens the clipper, Alt+Shift+S
saves the selection or the article straight away). `clipper/README.md` is the whole of it: modes, note format,
permissions and why each, the session ("Stay signed in"), how to build, load unpacked and test, and what each store
would need.

**Sealed in the browser.** It is a device of the account made of the web app's own code (`tauri/src/app/core`:
`derive`/`unwrap`, `call`, `seal`, the sync's `sendFile`), mirroring the connector's `GlyphAccount`. The service sees
the login half of the password and sealed blobs, as from any device; the e2e proof searches every request body for
the page's words and the password and finds neither.

**The note** is plain Markdown: front matter `source:` and `clipped:` (and `tags: [..]`, the one list form the app's
front matter rule and its queries both read), the title as the first heading, the comment, a rule, the page's words,
and pictures as `![alt](image/clip-<id>.jpg)`, stored sealed through the app's file route as the app stores a picture
(1600 px JPEG). A picture that cannot be stored stays a link.

**In the app.** `lib/editor/media/source_line.dart` (new) draws a note's `source:` as one quiet line under its title,
"From field.example/art…tml" (shortened as every address is), whose tap opens the page; the front matter itself stays
folded to "source · clipped · tags". Hooked by one line in `lib/root/note_desk.dart`'s editor extensions. Tests:
`test/clipper/source_line_test.dart`, and `test/clipper/clipped_note_test.dart`, which opens two notes the clipper's
end-to-end run saved (an article with two pictures; a page of tables, code and to-dos) in the app put together and
draws them, phone size and the Fold's inner size.

**Not done.** No store listing or publishing (Chrome Web Store, Edge, AMO, Safari: `clipper/README.md` says what each
needs; Safari needs an Xcode wrapper app). Not offered: an organization's workspace (a team's notes go through the
team's channel, `mcp/team.ts`, which the clipper does not carry) and journals (their pages are named by the minute).
Not verified: Firefox (built, never loaded), a real toolbar click and the real context menu and shortcut keys (the
proof presses the button through Chrome's DevTools command `Extensions.triggerAction`, which grants the same
`activeTab`, and calls the menu's and shortcut's handler directly), real sites (only fixture pages), and the phone
receiving a clip through sync (proven against a local glyph-api and through the connector's and the web app's sync
code, not on the Fold).

**Found beside, not the clipper's:** on a home of two cards across (the Fold opened, 669 and 900 wide), a note card
whose picture is drawn fails its row's layout: `lib/home/note_card.dart` `CardRow` asks for the intrinsic height of a
card holding a `LayoutBuilder` ("LayoutBuilder does not support returning intrinsic dimensions"). Any note with a
picture does it, clipped or not; a phone-width home (one card a row) does not.

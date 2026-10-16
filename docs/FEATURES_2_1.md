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

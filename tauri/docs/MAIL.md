# Email to a note

Each account may turn on a private address. Mail sent to it becomes a note in the person's Inbox. Settings › Meetings › Email to a note (Flutter: `lib/mail/ui/mail_card.dart`; the address itself is shown on the Invite Ghost card, `lib/meet/ui/meet_card.dart`); the service's side is `server/src/mail.rs`.

## What the service sees, and keeps

This is the one design where the service reads a person's words in the clear, and the setting says so in its footer. A mail arrives from the mail provider as plain MIME, as it does at any mail server. In the same request the service:

1. checks the provider's signature, the address and the limits, before it reads a word;
2. reads the mail into a note's words (`server/src/mail/message.rs`): subject, sender, date, the body as Markdown, the files;
3. seals that to the account's encryption PUBLIC key (`server/src/mail/seal.rs`, below);
4. stores only the sealed copy (`mail_in`), wipes the buffers that held the clear copy, and answers.

The clear copy is never written to disk or to a log. The sealed copy waits until a device of the account syncs; that device opens it with the account's private key, which never leaves the account's devices, files the note through the normal door (`store_apply`), and deletes the sealed copy. `server/src/mail_tests.rs` `not_a_word_of_a_mail_reaches_the_service_s_files` reads the database's files on disk and finds no word of a mail in them.

## The address

A made address is a readable name, `sneaky_siren33@in.ghostmarkdown.com` (GHST-109, `server/src/mail/names.rs`): an adjective, an underscore, a ghostly noun and two digits, about 2.3 million of them. Addresses made before 2026-10-23 were `<16 letters and digits>`, RFC 4648's lower-case base32 alphabet, eighty random bits; those still take mail. Or a name of the person's own, `matt@in.ghostmarkdown.com` (below). One address an account, kept as its local part, lower-cased, in the clear (the service must find the account a mail is for, as it finds one by its handle), and found however a mail program cases it. **Make a new address** puts a new one in place of the old in one transaction; the old one is dead at once. A `+tag` after the local part is ignored, so `x+receipts@…` reaches `x@…`.

**An address given up is never anyone else's.** Since 2026-10-24 every address that leaves `mail_addresses` - replaced by a made one or a chosen one, turned off, or gone with a deleted account - is kept in `mail_addresses_retired` by a trigger on the table (`server/src/store.rs`), so no door forgets to. It is kept against the account it was: that account may take it back; no other account may ever have it, so a contact or a Calendar invite that still has it is refused with a bounce rather than read by a stranger. `account_id` there has no foreign key, so the row outlives a deleted account, whose id `AUTOINCREMENT` never hands out again: a deleted account's addresses stay, as their local parts linked to nothing left, and are nobody's for good. That is the one thing about a deleted account the service keeps. Addresses replaced before 2026-10-24 were not kept; that is why a chosen name may not have the shape of a made one.

### A name of one's own

Matt, 2026-10-24: "i'd like you to add the ability to create our own custom name for the email if the name is available like matt@in.ghostmarkdown.com". Settings › Meetings › Invite Ghost › **Choose a name…** (`lib/meet/ui/meet_card.dart`, `lib/mail/mail_name.dart`).

A name is trimmed and lower-cased, then must be (`names.rs` `chosen`; the app checks the same before it asks):

| | reason | the words |
|---|---|---|
| a to z, 0 to 9, `.`, `-`, `_` only | `characters` | Only letters, numbers, dots, dashes and underscores. |
| at least 3 | `short` | At least 3 characters. |
| at most 30 | `long` | At most 30 characters. |
| a separator only between letters or digits, one at a time | `separators` | A dot, dash or underscore goes between letters or numbers, one at a time. |
| not the shape of a made one: 16 of the base32 alphabet, or `<adjective>_<noun><nn>` from the lists | `generated` | That looks like a name Ghost.md makes up. Choose one of your own. |
| not reserved, compared with its separators taken out (`no-reply` is `noreply`): postmaster, abuse, admin, root, hostmaster, webmaster, security, support, noreply, mailer-daemon, help, info, ghost, ghostmd, glyph, mail, calendar, meet, team, staff, billing and the rest of `RESERVED` | `reserved` | That name is reserved. |
| nobody's, live or given up, but the account's own | `taken` | That name is taken. |

The look and the claim are one transaction on the store's one connection, and the address is the live table's key, so two accounts asking for `matt` at once cannot both have it (`mail_tests.rs` `two_accounts_asking_for_one_name_at_once_one_has_it` races eight threads). Choosing a name turns the old address off exactly as a new one does.

Asking whether a name is free is an answer about everyone's addresses, so asking and choosing are counted together: sixty an hour an account and a hundred and twenty an hour a client address (`NAMES_PER_HOUR`, `guard.rs`), enough to try names as one types and too few to walk the namespace. The name is posted in the body, not put in the query, so it stays out of the proxy's access log. (Writing this found the hourly buckets were forgotten after ten idle minutes and came back full; `guard.rs` now keeps a bucket until it has filled.)

**The trade-off, said plainly:** a chosen name is a guessable one. Anyone can try mailing `matt@in.ghostmarkdown.com`, as anyone can try `matt@` any domain, where a made name has to be guessed out of millions. What reaches it is still sealed to the account the moment it arrives, the address still takes thirty mails an hour, and a person who starts getting mail they did not want makes a new address in its place (the old one bounces from then on).

Why a random local part on a subdomain, rather than plus-addresses on one mailbox: one catch-all route on a subdomain of its own is the cheapest thing a provider sells, its MX records touch nothing else of ghostmarkdown.com (any mail Matt has on the root is untouched), and a revoked address is gone outright rather than living on as a plus-tag a provider might still route.

## The provider: Mailgun

ghostmarkdown.com's DNS is at Gandi, so the provider must work with MX records added there. Mailgun does (Cloudflare Email Routing would need the domain's nameservers moved to Cloudflare). Its free plan has one inbound route and 100 mails a day across the service; Basic is $15 a month for more. One route does it all:

```
match_recipient(".*@in.ghostmarkdown.com")  →  forward("https://ghostmarkdown.com/api/v1/mail/inbound/mime")
```

A forward URL ending in `mime` posts the raw mail, `application/x-www-form-urlencoded`, with `recipient`, `body-mime`, `timestamp`, `token` and `signature`. The signature is the hex HMAC-SHA-256 of `timestamp` then `token`, keyed with the account's HTTP webhook signing key (`server/src/mail/mailgun.rs`). The service takes a timestamp up to nine hours from now (Mailgun retries for eight), and a token once.

The provider-specific part is that one file. Another provider that posts raw MIME under an HMAC would be a file beside it.

| The service answers | Mailgun does |
|---|---|
| 200 | Kept. |
| 406 | Refused for good, and the sender gets a bounce: no such address, too large, unreadable, a mailbox with two hundred waiting, a post seen before. |
| 429 | Tries again later: the address has had thirty this hour. |
| 401 | Not Mailgun's signature. |
| 503 | Tries again later: the service has no signing key, or could not keep it just now. |

## The seal

Two layers, the same two an organization's notes have (docs/SHARED.md, S2 and S3):

1. **A key wrapped to the account.** A fresh 32-byte key for this one mail, wrapped to the account's encryption public key by ECIES exactly as an organization key is wrapped to a member (`core/orgs/wrap.ts` `wrapFor`, `native/src/crypto.rs` `wrap_for`): an ephemeral P-256 pair, ECDH with the account's point, HKDF-SHA-256 with no salt and the info `glyph/v1/org-key:<context>`, AES-256-GCM with the context as associated data. The wrap is the ephemeral point (65 bytes), the IV (12) and the ciphertext, base64url. **The context is `inbound-mail:<mail id>`**, new for this: no organization's wrap (`org-key:…`) opens as a mail's, and a wrap moved onto another mail opens nothing.
2. **The mail under that key**, as `sealBytes` seals everything synced: a version byte (1), a fresh 12-byte IV, AES-256-GCM, with **`mail:<mail id>`** as associated data.

A device opens it with commands the core already has: `unwrap_with` (the pair, the wrap, `inbound-mail:<id>`), `seal_key_import`, `open` (`mail:<id>`). Nothing new in the core. `test/mail/sealed_mail_test.dart` opens a mail the service's own code sealed (`test/mail/fixtures/sealed_mail.json`, written by `mail_tests.rs` `the_sealed_mail_the_app_opens` when `GLYPH_MAIL_FIXTURE` names the file) through the real core, and no other key opens it.

## What is sealed: `GML1`

Four magic bytes `GML1`, the head's length as four bytes big-endian, the head as JSON, then each file's bytes in the order the head lists them (the share's `GSP1`, for mail):

```json
{ "v": 1, "subject": "Café plans", "from": "Sam Lee <sam@example.com>", "to": "…@in.ghostmarkdown.com",
  "date": 1792159500000, "body": "Markdown", "files": [{ "name": "door.png", "type": "image/png", "size": 8, "cid": "pic1@x" }] }
```

The body is the HTML part as Markdown (htmd) when there is one, else the plain part. A picture the HTML shows from the mail itself (`cid:`) stays as `![…](cid:…)`, and the device points it at the picture it keeps. A picture from the web is left out (in a note it would be fetched each time the note is drawn, and a tracking pixel would learn when you read it); a link that runs a script becomes `#`. A body past 900 KB is cut, and says so.

## The note

```markdown
---
from: "Sam Lee <sam@example.com>"
---
# Café plans

The body, with each inline picture in its place.

![door.png](image/<uuid>.png)

Came with it, not kept: menu.pdf (9 bytes).
```

Its id is a UUID made from the mail's id (`lib/mail/mail_note.dart` `mailNoteId`), and so are its pictures' names, so a pass cut short, or two devices at once, file one note. It has no folder, so it lands in `Inbox/`; it is dated when the mail was sent. JPEG, PNG, GIF and WebP are kept as pictures. Any other file goes through `MailFileKeeper` (`notKeptLine` today): it is named and not kept. When general attachments land, `MailPassContext.keepOther` is the one place to point at their store.

## Limits

| | |
|---|---|
| a mail, raw | 10 MB |
| the provider's post | 32 MB |
| mails an address takes | 30 an hour |
| mails waiting for an account's devices | 200 |
| files in one mail | 40 |

## Routes

| | |
|---|---|
| `GET /api/v1/mail/address` | `{ address, available }`; `available` is false when the service has no signing key |
| `POST /api/v1/mail/address` | a new address in place of any old one; 409 without the account's encryption key, 503 when not available |
| `PUT /api/v1/mail/address` | `{ name }`: that name in place of any old one, `{ address }`; 400 `{ error, reason }` for a name nobody may have, 409 `{ error, reason: "taken" }`, 429 past the hour's names, and `POST`'s 409 and 503 |
| `POST /api/v1/mail/address/available` | `{ name }` → `{ name, available, reason, message }`: `name` as it would be kept, `reason` a code from the table above or `yours`, both null when free; 429 past the hour's names |
| `DELETE /api/v1/mail/address` | off |
| `GET /api/v1/mail` | `{ mail: [{ id, size, at }] }`, oldest first |
| `GET /api/v1/mail/{id}` | `{ id, wrapped, blob, at }` |
| `DELETE /api/v1/mail/{id}` | taken |
| `POST /api/v1/mail/inbound/mime` | Mailgun's post |

**A calendar invite to the address also books Ghost into its meeting.** Added as a guest on a Google Calendar event, the address gets Google's invitation like any guest; the mail becomes a note as above, and in the same request the service reads the invite's calendar part and books Ghost to join its Google Meet, moves it when the event moves and calls it off when it is cancelled (`server/src/meet.rs`, `docs/MEET.md`).

The device's step runs in every sync pass, before the notes (`lib/sync/engine.dart` `mailIn`), and is quiet against a service with no mail routes. It is not offered on the iPhone yet (`publishingOffered`).

## To go live (Matt)

1. Put Mailgun's HTTP webhook signing key (Mailgun › Settings › API Security) in `tauri/.env` as `GLYPH_MAILGUN_SIGNING_KEY=…`, and deploy glyph-api (`node scripts/deploy-server.mjs`), which writes it into the box's `/opt/glyph-api/glyph-api.env` with the token. That script rewrites the env file on every run, so a key added there by hand would be lost at the next deploy. Without the key the service takes no mail and the app does not offer an address.
2. In Mailgun, add the domain `in.ghostmarkdown.com`.
3. At Gandi, on ghostmarkdown.com, the records Mailgun shows for it: two MX records on `in` (for the US region `mxa.mailgun.org.` and `mxb.mailgun.org.`, priority 10; the EU region names its own), and the TXT records for its verification. Nothing on the root domain changes.
4. In Mailgun › Receiving, one route: expression `match_recipient(".*@in.ghostmarkdown.com")`, action `forward("https://ghostmarkdown.com/api/v1/mail/inbound/mime")`, and `stop()`.
5. Send a test from Mailgun's route page, or a real mail to an address made in the app.

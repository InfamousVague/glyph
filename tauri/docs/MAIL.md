# Email to a note

Each account may turn on a private address. Mail sent to it becomes a note in the person's Inbox. Settings › Account › Email to a note (Flutter: `lib/mail/ui/mail_card.dart`); the service's side is `server/src/mail.rs`.

## What the service sees, and keeps

This is the one design where the service reads a person's words in the clear, and the setting says so in its footer. A mail arrives from the mail provider as plain MIME, as it does at any mail server. In the same request the service:

1. checks the provider's signature, the address and the limits, before it reads a word;
2. reads the mail into a note's words (`server/src/mail/message.rs`): subject, sender, date, the body as Markdown, the files;
3. seals that to the account's encryption PUBLIC key (`server/src/mail/seal.rs`, below);
4. stores only the sealed copy (`mail_in`), wipes the buffers that held the clear copy, and answers.

The clear copy is never written to disk or to a log. The sealed copy waits until a device of the account syncs; that device opens it with the account's private key, which never leaves the account's devices, files the note through the normal door (`store_apply`), and deletes the sealed copy. `server/src/mail_tests.rs` `not_a_word_of_a_mail_reaches_the_service_s_files` reads the database's files on disk and finds no word of a mail in them.

## The address

`<16 letters and digits>@in.ghostmarkdown.com`: RFC 4648's lower-case base32 alphabet, so eighty random bits, and nobody finds one by guessing. One address an account, kept as its local part in the clear (the service must find the account a mail is for, as it finds one by its handle). **Make a new address** puts a new one in place of the old in one transaction; the old one is dead at once. A `+tag` after the local part is ignored, so `x+receipts@…` reaches `x@…`.

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
| `DELETE /api/v1/mail/address` | off |
| `GET /api/v1/mail` | `{ mail: [{ id, size, at }] }`, oldest first |
| `GET /api/v1/mail/{id}` | `{ id, wrapped, blob, at }` |
| `DELETE /api/v1/mail/{id}` | taken |
| `POST /api/v1/mail/inbound/mime` | Mailgun's post |

The device's step runs in every sync pass, before the notes (`lib/sync/engine.dart` `mailIn`), and is quiet against a service with no mail routes. It is not offered on the iPhone yet (`publishingOffered`).

## To go live (Matt)

1. Deploy glyph-api with `GLYPH_MAILGUN_SIGNING_KEY` set in its env file (Mailgun › Settings › API Security › HTTP webhook signing key). Without it the service takes no mail and the setting does not show.
2. In Mailgun, add the domain `in.ghostmarkdown.com`.
3. At Gandi, on ghostmarkdown.com, the records Mailgun shows for it: two MX records on `in` (for the US region `mxa.mailgun.org.` and `mxb.mailgun.org.`, priority 10; the EU region names its own), and the TXT records for its verification. Nothing on the root domain changes.
4. In Mailgun › Receiving, one route: expression `match_recipient(".*@in.ghostmarkdown.com")`, action `forward("https://ghostmarkdown.com/api/v1/mail/inbound/mime")`, and `stop()`.
5. Send a test from Mailgun's route page, or a real mail to an address made in the app.

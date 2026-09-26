# Sync and the end-to-end keys

_How a password becomes two keys, how every device seals what it sends, and how a sync pass keeps notes the same without the server reading a word._

## One password, two halves

`src/app/core/sync/crypto.ts` uses WebCrypto only, so the phone, the Mac, the browser and the Claude connector run the same code. A password never leaves the device as itself.

| Step | What happens |
|---|---|
| Stretch | PBKDF2-SHA-256, 600,000 rounds (`ROUNDS`), over the password |
| Salt | `glyph/v1/<handle>`, with the handle trimmed and lower-cased |
| Output | 64 bytes |
| First 32 bytes | the login secret, sent as 64 hex characters in place of the password; the server keeps its Argon2 hash (`server/src/accounts/credentials.rs`) |
| Last 32 bytes | the wrap key, an AES-GCM key that never leaves the device |

## The account key

Sign-up makes a 32-byte AES-256-GCM account key on the device, and everything synced is sealed under it. `sealBytes` writes a version byte (`1`), a fresh 12-byte IV and the ciphertext. It binds what the item is as associated data, so a blob moved onto another item will not open.

| What is sealed | Its associated data |
|---|---|
| a note | `note:<id>` |
| a recording or a picture | `file:<its id>` |
| the synced settings | `prefs` |
| a live typing message | `live:<note id>` |
| a shared note or book, under the share's own key | `glyph/v1/share` |
| the account key itself, when wrapped | `account-key` |

glyph-api holds the account key only in wrapped form: once under the password's wrap key, and once under each of eight recovery codes. A code looks like `XXXX-XXXX-XXXX`. Its letters come from a 32-character alphabet with no 0, O, 1 or I, which gives sixty bits. Dashes and case are taken out, then the code is split into two halves the same way, salted with `glyph/v1/recovery/<handle>`. The server keeps the SHA-256 of each code's login half. The code itself only ever appears on the person's screen, once.

On a device, the account key is a non-extractable CryptoKey in IndexedDB (`src/app/core/account/keystore.ts`, database `glyph-account`): a page script can use it but never read its bytes. The device's own signing key is kept beside it. The session token lives in `localStorage` as `glyph-account-session`. A browser with no IndexedDB keeps the keys in memory, for as long as the page is open.

## Ways in, and staying in

`src/app/core/account/account.ts` holds the flows. `api.ts` is the page's one way to call the service, at `https://attack.fm/glyph/api/v1/`.

- **Sign-up** sends the handle, the login half, the wrapped key, eight recovery entries and this device's public key. The server refuses an account without a whole recovery sheet, because end to end it is the only way back in.
- **Password.** `POST login` answers with a token and the wrapped key, which is unwrapped on the device.
- **Recovery code.** `POST login/recovery` spends the code and answers with the key wrapped under it. The app then sets a new password and makes a fresh sheet.
- **Device key.** Every device the app runs on registers an Ed25519 key of its own, which can never be exported. At launch, `resume` tries `POST refresh`. If the token has lapsed, it asks `login/challenge` for a nonce (24 random bytes, good for two minutes and spent by one attempt) and signs it for `login/device`. Offline, it stays signed in as it was. Only when neither way works is the device signed out, keys and all.

The token is `glyph1.<claims>.<signature>`: the claims as base64url JSON, signed with Ed25519 by a key the server makes on first start (`server/src/identity.rs`). It lasts seven days. There is no algorithm field in it for anyone to choose.

Changing the password re-wraps the key, and the notes are untouched. Signing out takes the session and both keys off the device, and the notes stay.

## A pass

`src/app/core/sync/notes.ts` runs a pass in three steps. Per account, a device keeps a cursor into the feed. Per note, it keeps the revision it last saw and a fingerprint of the note at that time (`mark`): its body, times, source, pin, archive, recording length, formatted hash and model, and path.

1. **Pull.** `GET notes?since=<cursor>` pages through every note written since the cursor. A revision this device has already recorded is its own write coming back. A note unchanged here takes the other device's version, through `store_apply`. A note changed on both sides whose words differ is kept twice. This device's words become a new note with a new id and no recording, and the other device's version keeps the id. A pin, an archive or a folder changed on both sides takes theirs. A deletion removes a note only if the note was not changed here. A note that was changed here stays, and is sent again.
2. **Push.** Every note whose fingerprint moved is sealed and sent with `PUT notes/<id>`, from the revision last seen (`base`). A new note with no words and nothing set waits until it has some. A note that was recorded before and is now gone from this device is sent as a `DELETE`. If the server refuses a write, the refusal is a 409 carrying the note that won. The winner is merged just as a pulled note is, and the write is tried once more.
3. **Settle the pictures** (`settlePictures`). Every picture a note on this device names is made whole on both sides. The device asks the account with a `HEAD` before it sends a picture the account may already hold, and asks again for a missing picture at most every four minutes.

Recordings travel by hash (the first 16 bytes of SHA-256) under the id `r-<note id>`, and are sent again when the hash changes. Pictures travel by name, which is never reused, under `i-<ext>-<stem>`. Both go as sealed files on the same `recordings/` route. A note that is live with another device is left out of both the pull and the push (`core/live/shared.ts`).

## Settings, as one blob

`src/app/core/sync/prefs.ts` seals the settings that describe the person as one object under `prefs`, written from the revision last read. A device that changed nothing, or has never synced, takes the account's settings. A device that changed its settings sends them, and on a 409 reads once more. The list (`SYNCED_PREFS`) holds the theme, density, text size and both typefaces, the typing aids, recording behaviour (better words, stop when quiet, the command word), the review, code colours, the note view, animations, link previews, the open tabs and tab groups, the workspaces, the trash and the shares. Which model formats notes, Local only, the accent colour, the rounding of corners, the interface size and the sidebar's style stay on the device.

## When a pass runs

`src/app/core/sync/engine.ts` runs a pass when the app starts signed in (after the session is renewed), when the app comes back to the front, four seconds after the last change to a note or a setting, and every five minutes. One pass runs at a time, and a request made while one is running queues exactly one more. No pass runs without the account key, or while Local only (Settings › Formatting) is on. The native side needs generation 16 (`SYNC_GENERATION`), which brought `store_apply` and `sync_put_file`. On an older binary the Account page says "Sync needs the newest Ghost.md. Install it from attack.fm/glyph."

## The server's side

`server/src/sync.rs` checks sizes and shapes, never content.

| Limit | Value |
|---|---|
| a note's sealed blob | 1.4 MB of base64 (1,400,000 characters) |
| the settings blob | 350 KB (350,000 characters) |
| a recording or a picture | 64 MB |
| one page of the feed | 500 notes |
| an id | 1 to 64 base64url characters |
| signing in | 20 attempts a minute per address, and 10 per handle |

Each account has one counter, bumped by every write of a note, the settings or a file, and it is the feed's cursor. A note the server has never seen is accepted whatever its base. The sign-in limit covers sign-up, every way in, the device challenge, and deleting the account.

## Shares: the same seal under another key

A shared note or book (`src/app/share/share.ts`) is sealed with the same `sealBytes`. It uses a random 32-byte key made for that share alone, with `glyph/v1/share` as associated data. The link is `https://ghostmarkdown.com/read.html#<id>.<key>`: a 16-byte id, then the key after the `#`, which a browser never sends. The server (`server/src/shares.rs`) holds ciphertext it cannot open.

A book is shared as its index and every chapter that has a note. Pictures ride inside the share, because a reader has no account to fetch them from. The `GSP1` layout is four magic bytes, then four bytes of length, then the JSON with each picture's name and size, then the pictures' bytes. The budget before sealing is 4.4 MB (`SHARE_BYTES`), which keeps the sealed share's base64url under the server's 6 MB (`SHARE_LIMIT`, 6,000,000 characters). Pictures that do not fit as they are kept are redrawn at 1024 pixels, and then as many as fit are taken. The synced settings list every share with its key, so any device can follow edits (three seconds after a save) and stop a share.

`read.html` is a second Vite entry (`src/read/Reader.tsx`). It is built from the app's own editor, canvas and book views, all read-only, and it sends no referrer and asks not to be indexed. Save a copy forks the share (`forkShared`): each page becomes the reader's own note, and a title already in their library gets "(shared)".

## What the server can see

The server can see handles, when each account was made and last signed in, and device public keys with their labels (Android, iPhone, Mac, Windows, Web, or Claude). It can see note ids, how many notes there are and how big, when each was written, and which were deleted, and the same for files and shares. glyph-api counts the address a sign-in came from in memory, for the rate limit, and keeps it nowhere. It never sees a title, a folder name, a word, a setting or a second of audio.

The one exception is the hosted Claude connector, which runs on the same machine beside glyph-api. For a person who connects Claude through it, it holds that account's key in memory for as long as the connection lasts, and it opens their notes ([[The Claude connector, inside]]). The connector a person runs on their own computer keeps the key there.

## Proving it

`src/app/core/sync/sync.e2e.test.ts` runs two devices and one account against a real glyph-api. It covers signing up and signing in with one key, a note with a recording and a picture, both kinds of conflict, a race, settings, a password change, recovery, and deleting the account. One test reads the server's database files and checks that no word of a note is in them. The file runs only when `GLYPH_SYNC_E2E` names the server's data folder, and it needs `VITE_GLYPH_API` pointed at that server running locally. `crypto.test.ts`, `notes.test.ts`, `prefs.test.ts` and `pictures.test.ts` run on every test run, and `server/src/sync_tests.rs` covers the server's side.

## Where SYNC.md is wrong

- Its wire list leaves out `DELETE account`, which takes the login half and answers `{ deleted: true }`. It also leaves out the `HEAD` on a file, which only its prose mentions.
- It says `POST device`, `PUT password` and `POST recovery` answer `{}`. They answer `{ ok: true }`, `{ ok: true }` and `{ left: 8 }`.
- It says the settings that travel are the look, the type, recording behaviour, code colours, the view and animations. The typing aids, the review, the tabs, tab groups, workspaces, trash, shares and link previews travel too. The accent colour, the rounding, the interface size and the sidebar's style do not.
- It calls the switch that stops sync "Nothing leaves the phone", as `engine.ts`'s comments do. In Settings it is Local only, under Formatting.
- It says a conflict copy's file "gets a number, `Title 2.md`". The copy is applied with no path, so it lands in `Inbox/`, and gets a number only if that title is already taken there.

## Read next

- [[Live typing over a relay]]
- [[glyph-api, the server]]
- [[Accounts, sync and the key you hold]]

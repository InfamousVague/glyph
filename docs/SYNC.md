# Accounts and sync

Ghost.md accounts, and notes, settings, recordings and pictures kept the same on every device, **end-to-end
encrypted**: the server holds copies it cannot read. Matt's brief (2026-09-16): "make a tauri/desktop version and add
account signup to keep notes in sync across devices, copy the mechanisms on attack.fm". His choices: an account of its
own (not the attack.fm one), end-to-end encryption, and notes + settings + recordings from the start. Served from
`attack.fm/glyph/api` for now. The page takes the address from one build setting, `VITE_GLYPH_API`, for accounts,
sync, shares and the live relay; Notion's sign-in and Claude's MCP server name it on their own (README, "Moving to
another domain").

## What is copied from AttackFM, and what is not

AttackFM's registry (`AttackFM/server/crates/registry`, `crates/identity`) is the model:

| Piece | AttackFM | Ghost.md |
| --- | --- | --- |
| Identity | handle + password, and/or a device key; 8 recovery codes | the same |
| Token | `afm1.<claims>.<sig>`, Ed25519, 7 days, `POST /v1/refresh` | the same shape, tagged `glyph1` |
| Signing key | generated on first boot, kept in the database's `meta` | the same |
| Server | Rust, axum, rusqlite, argon2, behind Caddy on loopback | added to `glyph-api`, which already runs there |
| Settings sync | one JSON blob with a `rev`; a stale `rev` gets 409 and the current blob | the same, the blob encrypted |
| Library sync | a `rev` change feed with deletion markers, server-written | the same feed, but every device writes: a push carries the `rev` it was based on |
| Rate limits | none on login | **added**: per address and per handle |
| Encryption | none | **end to end**, below |

Not copied: AttackFM's friends, invites, shares and presence, its pairing codes, and the review-box backdoor.
Ghost.md has shared links of its own, a different thing under the same word (docs/SHARING.md), and live typing
(docs/LIVE.md).

## Keys

Nothing the server stores can be read without a key it never sees.

- **The account key (AK).** 32 random bytes, made on the device that signs up. Every note, setting and recording is
  encrypted with it: AES-256-GCM, a fresh 12-byte IV per write, the item's id and kind as associated data (so a
  blob cannot be swapped onto another item).
- **The password never leaves the device as itself.** PBKDF2-SHA-256, 600 000 rounds, salt `glyph/v1/<handle
  lower-cased>`, 64 bytes out: the first 32 are the **login secret** (sent in place of the password, and Argon2-hashed
  by the server exactly as AttackFM hashes a password), the last 32 the **password wrap key**, which never leaves.
- **AK is stored on the server only wrapped:** once under the password wrap key, and once under each recovery code.
  A code is split the same way (the same PBKDF2, salt `glyph/v1/recovery/<handle lower-cased>`, the code upper-cased
  with its dashes taken out): the login half is what the server keeps (as SHA-256) to know the code, the wrap half
  unwraps that code's copy of AK. Wrapping is AES-256-GCM, with `account-key` as associated data. Codes are made on
  the device and never sent.
- **On a device, AK is kept as a non-extractable WebCrypto key** in IndexedDB. A signed-in device never asks for the
  password again; device-key sign-in (Ed25519, as AttackFM) renews the session without it.
- **A new device** gets AK by signing in with the password (unwrap), or with a recovery code (unwrap, then set a new
  password, which re-wraps).
- **Changing the password** re-wraps AK under the new wrap key; nothing else changes.
- **What is lost when everything is lost:** forget the password, lose every device, and lose every recovery code,
  and the notes on the server can never be read again. The sign-up screen says so, and shows the recovery codes once.

What the server can see: the handle, when things change, how many notes and how big, and note ids (random UUIDs).
Not titles, not folders, not a word of any note, not settings, not a second of audio.

## The wire

All under `/glyph/api/v1/`, bearer token where signed in, JSON unless said. `login` values are 64 hex characters;
`wrapped` values and blobs are base64url.

```
GET  pubkey                                                              -> { alg, publicKey }
POST signup          { handle, loginSecret?, wrapped?, devicePublicKey?, deviceLabel?, recovery: [8 × { login, wrapped }] }
                                                                         -> { token, account }
POST login           { handle, loginSecret }                             -> { token, account, wrapped }
POST login/challenge { handle }                                          -> { nonce }
POST login/device    { handle, nonce, signature }                        -> { token, account }
POST login/recovery  { handle, login }                                   -> { token, account, wrapped }   (the code is spent)
POST refresh                                                             -> { token, account }
POST device          { devicePublicKey, label }                          -> { ok: true }
GET  keys                                                                -> { wrapped }
PUT  password        { loginSecret, wrapped }                            -> { ok: true }
GET  recovery                                                            -> { left }
POST recovery        { codes: [8 × { login, wrapped }] }                 -> { left }   (replaces the sheet)
DELETE account       { loginSecret }                                     -> { deleted: true } | 403 (not the password)

GET    notes?since=<rev>&limit=                                          -> { rev, items: [{ id, rev, deleted, blob }], more }
PUT    notes/<id>    { base, blob }                                      -> { rev } | 409 { id, rev, deleted, blob }
DELETE notes/<id>    { base }                                            -> { rev } | 409 { id, rev, deleted, blob }

GET  prefs                                                               -> { rev, blob }   (rev 0, blob null: never written)
PUT  prefs           { base, blob }                                      -> { rev } | 409 { rev, blob }

PUT  recordings/<id>?base=<rev>   octet-stream                           -> { rev } | 409 { rev }
GET  recordings/<id>              octet-stream, the rev in x-glyph-rev
HEAD recordings/<id>              the same headers, no body
```

Deleting the account deletes everything the service keeps for it: its notes, settings, recordings and pictures, its
shared links, its devices and its recovery codes (Settings › Account › Delete account, or the page
`landing/delete-account.html`). The same `/glyph/api/v1/` holds the shared links (`shares`, docs/SHARING.md) and the
live relay (`live`, docs/LIVE.md).

The HEAD has no route of its own: axum answers it through the GET, which reads the whole file to send only its
headers. The client asks it of every picture a pass settles.

One `rev` counter per account, bumped by every write, is the feed's cursor. A note's own `rev` is the counter at its
last write, and a push names the `rev` it was made from (`base`); a push whose base is not the note's current `rev`
lost a race and gets the winner back. A note the server has never seen is accepted whatever the base.

The `recordings` route holds every synced file, by an id the client makes: `r-<note id>` for a note's recording (WAV),
`i-<ext>-<stem>` for a picture `<stem>.<ext>`.

What is sealed, and under which associated data: a note as `{ v: 1, note, recording?, images? }` under `note:<id>`
(`recording` is a hash of the WAV, `images` the picture names the body uses); the synced settings under `prefs`; a
file under `file:<its id>`.

Limits: a note blob 1.4 MB and prefs 350 KB (as base64), a file 64 MB, 500 notes a page; sign-in 20 attempts a
minute per address and 10 per handle.

## The client

- `src/app/core/account/` — sign-up, sign-in, recovery, password and recovery-sheet changes, deleting the account,
  the session (as AttackFM: a token in storage, refreshed on launch, device-key sign-in when it has lapsed), the keys
  in IndexedDB.
- `src/app/core/sync/crypto.ts` — the key handling above, WebCrypto only, so the browser, the phone and the desktop
  run the same code.
- `src/app/core/sync/notes.ts` — a pass: pull the feed from the cursor and merge it; then push every note whose
  fingerprint moved since it was last synced, and a deletion for every synced note gone since. A device keeps, per
  account, the cursor, each note's last `rev` and fingerprint, and each file's `rev` (and hash, for a recording).
- **A conflict makes a copy, never a loss.** A note changed on both sides keeps the other device's version under its
  id, and this device's version becomes a new note beside it (the file gets a number, `Title 2.md`). A note deleted
  on one device and changed on another comes back. A push that loses a race is merged the same way and sent again.
- **Files follow their notes:** a recording is sent when its hash changes and fetched when a note arrives with a hash
  this device doesn't have; a picture is sent with the note that first names it. A browser syncs pictures but keeps
  no recordings.
- **And every pass settles the pictures** (`settlePictures`): each picture a note here names that this device holds
  and the account lacks is sent (the account asked first by a HEAD on its file, so one it has is not uploaded again),
  and each the account holds and this device lacks is fetched, asked again at most every four minutes while it is not
  there yet. A picture can reach a device by another road than the app - a note written through the MCP naming
  pictures another program put in the Mac's picture folder - and before this the Mac marked such a picture as sent
  without sending it, and a phone that asked for one too early never asked again (Matt's HelloTrade book, 2026-09-22).
  A picture that lands while its note is on screen is drawn at once (`src/app/core/images.ts`).
- `src/app/core/sync/prefs.ts` — AttackFM's settings blob, sealed. Only the settings about the person travel (theme,
  type, density, recording behaviour, code colours, view, animations, link previews), with the open tabs and their
  groups, the workspaces and what is filed in each, the trash, and the shared links with their keys; the downloaded
  model and Local only stay on the device. A device that changed nothing takes the account's; one that did sends its
  own.
- `src/app/core/sync/engine.ts` — runs a pass on launch, on return to the app, a few seconds after a note or setting
  changes, and every five minutes; one at a time. Nothing runs without the account key, or with Local only on
  (Settings › Formatting).
- Native: `store_apply` writes a note whole, with its own times, pin, archive, folder and sidecar
  (`library::Library::apply_note`), and `sync_put_file` keeps a synced recording or picture under its own name;
  **native generation 16**. An older app doesn't sync, and the Account page says so.
- Tests, in the default run: `src/app/core/sync/crypto.test.ts`, `src/app/core/sync/notes.test.ts` (the merge rules),
  `src/app/core/sync/engine.test.tsx` (when a pass runs), `src/app/core/sync/pictures.test.ts` (`settlePictures`,
  without a server) and `src/app/core/sync/prefs.test.ts`, with `src/app/core/account/account.test.ts` and
  `src/app/core/account/keystore.test.ts`; the devices they sync are made by `src/test/syncDevice.ts`.
  `src/app/core/sync/sync.e2e.test.ts` runs two devices against a real `glyph-api`
  (`GLYPH_SYNC_E2E=<data dir> VITE_GLYPH_API=http://127.0.0.1:<port>/glyph/api`). The server's side is
  `server/src/sync_tests.rs`.

## Claude, as a device

An MCP server (`mcp/`, docs/MCP.md) signs in to an account from outside the app and reads and writes its notes on
this same wire, sealing and opening them with the account key it unwraps at sign-in and keeps as a phone does. It is
one more device to the service, and to the other devices its notes arrive as any device's do. Its hosted form runs
on the box beside this service and holds a signed-in person's key in memory for their session - the one place the
key is ever held off a device, chosen with that said plainly on the sign-in page.

## The desktop

The same Tauri app built for macOS (`npm run desktop:dev`, `npm run desktop:build`): on-device Whisper and the
language models run there as they do on the phone. The window is the wide layout the Fold already uses.

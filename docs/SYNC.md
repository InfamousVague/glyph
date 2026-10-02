# Accounts and sync

Ghost.md accounts, and notes, settings, recordings and pictures kept the same on every device, **end-to-end
encrypted**: the server holds copies it cannot read. Matt's brief (2026-09-16): "make a tauri/desktop version and add
account signup to keep notes in sync across devices, copy the mechanisms on attack.fm". His choices: an account of its
own (not the attack.fm one), end-to-end encryption, and notes + settings + recordings from the start. Served from
`ghostmarkdown.com/api` now (attack.fm stays a working alias). The page takes the address from one build setting, `VITE_GLYPH_API`, for accounts,
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

Not copied: AttackFM's friends, shares and presence, its pairing codes, and the review-box backdoor. Ghost.md has
shared links of its own, a different thing under the same word (docs/SHARING.md), live typing (docs/LIVE.md), and,
since 2026-10-02, organizations with invitations by handle and a notifications feed (docs/TEAMS.md). The invitations
differ from AttackFM's: they are to a named team, not between friends; an organization's name, hue, members' handles
and roles are plaintext on the service, as handles already are, while the notes stay sealed per account; and the
feed carries two shapes in one table, the service's own rows about a team in the clear and the account's own rows
(Claude's writes, a summary, a conflict) sealed under the account key.

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
Not titles, not folders, not a word of any note, not settings, not a second of audio. With organizations
(docs/TEAMS.md) it also sees an organization's name and hue, who is in it by handle and in what role, who invited whom
and when, and each notification's kind, time, sender, organization and small body for the kinds it makes itself; for
every notification, sealed ones included, when it was read and whether it is hidden; and, once, whether a handle
exists, told to a signed-in account that invites it (404 "No one has that handle.", thirty an hour per account and
per address). A self-made notification's payload - the note's title, the lines Claude changed - it cannot read.

## The wire

All under `/api/v1/`, bearer token where signed in, JSON unless said. `login` values are 64 hex characters;
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

POST   orgs                          { name, hue? }                       -> 201 { org }           (docs/TEAMS.md has the shapes, the refusals and the limits)
GET    orgs                                                               -> { orgs: [OrgRow] }
GET    orgs/<id>                                                          -> { org } | 404
PUT    orgs/<id>                     { name?, hue? }                      -> { org }
DELETE orgs/<id>                                                          -> { deleted: true }
POST   orgs/<id>/members             { handle }                           -> { member } | 404 | 409
DELETE orgs/<id>/members/<handle>                                         -> { removed: true }
PUT    orgs/<id>/members/<handle>    { role }                             -> { member }
POST   orgs/<id>/invite              { accept }                           -> { org } | { declined: true }

GET    notifications?since=<rev>&limit=                                   -> { rev, items: [Notification], more }
POST   notifications                 { id, kind, blob }                   -> { rev }   (a self kind, sealed; idempotent by id)
POST   notifications/read            { ids?, all?, before? }              -> { rev }
PUT    notifications/<id>            { read?, hidden? }                   -> { rev }
```

Deleting the account deletes everything the service keeps for it: its notes, settings, recordings and pictures, its
shared links, its devices and its recovery codes, its organization rows and its notifications (Settings › Account ›
Delete account, or the page `landing/delete-account.html`). It is refused, inside the same transaction, while the
account owns an organization anyone else is in: 403 "Hand over or delete your organizations first."; an organization
whose only row is its owner's goes with the account, and every organization the account had joined is told it left
(docs/TEAMS.md). The same `/api/v1/` holds the shared links (`shares`, docs/SHARING.md), the live relay (`live`,
docs/LIVE.md), and the organizations and notifications (`orgs`, `notifications`, docs/TEAMS.md).

The HEAD has no route of its own: axum answers it through the GET, which reads the whole file to send only its
headers. The client asks it of every picture a pass settles.

One `rev` counter per account, bumped by every write, is the feed's cursor. A note's own `rev` is the counter at its
last write, and a push names the `rev` it was made from (`base`); a push whose base is not the note's current `rev`
lost a race and gets the winner back. A note the server has never seen is accepted whatever the base. The
notifications feed rides the same counter: a row written to an account, by the service or by one of its devices,
takes the account's next `rev`, and so does every change to one (read, hidden, an invitation answered), so the row
is fed again and the state follows the person across devices.

The `recordings` route holds every synced file, by an id the client makes: `r-<note id>` for a note's recording (WAV),
`i-<ext>-<stem>` for a picture `<stem>.<ext>`.

What is sealed, and under which associated data: a note as `{ v: 1, note, recording?, images? }` under `note:<id>`
(`recording` is a hash of the WAV, `images` the picture names the body uses); the synced settings under `prefs`; a
file under `file:<its id>`; a notification the account makes for itself as `{ kind, ...details }` under
`notification:<id>`, with the kind inside the seal so nothing outside it can relabel the row (docs/TEAMS.md).

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
- **Two cases merge without a copy.** Two bodies that differ only by the app's summary section keep the other
  device's words with this device's section. And two copies of a notebook that are the same once their index's lines
  are taken out keep the other device's, with each line only this device has put after the line it followed here
  (`mergedIndex`, DESIGN §142): a journal written in on the phone and on the Mac between two syncs stays one "Diary",
  not "Diary" and "Diary 2". A line taken out on one side and kept on the other comes back; a journal draws an
  entry's line whose note is gone as nothing.
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
  (Settings › Account › Privacy). A pass is four steps: the notifications, the notes, the settings, the organizations.
- `src/app/core/notifications/` and `src/app/core/orgs/` — the two new steps (docs/TEAMS.md): the feed, read from
  the cursor with the pending marks replayed first and the self rows not yet posted sent again; and the list of
  organizations, after which the organization workspaces are brought into line with it. Both are quiet against a
  service that does not have their routes yet (`notYet`, `core/account/api.ts`), and each keeps its own per-account
  key, `glyph-sync-<accountId>-notifications` and `-orgs`, forgotten with the rest on sign-out.
- Native: `store_apply` writes a note whole, with its own times, pin, archive, folder and sidecar
  (`library::Library::apply_note`), and `sync_put_file` keeps a synced recording or picture under its own name;
  **native generation 16**. An older app doesn't sync, and the Account page says so.
- Tests, in the default run: `src/app/core/sync/crypto.test.ts`, `src/app/core/sync/notes.test.ts` (the merge rules),
  `src/app/core/sync/engine.test.tsx` (when a pass runs, and in what order), `src/app/core/sync/pictures.test.ts`
  (`settlePictures`, without a server) and `src/app/core/sync/prefs.test.ts`, with
  `src/app/core/account/account.test.ts` and `src/app/core/account/keystore.test.ts`; the devices they sync are made
  by `src/test/syncDevice.ts`. The notifications and the organizations have
  `src/app/core/notifications/feed.test.ts` (two devices converging on what was read and hidden) and
  `src/app/core/orgs/orgs.test.ts` (the reconcile, on a list that arrived and only then).
  `src/app/core/sync/sync.e2e.test.ts` runs two devices against a real `glyph-api`
  (`GLYPH_SYNC_E2E=<data dir> VITE_GLYPH_API=http://127.0.0.1:<port>/api`). The server's side is
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

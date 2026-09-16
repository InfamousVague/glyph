# Accounts and sync

Glyph accounts, and notes, settings and recordings kept the same on every device, **end-to-end encrypted**: the
server holds copies it cannot read. Matt's brief (2026-09-16): "make a tauri/desktop version and add account signup
to keep notes in sync across devices, copy the mechanisms on attack.fm". His choices: a Glyph account of its own
(not the attack.fm one), end-to-end encryption, and notes + settings + recordings from the start. Served from
`attack.fm/glyph/api` for now; the address is one setting (`VITE_GLYPH_API`).

## What is copied from AttackFM, and what is not

AttackFM's registry (`AttackFM/server/crates/registry`, `crates/identity`) is the model:

| Piece | AttackFM | Glyph |
| --- | --- | --- |
| Identity | handle + password, and/or a device key; 8 recovery codes | the same |
| Token | `afm1.<claims>.<sig>`, Ed25519, 7 days, `POST /v1/refresh` | the same shape, tagged `glyph1` |
| Signing key | generated on first boot, kept in the database's `meta` | the same |
| Server | Rust, axum, rusqlite, argon2, behind Caddy on loopback | added to `glyph-api`, which already runs there |
| Settings sync | one JSON blob with a `rev`; a stale `rev` gets 409 and the current blob | the same, the blob encrypted |
| Library sync | a `rev` change feed with deletion markers, server-written | the same feed, but every device writes: a push carries the `rev` it was based on |
| Rate limits | none on login | **added**: per address and per handle |
| Encryption | none | **end to end**, below |

Not copied: friends, invites, shares, presence, pairing codes, the review-box backdoor.

## Keys

Nothing the server stores can be read without a key it never sees.

- **The account key (AK).** 32 random bytes, made on the device that signs up. Every note, setting and recording is
  encrypted with it: AES-256-GCM, a fresh 12-byte IV per write, the item's id and kind as associated data (so a
  blob cannot be swapped onto another item).
- **The password never leaves the device as itself.** PBKDF2-SHA-256, 600 000 rounds, salt `glyph/v1/<handle
  lower-cased>`, 64 bytes out: the first 32 are the **login secret** (sent in place of the password, and Argon2-hashed
  by the server exactly as AttackFM hashes a password), the last 32 the **password wrap key**, which never leaves.
- **AK is stored on the server only wrapped:** once under the password wrap key, and once under each recovery code
  (the same PBKDF2, salt `glyph/v1/recovery/<code>`). Wrapping is AES-256-GCM.
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

All under `/glyph/api/v1/`, bearer token, JSON unless said.

```
POST signup            { handle, loginSecret?, devicePublicKey?, wrapped: { password?, recovery[8] } } -> { token, recoveryCodes? }
POST login             { handle, loginSecret }                          -> { token }
POST login/challenge   { handle }                                       -> { nonce }
POST login/device      { handle, nonce, signature }                     -> { token }
POST login/recovery    { handle, code }                                 -> { token }
POST device            { publicKey, label }                             -> {}
POST refresh                                                            -> { token }
GET  keys                                                               -> { password?, recovery[] } (wrapped AK)
PUT  keys              { password?, recovery? }                         -> {}      (after a password change)

GET  notes?since=<rev>&limit=                                           -> { rev, items: [{ id, rev, deleted, blob? }], more }
PUT  notes/<id>        { base, blob }                                    -> { rev }  | 409 { rev, blob, deleted }
DELETE notes/<id>      { base }                                          -> { rev }  | 409 …

GET  prefs                                                              -> { rev, blob }
PUT  prefs             { base, blob }                                    -> { rev }  | 409 { rev, blob }

PUT  recordings/<id>   (octet-stream, encrypted)  ?base=<rev>            -> { rev }
GET  recordings/<id>   -> octet-stream
```

One `rev` counter per account, bumped by every write, is the feed's cursor. A note's own `rev` is the counter at its
last write, and a push names the `rev` it was made from (`base`); a push whose base is not the note's current `rev`
lost a race and gets the winner back.

Limits: a note blob 1 MB, prefs 256 KB, a recording 64 MB, 20 sign-in attempts a minute per address, 10 per handle.

## The client

- `core/account/` — sign-up, sign-in, the session (as AttackFM: a token in storage, silent refresh, device-key
  fallback), recovery codes.
- `core/sync/crypto.ts` — the key handling above, WebCrypto only, so the browser, the phone and the desktop run the
  same code.
- `core/sync/notes.ts` — a pass: pull the feed from the cursor and apply it; then push every local note changed
  since it was last pushed, and a deletion for every note gone since. Runs on sign-in, on launch, on return to the
  app, a few seconds after an edit settles, and every few minutes.
- **A conflict makes a copy, never a loss.** When a push loses and both sides changed the words, the other device's
  version stays as the note and this device's is kept beside it as "Title (conflict, <device>)". Metadata-only
  differences (a pin, the archive) merge without a copy.
- Settings sync is AttackFM's `prefsSync` shape, encrypted.
- Recordings follow their note: pushed after it, fetched when a note with a recording arrives without one.
- Applying a remote note needs the store to take a note whole, times and all: `store_apply` in
  `src-tauri/src/store.rs`, **native generation 16**. An older app can't sync; Settings says so.

## The desktop

The same Tauri app built for macOS (`npm run desktop:dev`, `npm run desktop:build`): on-device Whisper and the
language models run there as they do on the phone. The window is the wide layout the Fold already uses.

# Stage 7, account and sync: what was read in ../glyph (2026-10-07), and the plan

## Rules before anything else
- **A development build never talks to ghostmarkdown.com.** No default API base in debug; work against the fake service
  (a port of `src/test/fakeService.ts`) and a local copy of `server/`. Sign-up, device keys, `PUT account/key` and an
  organization's first key are permanent or first-wins on the real service; a bad note mark or preferences write would
  spread conflict copies, deletions or dropped settings to every real device.
- There are no pinned crypto vectors in the web repo: the port makes its own from the web code (Node script) and must
  pass them in both directions.

## Crypto (to live in the Rust core behind the FFI, keys held by handle)
PBKDF2-HMAC-SHA-256, 600,000 rounds, 64 bytes; salt `glyph/v1/<handle lower>` (password) or `glyph/v1/recovery/<handle>`;
bytes 0–31 login half (hex), 32–63 AES-256 wrap key. Account key wrap: base64url(iv12 ‖ AES-GCM(raw key)), AAD
`account-key`. Seal: `0x01 ‖ iv12 ‖ AES-GCM`, AAD = the context (`note:<id>`, `prefs`, `file:<id>`, `notification:<id>`,
`encryption-key`, `glyph/v1/share`, `live:<note>`, `live:org:<org>:<room>`, `org:<org>:note:<id>[:update]`), base64url
without padding. Device key Ed25519. Account pair ECDH P-256 (public = raw 65-byte point; private as JWK sealed under
the account key). Org key wrap: ephemeral P-256 → HKDF-SHA-256 (empty salt, info `glyph/v1/org-key:` + context
`org-key:<org>:<generation>`) → AES-GCM, output point65 ‖ iv12 ‖ ct. Recovery codes: 12 random bytes & 31 into
`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, eight to a sheet. Device storage: keys and the session token in Keystore-backed
secure storage; cursors and feeds in `Stored`; org keys in memory only.

## Sync
One pass at a time (notifications, org list, notes, preferences, org keys + team notes), on start, on resume, 4 s after
a save or preference change, every 5 minutes; no HTTP backoff. Notes: pull by cursor, merge (deletion only if unchanged
here; summary-section merge; notebook-index merge; else a conflict copy), push sealed `{v:1, note, ...}` with `base`,
one retry on 409, tombstones for ids gone locally. Files on the `recordings` route (`r-`, `v-`, `i-` ids). Preferences:
one sealed blob, three-way merge per key. The engine needs `LocalNotes {list, get, apply, remove}` and
`LocalFiles {read, write, owed, settled, digest}`; the core still lacks `sync_put_file` and a picture reader.

## Live typing and team notes
Yjs v1 updates, state vectors, `Y.Text` in UTF-16, relative positions, awareness; `yrs` in the Rust core, proven first
against fixtures made by the web's Yjs. Relay: `wss://…/api/v1/live`, JSON frames, auth in the first frame, 64 KB a
frame; envelope = kind byte (Query, State, Update, Presence) + sealed payload.

## Pieces
A crypto core + vectors · B API client + fake service · C account + key store + Account page · D file commands in the
core · E versions file · F notes/prefs sync + engine · G notifications feed · H organizations · I CRDT core (yrs) ·
J team notes · K live (needs the editor) · L shares and links · M comments format.
Order: A, D, E, I, M together; B then C; F and G; H, J, K; L after F.

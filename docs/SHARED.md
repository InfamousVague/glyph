# Notes shared in an organization

Matt's brief (2026-10-04): "In organizations, add the ability for users to pick and change their color. the color
will be used to tag the persons cursor when they are live editing a document or have a section of the document
highlighted. I would like to be able to see the activity for users in organizations like "editing <doc_name>" and be
able to click the user's profile and "jump to cursor" to open the doc they're editing to the exact point.
Organizations should have real time sync on documents so everyones stuff stays up to date. I would like to also be
able to leave comments on documents in a common format that renders as a comment on the document as well as
allowing for threads on the comment, make this a standard format within the markdown documents themselves and make
sure replies and comments are tracked per user in the organization" - and, while it is being built, "also build in
cursor tracking on canvases and comments".

His answers to the four questions it raised: **filed is shared** (a note filed in an organization's workspace is
the team's); **end-to-end, with an organization key** wrapped per member; a colour **per account, with a
per-organization override**; comments as **an anchor in the prose and a `comments` fence** at the end of the note.
And a standing word: glyph-api is deployed as each slice lands.

This is the follow-up [TEAMS.md](TEAMS.md) left for later ("Not shared yet"): the organization key, team notes,
live editing between members, presence and colours, and comments. It sits on [SYNC.md](SYNC.md) (the durable sync),
[LIVE.md](LIVE.md) (the relay and the CRDT), [TEAMS.md](TEAMS.md) (organizations) and [CANVAS.md](CANVAS.md).

## The model

**S1. Filed is shared.** A note filed in an organization's workspace is the team's: on every member's devices, read
and edited by every member, live when two have it open at once. Filing is the sharing, and there is nothing else to
press. Taking a note out of the workspace takes it from the team, and the move asks first; trashing it trashes it
for everyone; every member's edits are in its version history by handle, which is what the audit log (DESIGN §183)
reads. A note made in the workspace - New note on the dashboard, a note filed from its More - is the team's from its
first word.

**S2. The organization key.** 32 random bytes, made on a member's device and never seen by the service. Every member
holds it wrapped under their account's encryption key pair (S3), a row each: `org_keys(org, account, generation,
wrapped, by, at)`, with `org_key_state(org, generation, made_by, at)` naming the generation in force. The first
member device to ask the service for the key and find no generation makes one and wraps it for every member who has a
public key, itself included; two devices making one at once are settled by the service, which keeps the first and
answers the second 409 with the generation it keeps, so the second throws its key away and reads its wrap. From then
on any device holding the key wraps it for whoever the service says lacks one (`missing`: members without a wrap at
the generation in force, with their public keys), so a member who joins reads their wrap on their next sync, made
by whichever member's device synced first. Team notes, their versions files, their pictures and every live message
in the organization's rooms are sealed under it, AES-256-GCM as everything else is (SYNC.md, Keys), with
`org:<org id>:` at the head of the associated data so nothing sealed for one organization opens in another.

**S3. The account's encryption key pair.** Only signing keys existed (Ed25519, a device each). An account now has one
encryption key pair, ECDH P-256 - WebCrypto has it on every engine the app runs on, which X25519 does not yet - made
on the first signed-in device that needs it and registered with the service: `PUT /api/v1/account/key { pub, sealed }`,
the public key in the clear and the private key sealed under the account key, so every other device of the account
reads and unseals it (`GET /api/v1/account/key`) and keeps it as a non-extractable key beside the account key
(core/account/keystore.ts). The service keeps the first registration and answers a second 409 with it, so two devices
racing to make one end with one. Wrapping is ECIES: an ephemeral P-256 pair per wrap, ECDH with the member's public
key, HKDF-SHA-256 (info `glyph/v1/org-key`) to an AES-256-GCM key, the organization key sealed under it with
`org-key:<org id>:<generation>` as associated data; the wrap is the ephemeral public key, the IV and the ciphertext,
base64url. An account made before this slice gets its pair the first time a device of its signs in on a build that
has it; until then the organizations it is in list it as `pub: null`, and no wrap can be made for it.

**S4. Where team notes live.** On the service, under the organization: `org_notes(org, id, rev, deleted, blob, by,
updated_at)` with the account feed's shape (`GET /api/v1/orgs/{id}/notes?since=&limit=`, `PUT …/notes/{nid}
{ base, blob }`, 409 with the winner; `DELETE` the same way), the CRDT's update log `org_note_updates(org, note, seq,
blob, by, at)` (`GET …/notes/{nid}/updates?since=`, `POST …/notes/{nid}/updates { blobs }`; `GET …/heads` answers every live
note's log head in one read, so a pass fetches only the logs that moved), and the note's sealed
files - its versions file, its pictures - as `GET`/`PUT …/orgs/{id}/files/{fid}`. The organization has a write
counter of its own, as an account does, so a member's feed cursor is per organization. A member reads and writes;
nobody else reaches them; the service checks membership, sizes and shapes, never content, and records who wrote
(`by`), which the audit log does not need but a removal does.

**S5. The document of record is the CRDT.** A team note is a Yjs document (LIVE.md): its text in a `Y.Text` - a
canvas's nodes and edges in a `Y.Map` and a `Y.Array` (S9) - held on the device as the document's state
(IndexedDB, `ydoc:<note id>`, beside the account's keys) and on the service as the note row's blob (the state, sealed,
compacted now and then) with the updates since in the log. A device that opens or syncs a team note applies the
updates it has not seen and posts its own, so two members who edited apart merge by the CRDT, never into a conflict
copy; the markdown file in the library is the document's text, written as it changes, so the Mac's folder, the
connector and every extension read the note as ever. The pass sync (SYNC.md) leaves team notes alone: the organization
channel is theirs. A device compacts when the log it reads is long (`PUT` the row with a fresh state and the `seq` it
holds; the service drops the updates up to it).

**S6. Live for the team.** The relay's rooms grow an organization form, `org:<org id>:<note id>`, which a member of
the organization may join: the service checks membership on `join` and tells the room's sockets when a member is
removed, which closes them out of it. Over the room go the document's updates, sealed under the organization key,
exactly as an account's rooms carry them today, so typing crosses in the time a message takes; and **presence**, the
`presence` kind LIVE.md reserved: the awareness protocol (y-protocols) sealed the same way, carrying the member's
handle, colour and selection as Yjs relative positions, drawn by `yRemoteSelections` - the caret in their colour with
their handle on it, the selection a wash of it. The organization's own room, `org:<org id>`, is joined by every
member's device while the app is open: its awareness says who is in the app, which note or canvas they have open and
where their caret or pointer is, so an organization's dashboard reads "editing Roadmap" beside a member, and
**Jump to cursor** on their profile opens that note at that point (the relative position resolved against the
document once it is loaded). What the relay learns grows by this, and S10 says so.

**S7. Colours.** A person's colour is one of the app's seven hues (core/workspaces.ts `WORKSPACE_HUES`; `ink`, the
default, is no colour). The account's is `account_hues(account, hue)`, set under Settings › Account › Your colour;
an organization can override it, `org_member_hues(org, account, hue)`, set from the organization's dashboard or its
settings as "Your colour here" (the account's, or one of the seven). Both are in the clear on the service, as the
organization's hue is: a colour is not a secret. The effective colour rides in every member row the service answers
(`colour`), and in the account's own list (`GET orgs` answers `colour` for the account and `myColour` per row), so the
member rows, cursors, selections, comments and the profile card all wear it, and a member who never chose one is ink.

**S8. Comments.** In the markdown itself (Matt: "a standard format within the markdown documents themselves"): an
anchor after the words, `[^c1]`, or round a selection, `==the words==[^c1]`, and one fence at the end of the note
holding every thread:

```comments
c1 matt 2026-10-04T19:00:12Z
The venue needs confirming - the hall or the barn?
  sam 2026-10-04T19:05:40Z
  The hall. Confirmed this morning.
  resolved sam 2026-10-04T19:06:02Z
```

A comment is its id, a handle, a time and words; a reply is indented two under it, the same shape; `resolved` with a
handle and a time closes the thread, which keeps its words and loses its wash. Ids are `c` and a short random tail,
never reused. In the editor the anchor is a small round in its author's colour at the words (the selection washed in
it), a tap opens the thread card - the comments, a reply field, Resolve - and the fence is drawn as the list of
threads, as a board's fence is drawn as a board; Comment on the selection toolbar and in More starts one. Anywhere
else the note is read, the anchor is a footnote-looking mark and the fence a readable block. Tracked per person: each
line names its author; the audit log reads "sam commented on Roadmap" from the version that added it (its first
changed line being in the fence), and a member's profile card counts their comments and replies.

**S9. Canvases.** A canvas (CANVAS.md) in an organization is the team's as a note is: its nodes in a `Y.Map` by id,
each node a `Y.Map` of its fields with a card's text a `Y.Text`, its edges a `Y.Array`, so two members moving and
typing in cards at once merge. Presence on a canvas is the pointer's place in canvas space and the card being edited:
others' pointers are drawn as small arrows in their colour with their handle, a card being edited is ringed in its
editor's colour, and Jump to cursor pans to that place. Comments on a canvas are a `comments` array in its JSON, a
thread each - `{ id, node, by, at, text, replies }` - anchored to a card, drawn as a round on the card's corner.

**S10. What the server can see**, beyond TEAMS.md's list: each account's public encryption key; the organization key
wrapped per member (ciphertext); a team note's id, size, times and who wrote each row and update; the update log's
sizes and timing; which member has which team note open live, when, and the sizes and timing of what passes; and
colours. It still cannot read a title, a word, a comment, a caret's place or a pointer's.

**S11. Limits.** 2,000 team notes an organization; a note row 1 MB and an update 64 KB, as a frame is; a log compacted
past 500 updates; the relay's limits as they were, with 16 rooms an organization's socket may hold at once. Rotation
of the organization key on a removal or a leaving is a generation after the one in force, made by the next member
device to sync, wrapped for the members who remain, with every team note re-sealed under it by that device: S2's
`missing` handles the members, and the re-sealing is slice 6.

## Slices

1. **Keys and colours** - shipped 2026-10-05 (DESIGN §191). S3, S2 (the key made and wrapped; nothing uses it yet),
   S7. Server: the four tables and their routes; the member rows carry `pub` and `colour`. App: the key pair made
   and kept, the organization key fetched, made and filled, the colour pickers, the member rows coloured.
2. **Team notes** - shipped 2026-10-05 (DESIGN §193). S1, S4, S5: the organization channel in the sync engine, the
   CRDT of record, versions and pictures by the organization, the dashboard's "yours for now" words gone, the
   move-out asking first.
3. **Live for the team.** S6: organization rooms, presence, cursors and selections in the editor, "editing Roadmap",
   the profile card and Jump to cursor.
4. **Comments.** S8 on notes.
5. **Canvases.** S9: live, pointers, comments.
6. **Rotation and pruning.** S11's rotation and re-sealing; the log compacted on the service's side as well.

Each slice ships glyph-api first, then the web OTA after the login gap (TEAMS.md, D11), with its design note in
DESIGN.md and its tests beside the code.

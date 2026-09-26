# Live typing over a relay

_Two devices with one note open, a keystroke crossing in milliseconds, and a relay that passes along ciphertext it cannot read._

## What it is for

`docs/LIVE.md` sets out the idea. A note is open on two of one account's devices, and what is typed on either arrives on the other a character at a time. Live typing sits on top of sync, and sync stays the durable layer: offline work, recordings, pictures, and every note that is not open right now. Live typing covers only what two devices have open at the same moment, and it is off until a device turns it on.

## The relay

`server/src/live.rs` is a WebSocket at `/glyph/api/v1/live`. A browser cannot put an `Authorization` header on a WebSocket, so the socket signs in with its first frame, `{ t: "auth", token }`, within ten seconds. The server checks that token with the same verifier every HTTP route uses. The token never rides in a URL, where an access log would keep it.

| Direction | Frame | Meaning |
|---|---|---|
| in | `{ t: "auth", token }` | must be the first frame, or the socket closes with 4401 |
| out | `{ t: "ready", id }` | this socket's connection id |
| in | `{ t: "join", room }` | join a room; a room is a note id |
| in | `{ t: "leave", room }` | leave a room |
| in | `{ t: "msg", room, data, to? }` | `data` is base64url ciphertext; `to` names one connection, or leave it out for everyone |
| out | `{ t: "joined", room, first, peers }` | `first` means the room was empty until now |
| out | `{ t: "peers", room, peers }` | a device came or went |
| out | `{ t: "msg", room, from, data }` | `from` is a connection, never an account |
| out | `{ t: "error", message }` | a frame was refused, and the socket stays open |

Rooms are keyed by account as well as name, so a socket only ever reaches its own account's devices. Data is passed on untouched, nothing is stored, and no message is logged. A WebSocket is not covered by CORS, so the upgrade checks the page's origin itself. It lets in the origins the HTTP routes allow, or a page served over HTTPS from the host the socket reached. A client that sends no origin, as the phone's and the Mac's own networking do, is let through, because the token is what admits a device.

| Limit | Value |
|---|---|
| sockets per account | 16; the next is closed with 4429 |
| rooms per socket | 64 |
| frame size | 64 KB; a binary frame closes the socket with 4400 |
| messages per socket | a bucket of 200, refilled at 100 a second; then close with 4429 |
| queue to one device | 128 messages; a device further behind is closed with 4408, and comes back whole |
| ping | every 25 seconds |
| lifetime | until the token expires, then close with 4401 |

## The transport

`src/app/core/live/transport.ts` defines one interface, `LiveTransport` (join, leave, send and close), and the events that come back. `WebSocketTransport` is the relay's implementation. It signs in when the socket opens and rejoins every room when `ready` arrives. After a drop it reconnects with a jittered backoff, from half a second up to thirty seconds, and it tries again at once when the page comes back into view or the network returns. A 4401 is the one close it does not retry on its own: the next wake or network change connects again, with whatever token the account holds by then. Peer-to-peer is planned as a second implementation of the same interface, with nothing above it changing, and it has not been written.

## The wire

In `src/app/core/live/wire.ts`, a message is one byte of kind followed by the payload. It is sealed with `crypto.ts` under the account key, with `live:<note id>` as associated data, so a message cannot be replayed into another note. The format is binary, not JSON, because the payload is a Yjs update, and base64 inside JSON would cost a third more on every keystroke.

| Kind | Byte | Sent |
|---|---|---|
| Query | 1 | "send me your document", by a device that was not first into the room, or one back after a drop |
| State | 2 | the whole document, led by a 16-byte seed id: to the device that asked, or to the room when a device comes back after a drop |
| Update | 3 | one change: a keystroke or a paste |
| Presence | 4 | defined, and never sent |

## The document and the binding

`src/app/core/live/session.ts` holds a `LiveSession` per note: a `Y.Doc` with the words in a `Y.Text`. Outgoing messages are sealed one after another, in the order they were made. A change from another device is applied under the `REMOTE` origin, so it is not sent back out. `src/app/editor/liveBinding.ts` binds the editor with `yCollab` from `y-codemirror.next`. It first brings the editor to the document's words, then swaps CodeMirror's undo for a Yjs `UndoManager` in the undo slot (`editor/undoSlot.ts`), so an undo on one device takes back only that device's typing. The binding is given no awareness, which is why no remote caret is drawn.

## Seeding, and why it is the trap

Two devices that each build a document from the same words hold the same text under different CRDT identities, and merging them doubles the note. So the document is made once and adopted everywhere else.

- The relay serialises joins, so exactly one socket opens a room and hears `first: true`. That device seeds the document from its note and stamps it with a random seed id.
- Every later device sends a Query and waits. It asks up to three times, 2.5 seconds apart, and adopts the State it receives whole. If its own words differ from the room's, it checks whether its note has changes the sync pass has not sent (`hasUnsyncedChanges` in `core/sync/engine.ts`). If it has, it keeps its words as a note of their own. If it was only behind, it keeps nothing.
- If nobody answers and nobody else is in the room, the device seeds the document itself. If somebody is there but will not answer, it stays out rather than risk a second history.
- A device that comes back after a drop trades whole documents with the room. The same seed id merges exactly. A different seed id means the room was made again while the device was away, and the session closes rather than merge a history it does not share.

The tempting shortcut is to diff the room's words against this device's and replay the difference. It is wrong: a device that is merely behind would replay the other devices' newer typing as an undo of it.

## The hub, the door and the switch

`src/app/core/live/hub.ts` keeps one connection for the device. It makes the connection when the first note goes live, closes it with the last, and hands each message to its room's session. `open.ts` (`goLive`) is the one door the note screen uses, and `editor/useLiveNote.ts` imports it on demand, only while the switch is on, so Yjs and its binding are not in the app until a device asks for them. `openLive`, in `hub.ts`, answers null when the switch is off, the device is signed out, or it holds no account key, and the note goes on as it always has.

The switch is `core/live/enabled.ts`, a device flag (`glyph-live`) that never syncs: Settings › Account › Sync › Live typing (trial). It applies from the next note opened. Nothing on screen says a note is live: the typing arriving from the other device is the sign.

## Living on top of sync

While two people type, their words differ by whatever is in flight. A sync pass in the middle would take that difference for a conflict and copy the note. So a note that is ready and has another device in its room is marked in `core/live/shared.ts`, which holds no Yjs, so the pass can check it without loading live code. Both halves of the pass skip a marked note, and its revision stays unrecorded. Once the session ends, the push meets a 409, finds the same words on both sides, and nothing is copied.

## The tests

- **`server/src/live_tests.rs`**, over a real socket. It checks that a socket must sign in first or be closed with 4401, and that an edit reaches the account's other device but not its own. It checks that another account in a room of the same name hears nothing, that a message can go to one device, and that the others are told when a device leaves. It checks that bad frames are refused with the socket kept, that an oversized frame ends the socket, and that a foreign origin is refused. It checks the limits of sixteen devices and sixty-four rooms, and that a socket ends with its token.
- **`src/app/core/live/session.test.ts`** runs whole rooms through a relay held in memory.
- **`src/app/core/live/session.rules.test.ts`** drives one session by hand, with no relay and no clock. It checks that a device asks three times, then seeds alone, and stays out when someone will not answer. It checks that a Query is answered only to the one who asked, the exchange after a drop, that a foreign history ends the session, and that a closed session sends nothing.
- **`src/app/core/live/live.e2e.test.ts`** puts two devices through a real glyph-api, with real sockets and real sealing. It measures how long a keystroke takes to cross, and checks that the server's database never holds a word. It runs only when `GLYPH_LIVE_E2E` names the server's data folder and `VITE_GLYPH_API` points at that server.

## Where LIVE.md and the code differ

- LIVE.md puts the document in `src/app/core/live/doc.ts`, which does not exist. The document is in `session.ts`.
- It lists `presence` (a caret) among the messages. The kind is defined in `wire.ts`, but nothing sends it, and `yCollab` is given no awareness.
- It says a socket closed when its token expires comes back with a fresh token. The transport does not retry after a 4401 by itself: it reconnects at the next return to view or change of network.
- It says a device that meets a different seed id after a drop is treated as joining fresh. In fact its session closes, and nothing opens a new one until the note is opened again. `session.ts`'s own comment says the editor opens a new session, and no code does.
- Its protocol table leaves out `ready`, `error`, and a message's `to`.

## Read next

- [[glyph-api, the server]]
- [[The editor and its language]]
- [[Live typing]]

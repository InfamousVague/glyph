# ghost_p2p: the direct network's core

The Rust half of Ghost Messaging's direct route (`docs/OPEN_NETWORK.md`, section 2; Matt, 2026-11-22: "look at iroh
as the rust backend for the p2p side"). A **node** is one device: a key made on the device, whose public half is its
**node id**. A node offers one thing, framed streams to another node by its id on a numbered **channel**, and says
how the path to each linked node stands. It is built on [iroh](https://github.com/n0-computer/iroh) 1.5 (QUIC,
hole punching, relay servers as a fallback, which the app calls **link helpers**).

It carries bytes and nothing else: who may link, what a frame means, when a phone's node is up are all the app's, in
Dart, behind `lib/net/p2p/node.dart` (`P2pNode`). `lib/net/p2p/node_ffi.dart` is this library's one caller.

    src/node.rs    the node, and every rule it keeps
    src/wire.rs    commands and events as bytes
    src/ffi.rs     the C interface (include/ghost_p2p.h)
    src/tests.rs   nodes in one process, linked over loopback and through a link helper inside the test

## What it never does

- **Look anyone up, or publish where it is.** The endpoint is made with no address lookup at all (no DNS or pkarr
  record, no DHT, no mDNS). A node is dialled only by what the app hands `OPEN` (where the other device last said it
  is) and by what iroh has learnt of it over a link since this node came up.
- **Talk to a server the app did not name.** Link helpers are the ones `START` names; with none, relays are off. A
  hint's helper is used only when it is one of this node's own, whoever sent the hint (iroh would otherwise connect to
  any relay address it is handed). The helper's name is asked of the system's own DNS servers and of no public
  resolver behind them (iroh's default falls back to Cloudflare, Google and Quad9; that is turned off).
- **Ask a link helper's name anything but what the helper is there for.** See "What a link helper is asked". iroh's
  captive-portal check is off: it asks `http://<the helper's name>/generate_204`, in plain HTTP on port 80 whatever
  the helper's own port, and where port 80 there is another server's, takes its answer for a captive portal.
- **Open a port on the router.** iroh's port mapping (UPnP, NAT-PMP, PCP) is not compiled in, nor its metrics, nor
  the faster datagram calls that are private to Apple's systems.
- **Believe a length.** A frame's length is checked against the most before anything is set aside for it, and its
  memory grows only as its bytes arrive, 64 KiB at a time.
- **Grow without bound.** See "What is counted".

`helpers_only` binds no socket of this node's own: every packet goes through a link helper, and the other device
sees the helper's address. Such a node says where it is by its helper alone, never an address.

### What a link helper is asked

A link helper is an iroh relay server, and is made from its https address alone, as `START` wrote it: a port and a
path are kept (`https://link.example:7843`), and no token goes with it. Its certificate is checked against the
roots compiled into the library (Mozilla's), not the system's. Three things are asked of it, all at that one name:

| | |
| --- | --- |
| The connection links are made through | HTTPS (a WebSocket) at the address itself, kept open while the node is up, with a ping every 15 seconds |
| How far away it is | an HTTPS GET of `ping` under the address, when iroh looks at the network |
| Where this node is seen from | QUIC on UDP port 7842 (iroh's usual port, which a helper keeps to; there is no saying another). Not asked by a `helpers_only` node, which has no socket to ask from |

A helper that asked for a token would be given it here too: iroh sends one as a bearer header on the first of
these. That is not built. The token would follow its helper's address in `START`, under a new interface number, and
be handed to iroh where a helper is made (`helper` in `src/node.rs`); nothing else would change.

### The port

A node asks for the same UDP port every time, for IPv4 and IPv6 alike, so that where a device was last said to be
is still where it is after a stop and a start, and after the app was closed and opened again on the same network.
The first time in a process it asks for the port its node key makes (49152 to 65535: two bytes of a signature over
words that are signed for nothing else, and that is shown to nobody, so the port is no one else's to work out from
the node id); every time after, for the port it had. A port that is taken is not waited for, but for a second
where it was this node's own a moment ago: the node starts on any other, which is then its port. A `helpers_only`
node has no port.

What that gives away: the same device shows the same local port on every network it joins, to whoever on that
network watches (behind a router, what the outside sees is the router's choice). Starting on any port instead is
one line (`first_port` in `src/node.rs`).

## The C interface

Seven functions. Every one may be called from any thread, none waits on the network, and each catches a panic
(`-6`, or nothing happens) so a bug here cannot take the app down.

| Function | What it does |
| --- | --- |
| `uint32_t ghost_p2p_abi(void)` | The interface's number, `1`. A caller that finds another number uses nothing. Raised whenever a function, a command, an event or what one means changes. |
| `int32_t ghost_p2p_node_id(const uint8_t *secret, uint8_t *out)` | The node id (32 bytes, into `out`) that a node key (32 bytes) makes, with nothing started. `0`, or `-2` where either is null. |
| `uint64_t ghost_p2p_new(uint64_t owner, ghost_p2p_event_cb callback)` | Makes a node, not started. Answers its number, or `0`. `owner` says who made it (the Dart side gives its Flutter engine's number). |
| `int32_t ghost_p2p_command(uint64_t node, const uint8_t *command, size_t len)` | Gives the node a command (below). The bytes are read before it returns and not kept. |
| `void ghost_p2p_buffer_free(uint8_t *buffer, size_t len)` | Gives back a buffer the callback was handed. |
| `void ghost_p2p_drop(uint64_t node)` | Stops the node and forgets it. Once this has returned the callback is not called for it again; its links and sockets close in the background. |
| `void ghost_p2p_drop_owned(uint64_t owner)` | The same for every node `owner` made. Called as the library is first opened: a hot restart ends an isolate without a word, and its nodes would stay up calling a callback that is gone. Another owner's nodes (a second Flutter engine in the same process) are left alone. |

    typedef void (*ghost_p2p_event_cb)(uint64_t node, uint8_t *event, size_t len);

The callback is called with a node's events one at a time and in order, from the library's own threads (two, named
`ghost-p2p`, made with the first node). `event` is the receiver's: it copies what it wants and gives the buffer back
with `ghost_p2p_buffer_free(event, len)`.

`ghost_p2p_command` answers:

| | |
| --- | --- |
| `0` | Taken. What it comes to is said in events. |
| `-1` | There is no such node. |
| `-2` | The command could not be read. |
| `-3` | `SEND`: there is no such stream (it has closed). |
| `-4` | `SEND`: the stream's queue was full. The stream is now closed. |
| `-5` | `SEND`: the frame is longer than 1 MiB. |
| `-6` | A bug in the library was caught. |

On Android there is one more, for Kotlin (`P2pCore.kt`): `Java_com_infamousvague_ghostmessaging_P2pCore_nativeInstall`
hands iroh's DNS the app's context, which it reads the phone's DNS servers through. It is called before Dart can
start a node.

## Commands

Every number is big-endian. A node id is its 32 bytes. Text is UTF-8. The first byte says which command it is.

| | Command | After the first byte |
| --- | --- | --- |
| `01` | START | `[helpers only: 1][node key: 32][how many helpers: 1]`, then for each `[length: 2][address]`. At most 8 helpers, each `https://…` and at most 200 bytes. Answered by UP or DOWN. Up already with the same: UP again, nothing else. Up with another: stopped (OFF), then started. |
| `02` | STOP | Nothing. Every stream closes, every linked node is told, the sockets close; then OFF. Who was allowed is kept. |
| `03` | ALLOW | `[node: 32][how many: 1][channel: 1]…` The channels this node may open streams on, in place of what it had; none takes it off the list. Streams it opened on a channel it no longer has are closed. |
| `04` | DISALLOW | `[node: 32]` Off the list, and every link and stream with it is closed. |
| `05` | OPEN_TO_ALL | `[how many: 1][channel: 1]…` The channels anyone may open, in place of what was. |
| `06` | OPEN | `[request: 4][node: 32][channel: 1][wait, ms: 4][helper length: 2][helper][how many addresses: 1]`, then for each `[length: 1][address]`. At most 8 addresses (`ip:port`), 64 bytes each. Answered by OPENED or OPEN_FAILED naming `request`. The wait is kept between 100 ms and 60 s. |
| `07` | SEND | `[stream: 8][the frame]` The frame is the rest of the command, 0 to 1 MiB. Queued; SENT says when it is written. |
| `08` | CLOSE | `[stream: 8]` What was queued before is written first, for 10 seconds at most; then the other end sees the end. CLOSED says when. |
| `09` | TAKEN | `[stream: 8][frames: 4][bytes: 4]` The app has handed that many frames, of that many bytes in all, to whoever listens. See "What is counted". |
| `0a` | DONE | `[stream: 8]` The app has handled the stream's CLOSED. |
| `0b` | NETWORK_CHANGED | Nothing. The device's network changed; Android does not tell native code by itself. |

ALLOW, DISALLOW and OPEN_TO_ALL are in force when `ghost_p2p_command` returns (a caller or a stream that comes after
is judged by them; what they close is closed a moment later). They are kept by the node whether it is up or not, and
across a STOP and a START.

## Events

| | Event | After the first byte |
| --- | --- | --- |
| `01` | UP | `[node id: 32]` |
| `02` | DOWN | `[why, in words]` It could not start (or stopped by a bug in the library). |
| `03` | OFF | Nothing. Stopped: nothing of the node is left. No event of the run before comes after it. |
| `04` | WHEREABOUTS | `[helper length: 2][helper][how many: 1]`, then for each `[length: 1][address]`. Where this node is: the helper it is on, written as START wrote it, and its own addresses, public ones first, at most 8. Said when it changes, no more than once a second. |
| `05` | PATH | `[node: 32][kind: 1][round trip, ms: 4]` kind `0` no link, `1` through a helper, `2` straight. `ffffffff` where no round trip is measured. Said when the kind changes, or the round trip by more than a quarter (and 10 ms). |
| `06` | OPENED | `[request: 4][stream: 8]` |
| `07` | OPEN_FAILED | `[request: 4][why: 1][in words]` |
| `08` | INCOMING | `[stream: 8][node: 32][channel: 1]` Another node opened a stream, on a channel it is allowed. |
| `09` | FRAME | `[stream: 8][the frame]` |
| `0a` | SENT | `[stream: 8][frames: 8]` How many of the stream's frames have been written, in all. |
| `0b` | CLOSED | `[stream: 8][why: 1]` |

OPEN_FAILED says why: `1` this node is not up, `2` it could not be reached in time, `3` it turned this node away (it
has not allowed it), `4` it is allowed but not on that channel, `5` what was asked makes no sense, `6` the link
already carries as many of this node's streams as a link does.

CLOSED says why: `0` closed here, `1` closed by the other end, `2` the link was lost, `3` this node stopped, `4` the
other node is no longer allowed, `5` the queue overflowed, `6` what came was no frame.

## A stream on the wire

One protocol, `ghost/1` (the ALPN). A stream is a QUIC bidirectional stream.

    opener    [channel: 1]
    taker     [01]                                   once it has checked the channel; otherwise it resets the stream
    both      [length: 4, big-endian][bytes] …       frames, each at most 1 MiB

`OPENED` is said only once the other end has answered, so a stream the app holds is one the other end took.

Closing is by either end and for both directions. The end that closes writes what it had queued, ends its half, and
waits (5 seconds at most) for the other end to have seen the end, which the other end shows by resetting its own
half: so a frame sent just before a close, or a close just before a stop, is not lost to what comes after. The
other end is handed every frame sent before the end, then CLOSED. What it had queued is given 10 seconds to be
written: past that the stream is reset, and what was still queued, or written and not yet arrived, is lost.

### A path that is held back

A link helper holds back a device that sends faster than the helper allows, it does not drop: through one, round
trips rise to seconds and bytes leave at the helper's pace. A stream then does what it does whenever the other end
is slow. Its writer waits on QUIC, the frames given to SEND wait in the stream's queue, and SENT says how many have
been written, which is what a sender that wants to be held back goes by (in Dart, the future `add` returns). A
sender that goes on regardless fills the queue (4 MiB or 4096 frames): that SEND is answered `-4`, the stream is
closed (CLOSED `5`; the other end sees it closed by this one, CLOSED `1`), and what was queued is dropped. Only
that stream: the link and its other streams go on. Reading is not hurried by any of this, except that a frame
whose length has been said has 15 seconds and 8 KiB a second to arrive (see "What is counted").

A link (one QUIC connection) is closed 30 seconds after its last stream: an open link costs both devices a packet
every few seconds. The next OPEN dials again.

## Who is let in

1. A caller that comes **through a link helper** is known before any handshake (the helper says who is calling). Not
   allowed, and with no channel open to all, it is refused there.
2. Any other caller is held by QUIC's early handle until the handshake has said who it is, and is closed on there if
   it is not allowed, before iroh has taken the link for its own (which is when iroh would tell it this node's
   addresses).
3. iroh's own hook (`after_handshake`) looks once more, and counts links (256 incoming at most).
4. Every stream's channel is checked as it is opened, and again when who is allowed changes.

A link this node dialled is one it chose; streams the other node opens on it are still checked (4).

### What a caller that is turned away can still learn

Not nothing, and it is iroh's to close, not this library's. QUIC's hole punching, inside iroh, lets a caller name
addresses of its own as soon as its handshake is done, and answers each with a small probe (35 bytes) before the app
has any say. A probe shows where it came from. So a node that is not allowed, but already knows an address and port
this node is reachable at straight (it cannot come through a link helper: see 1), can in the moment before it is
turned away be sent probes at addresses it chose, and so learn which address this node sends from towards each: its
IPv6 address where it knew the IPv4 one, or an address on another network it shares.
`cargo test how_often -- --ignored --nocapture` measures it between two nodes on one machine (0 to 11 of 300 to 600
callers, by run). What it cannot learn this way: anything without already having a working address, and the list of
this node's addresses, which only an allowed node is sent. A node started with `helpers_only` has no socket to probe
from at all.

## What is counted

So that no other device, however it behaves, makes this one hold more than it chose to:

| | |
| --- | --- |
| A frame | 1 MiB at most |
| Streams another node has open at once, on one link | 7 |
| What QUIC lets another node send unread | 256 KiB a stream, 1 MiB a link |
| A stream's queue of frames to send | 4 MiB or 4096 frames; past either the stream is closed (`-4`, CLOSED `5`) |
| What a stream has read that the app has not taken | 1 MiB + 64 KiB |
| What the whole node has read that the app has not taken | 32 MiB |
| Handshakes under way | 64 |
| Incoming links | 256, and one from any one node (a node that links again replaces its earlier link) |

Every frame is counted from the moment its length is read (its bytes and 64 more) until the app says `TAKEN` for
it, against its stream's window and against the node's one budget; an incoming stream counts 256 against the budget
until the app says `DONE`. While there is no room nothing is read, and QUIC holds the sender back. So the app must
say `TAKEN` as it hands frames on (and may hold it back while whoever listens is paused, which is how a slow reader
slows the sender), and `DONE` when it has handled a stream's end. A frame whose length was said and whose bytes do
not come (15 seconds, and no slower than 8 KiB a second) breaks the stream, so what was set aside is not held for a
sender that never sends.

What this does not give: fairness between nodes. One that is allowed and fills what it may (7 streams of 1 MiB or
so) holds a share of the budget; several together could hold all of it and slow the others until they are
disallowed or their frames time out. Nothing they do grows it.

## Building

    sh tool/build-p2p.sh mac        build/p2p/mac/libghost_p2p.dylib            both kinds of Mac in one file
    sh tool/build-p2p.sh android    build/p2p/android/arm64-v8a/libghost_p2p.so
    sh tool/build-p2p.sh ios        build/p2p/ios/GhostP2p.xcframework          a static library; not yet linked into the app
    cargo build --release           Windows (ghost_p2p.dll) and Linux (libghost_p2p.so), on their own runners

`Cargo.lock` is committed and every direct dependency is pinned to the version the tests ran against. Rust 1.91 or
later (built and tested with 1.94.1).

## Tests

    cargo test                                      in native/p2p: the node, the bytes, the C interface
    cargo test cost -- --ignored --nocapture        what an idle node costs, measured over a minute
    flutter test test/p2p_node_ffi_test.dart        the same essentials from Dart, through the built library
    flutter test test/p2p_node_contract_test.dart   the built library held to what the route's stand-in is held to

One test listens on this machine's port 80 to see that a link helper's name is never asked there. Where the
machine gives a test no port 80 (Linux without root, or a server already on it), that test has nothing to see and
passes.

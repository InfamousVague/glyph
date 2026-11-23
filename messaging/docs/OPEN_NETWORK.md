# The open network: direct links, relays that talk, a relay in the app, the web client

Matt, 2026-11-22: "do a major overhaul to make our network support p2p delivery with the relay as a primary source
but have p2p as a secondary back up that validates everything our relay says (maybe a bit slower so we use the relay
for speed, p2p for verification) I'd like the relays to be able to talk to each other and i'd like everyone to be
able to host a relay from their client, also build the full web client while we do this ... look at iroh as the rust
backend for the p2p side and take signficant inspiration from uplink".

This is the plan the work follows, and the reference for what is built. `docs/network.md` says what a route is;
this says what is added on top of it. Each part is behind its own switch and lands on its own, so the app is
releasable at every step. **Status** lines say what is built; everything else is the plan.

| Part | Where | Status |
| --- | --- | --- |
| Seams: a hub link and a hub socket that are not a WebSocket | `lib/net/hub_link.dart`, `relay/lib/hub.dart` | in progress |
| The direct network's core (Rust, iroh) | `native/p2p/`, `lib/net/p2p/` | planned |
| The direct route (`p2p`) | `lib/net/p2p/` | planned |
| Checking the relay: the ledger, the name watch | `lib/net/ledger.dart`, `lib/net/name_watch.dart` | planned |
| Relays that talk to each other | `relay/lib/federation.dart` | planned |
| A relay hosted from the app | `lib/relay_host/` | planned |
| The web client | `lib/web/`, `web/` | planned |

## What stays true

- **The relay comes first.** It is the fast path and the one that keeps things for someone who is away. The direct
  route comes after it: a way through when the relay can't carry something, and the way the relay is checked.
- **Everything is sealed before a route sees it** (`lib/net/switchboard.dart`, forward secrecy included). The direct
  route, a relay passing a packet to another relay, and a relay someone hosts all carry the same sealed packets.
- **Nobody is found by strangers.** A device makes direct links only with its own account's devices and with
  friends, and tells only them where it is. Nothing is published to a public directory.
- **Old builds keep working.** Every new thing said is a new envelope kind, a new field a build from before passes
  over, or a new message a relay from before answers "no such thing" to.
- **Rust carries bytes and nothing else.** Every rule below is Dart, so the tests, the phone, the computer and the
  browser share one implementation.

## What we take from Uplink

Uplink (Satellite.im) is built on Warp: identity, messaging, files and calls as interfaces over a peer-to-peer
network, with "shuttle" nodes anyone can run that keep things for people who are away. What this takes:

- **Who you are is a key, not an account on a server.** Already so here (an install's name is made from its key).
  New: a signed record of where you live (**home record**), so you can be found on any relay and can move.
- **Servers are helpers anyone can run**, and they talk to each other: relays that pass packets on, and a relay
  hosted from the app.
- **Devices talk straight to each other** where they can. Here that is a second route and a check, not the only way:
  Uplink's weak point is delivery when a straight path can't be made, and the relay is what covers that.
- **The same core in the browser.** The web client runs the same Dart.

## 1. Who is who

Unchanged: an account is a P-256 key pair; its **name** is the first 16 bytes of the SHA-256 of the public key, in
hex. Every device of the account holds the key. Each install has a **device** name (`hub_device`, 32 hex).

New, per device:

- A **node key**: 32 random bytes made on the device, kept in the secret store (`p2p_node`), never in the account's
  backup. The direct network's core turns it into the device's **node id** (an Ed25519 public key, 64 hex).
- A **device card**, which says "this node id is a device of this account":

      {"v":1, "a": account name, "k": account public key (33 bytes, base64), "d": device, "n": node id,
       "t": made (ms), "x": good until (ms), "s": signature (r then s, base64)}

  signed by the account's key over `"ghost-p2p card v1\n"` then `a (16) | d (16) | n (32) | t (8) | x (8)`.
  Anyone can check it: `idOf(k) == a`, and the signature is `k`'s. Good for 30 days, made again when a week is left
  or the node id changes.

New, per account:

- A **home record**, which says where the account lives:

      {"v":1, "a": account name, "k": public key, "h": [up to 3 relay addresses], "n": a count that only goes up,
       "t": made (ms), "s": signature}

  signed over `"ghost-home v1\n"` then `a | n (4) | t (8) | how many | each address, length first`. The highest `n`
  wins. Moving to another relay is signing a record with the next `n`.

A relay address is `wss://host/hub`, or for a relay hosted from an app `ghost-relay://<relay name>?n=<node
id>&via=<a public relay it stays linked to>` (section 5).

## 2. The direct route

**The core** (`native/p2p/`, Rust on iroh 1.x): a node started with the node key. It offers one thing: framed
streams to another node by its id, on a numbered channel. It dials, punches through NATs, falls back to a **link
helper** (iroh's relay servers: they help two devices find each other and carry their sealed traffic when a
straight path can't be made; they are not our relay), and says how each path stands (straight, through a helper,
gone). It turns away any node the app has not allowed, as soon as the handshake says who it is.

    channel 0  packets (this route)
    channel 1  a hub connection to a relay hosted from an app (section 5)
    channel 2  a relay talking to a relay (section 4)

How it is set up, and why (researched 2026-11-22, iroh 1.5.0):

- **Nothing public.** The endpoint is made with no address lookup at all (`presets::Minimal`): no DNS or pkarr
  record, no DHT, no mDNS. Where a device is, only its friends' devices and its own account's hear, in sealed
  envelopes (below), and that is what a dial is given.
- **Link helpers are ours, handed out by the relay.** iroh's public ones are for "development and hobby use only",
  so the app ships with none of its own: the relay's hub says which to use as an app signs in (`"helpers"`, from
  `GHOST_LINK_HELPERS`), as it hands out the call relay. Ours is an `iroh-relay` on the box (`tool/deploy-link.mjs`,
  on Matt's word). With none, links are made only between devices that can reach each other's addresses as they
  are (one network).
- **A phone's node is up only while there is something to say.** A node keeps every path warm every 5 seconds and
  its link helper every 15: megabytes a day and a radio that never sleeps (iroh issues 4651, 4590). A computer's
  stays up; a phone's is started for a send that fell back or a check, and stopped two minutes after its last
  stream closes.
- **Dart talks to it through a small C interface** (`native/p2p/src/ffi.rs`, `lib/net/p2p/node_ffi.dart`), not a
  generator: commands in, events out through one callback, bytes both ways. On Android the core is also loaded
  from Kotlin once, to give iroh's DNS the app's context (`install_android_jni_context`).

Dart reaches it through `lib/net/p2p/node.dart` (`P2pNode`): the real one over FFI, a stand-in mesh for tests
(`test/support/fake_p2p.dart`), and in the browser none (the core as WASM reaches others only through a link
helper; later). Where the library is not in a build, the route is simply not there.

**Telling each other where we are.** A new envelope kind, `p2p`, never asked to be answered, never sent by a route
that carries only small packets:

    {"t":"card", "c": device card, "w": {"r": link helper address, "a": [addresses], "t": ms}}
    {"t":"card?"}                    tell me yours
    {"t":"meet", "c": …, "w": …}     I am up, here: bring your node up and link, and tell me where you are

A device sends its card to a friend when they become friends, when its card changes, and when asked; its
whereabouts with it, and again with a `meet`. To the account's own devices the same goes through the account's own
name (`Net.mine`). What is kept: for each friend, up to 8 devices' cards and whereabouts (`p2p_cards`), dropped when
the card runs out or the friend is removed or blocked. A `meet` is answered at most six times an hour for one
friend, and not at all while Direct is off or the person chose Invisible.

**The route** (`P2pCarrier`, id `p2p`, shown as "Direct"):

- `reaches(peer)`: Direct is on, this build has the core, and an unexpired card is held for one of their devices.
- `send`: the node is started where it was not (a phone's), and the packet goes to every device a card is held
  for, on channel 0, dialling where no stream is open by where each last said it was (5 s in all). Passed if one
  took it; otherwise it throws and the switchboard goes on. It never keeps anything.
- What arrives is vouched for: the stream's node id has a card, and the card's account is who it is from
  (`Arrived.from`), as the hub's stamp is.
- A stream is let go after 90 s with nothing said. Nothing is dialled while the person chose Invisible, except to
  their own devices.
- **Meeting.** A device that wants a link with one whose node may be down (a check is due; something only kept by
  the relay) starts its own and sends a `meet` through the relay; the other brings its node up, answers with where
  it is, and the two dial. With the relay itself gone there is nothing to ask through: each device that sees the
  relay down for 15 s brings its node up by itself, and dials by what it last heard.

**The switchboard**: the order becomes `hub`, `p2p`, `lan`, `sms`. Two changes:

- When the hub only kept something (they are not connected to it) and a direct stream to one of their devices is
  open, it goes by that too, without waiting.
- It tells the ledger what was sent, by which route and what the route said, what came, and what was answered.

**Who learns what.** A friend's device learns this device's network address, as with any direct link; nobody else
does. A link helper sees node ids, addresses and how much is sent, never an account's name or what is said.
Settings › Routes has the switches: Direct on or off, and "Only through link helpers" (a friend's device then
sees the helper's address, not this one's).

## 3. Checking the relay

What the relay says, and what checks it:

| The relay says | Checked by |
| --- | --- |
| "Passed on" / "kept for them" | the other end's own answer (sealed), and the **ledger** compared over a direct link |
| "This is everything kept for you" | the ledger: what friends' devices say they sent |
| "They are here / away / gone" | a direct link being up, and what the friend's device says of its own connection |
| "@name is this key" | the **name watch**: friends' devices asking the same question and comparing |
| Who is in a room, what a room kept | not yet: later, members' own word over direct links |

**The ledger** (`lib/net/ledger.dart`). For each friend (and, later, the account's own devices), two short lists
kept for 7 days, at most 500 each: what was **sent** them (envelope name, when, the route, what the route said:
passed or kept, whether it was answered) and what was **got** from them (name, when, the route). Only what asks for
an answer is listed (not typing, tests, cards or the ledger's own messages). Kept with the app's choices; no words
of any message are in it.

When a direct stream to a friend's device opens, and every 15 minutes while it stays open, the two compare
(envelope kind `ldg`, by the direct route only):

    {"t":"sum", "w":[from, to], "s": names sent to you, "g": names got from you,
     "h": {"u": my relay, "up": whether I'm connected to it, "t": since when}}
    {"t":"dif", "want": names}                       I never got these: send them straight
    {"t":"was", "e": [[name, when, "p" or "k"], …]}  what the relay told me of each when I sent it

- What they sent that never came here is asked for (`want`) and sent again straight, by whoever still holds it
  (Friends' own list of what is unanswered, `lib/friends/friends.dart`; a call that has stopped ringing is not).
- What came here but they never heard was answered is marked answered: the answer was what got lost.
- Each thing that had to come straight is put down as one of: **made up for** (this device was away and another of
  the account's took it, or it could not be opened here), **the relay said passed, and it never came** (this
  device was connected to the relay at that moment), or **the relay kept it and never handed it over** (this is the
  account's only device, it signed in after, and the packet was not among what was handed over).
- A friend whose device says it is connected to the same relay while the relay says they are gone is put down as
  the relay being wrong about who is here.

Settings › Routes shows it per relay: when it was last checked and with how many devices, how many messages
matched, how many were made up for, and each thing the relay got wrong with its day. "Check now" dials the friends
the relay says are here (once a minute at most). With no direct link in use, a round runs by itself while the app
is on screen: up to 5 friends not compared in a day, every hour on a computer and every 6 hours on a phone.

**The name watch** (`lib/net/name_watch.dart`). A friend added by username was found by asking the relay "who is
@name". Each friend's app asks the same again once a day, and of its own name each time it signs in. An answer
that is a different key is shown on that friend ("The relay now says @maya is a different key; you are still
talking to the Maya you added"), and the friend is told by every route, so their app can say "a friend's app saw
the relay give your username to another key". An add-me link carries the first 8 hex digits of the key after `#`
(never sent to a server), and the app refuses an answer that doesn't match.

**What this does not check:** rooms (circles, spaces, voice), what the relay says to the browser client (it has no
direct route yet), and anything while no two devices are ever online together.

## 4. Relays that talk to each other

A relay gets a key of its own (`relay-key.json`), and a name made from it as an install's is. Its hello to an app
says so (`"relay": {"id", "key"}`), which a build from before passes over.

**A link between two relays** is one relay dialling the other's hub address and saying, in place of an app's
hello:

    {"fed":1, "id", "key", "sig", "url": its own hub address (where it has one), "c": a number it made up}
    {"ok":true, "fed":1, "id", "key", "sig": over "ghost-fed v1 " and c}

Each proves it holds its key; one that names a `url` is believed once the other has dialled that address and seen
the same key there (TLS says whose address it is). Whether a relay links at all is its keeper's choice:
`GHOST_FED=off | open | list`, with `GHOST_FED_ALLOW` and `GHOST_FED_BLOCK`. Off by default.

**What crosses a link:**

    [5][number: 4][to: 16][from: 16][packet]      → {"ack": number, "here": bool} or {"nak": number, "err"}
    [6][number: 4][to: 16][from: 16][relay: 16][packet]   the same, for a relay linked to the one asked (section 5)
    {"fed":"home", "rec": home record}
    {"fed":"whois", "q": n, "name"} → {"fed":"whois", "q": n, "id", "key", "home"} or {"none": true}

- A relay learns where someone lives only from their **home record**, which it checks; never from anyone's say-so.
  An app gives its relay its own record as it signs in (`{"dir":"home"}`) and its friends' as it needs them.
  Friends hear each other's records from each other, sealed: an envelope of kind `home` (`{"rec": …}`), sent when
  two become friends and whenever the record changes.
- A packet for someone not connected here whose record names another relay is passed to that relay, which hands it
  to their devices or keeps it as it would its own. One hop, or two through `via`; never further.
- **A relay speaks only for its own people:** what relay A passes on as from X is taken only where X's record
  names A as home. So a relay can't put anyone else's name on a packet.
- With the other relay down, packets wait here (per relay: 2,000 packets or 16 MB, seven days), and the sender is
  told "kept".
- Limits per linked relay: packets a minute, bytes a day, and the same mailbox limits per person as ever.

**Names.** `@maya` is a name on the relay you are on; `@maya@relay.example` is one on another. The app asks its own
relay (`{"dir":"whois","name":"maya","at":"relay.example"}`), which asks the other over a link; where its own relay
doesn't link, the app asks the other relay itself. The friend is kept with their home record, and every packet to
them goes through the app's own relay as now.

**Moving.** Signing a home record with the next count, giving it to the old relay, the new one and one's friends.
Friends' apps follow the record; the old relay passes on what still comes to it.

**Not in the first version:** who is here across relays (the direct link says it instead), and rooms across relays
(a circle stays on the relay it was made on; the app joining a room on another relay is the step after).

## 5. A relay hosted from the app

The relay is a Dart package with nothing in it but Dart (`relay/`), so the app runs the same hub in itself:
Settings › Routes › Host a relay on this device.

- It is given a key and a folder of its own, small limits (200 connections, 32 MB kept), and, where the person
  wants, a pass phrase people must have to use it.
- **Reached three ways:** by this app itself, in memory; by devices on the same network (`ws://address:port/hub`);
  and from anywhere over the direct network, as a hub connection on channel 1 to its node id, with no port opened
  and no certificate.
- **It stays linked to a public relay** (`via`, ours unless changed): it dials out as a relay does, so nothing
  needs to reach in. People on other relays reach its people through that link (`[6]`, above), and its people reach
  everyone else the same way back.
- It is up while the app is running: on a computer for as long as it is open, on an Android phone while the app is
  in use, on an iPhone not at all.

## 6. The web client

The same app, built for the browser, as one more device of an account: sign in with the username and password,
which fetches the account's sealed backup as any new device does (`lib/account/account.dart`). A browser is the
**standalone** mode a computer with no phone linked already runs in (`lib/standalone/`).

What stood in the way, surveyed 2026-11-22, and what answers each:

| In the way | Answer |
| --- | --- |
| The import graph is one piece (`net.dart` reaches 355 of 377 files), so nothing can be left out by not importing it | One build of the whole app (dart2js), with its own entry, `lib/web/main.dart` |
| `dart:ffi` in two files (TDLib, Apple's SHA): a compile error | Split by conditional import; the browser's half says "not here" |
| `fast_gcm.dart` needs 64-bit integers | A browser half that uses the browser's own AES-GCM, or 32-bit halves |
| `Platform.isX` 166 times in 59 files: compiles, then throws in a browser | `lib/platform_info.dart`: the same questions, answered from `dart:io` where there is one and "a browser" where not |
| `Isolate.run` in 14 files | `runAside()`: an isolate where there is one, in place where not |
| `gzip` from `dart:io` on the sign-in path | A Dart one (`package:archive`) in the browser |
| Argon2id (64 MiB, 3 passes) would freeze the page | The same JavaScript one the extension uses (`extension/src/ghost/crypto.ts`), which gives way as it works |
| The platform seam (`SmsCalls`: about 40 calls) | `WebCalls`, beside `StandaloneCalls`: `UsernameChats` as it is, kept in IndexedDB as one record |
| The Keychain | Secrets in IndexedDB, sealed with a key the page can use but not read out (WebCrypto, not extractable); or the password asked again each visit |
| The hub's WebSocket | `hub_link_web.dart` (the seam) |
| Pickers that hand back paths | Bytes in the browser |

In the first version: signing in, friends and groups of friends, circles and their spaces' chat, calls (the
browser's WebRTC, as `site/join/voice.js` already proves the room protocol in one), who is here, profiles,
reporting, formatting, forward secrecy. Not in it: texts through a phone, the other networks' chats (they need
helper programs), Files spaces, plugins and the Marketplace, recording, the voice changer and noise removal, screen
sharing, the local API, and the direct route (so the browser doesn't check the relay). A closed tab gets nothing:
there is no push to a browser yet.

Served as plain files from the same host as the relay (`/app/`; the relay sends no cross-origin headers), which a
relay anyone runs can serve as well. Tried against a relay on this machine (`dart run relay/bin/relay.dart`), with
accounts made for the test.

## The order of work

1. Seams (`HubLink`, `HubSocket`).
2. The core and its binding; the direct route against a stand-in node. Side by side.
3. The ledger and the name watch.
4. Relays that talk; names across relays.
5. A relay hosted from the app; a hub connection over the direct network.
6. The web client, alongside all of the above.
7. Each build's packaging (Android, the Mac, Windows, Linux; the iPhone when it ships), then an independent review
   before each switch is turned on.

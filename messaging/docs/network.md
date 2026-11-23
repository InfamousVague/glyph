# Ghost Messaging's network: routes

Matt, 2026-11-14: "implement a full relay system for the app that's replacable and swappable so that for right now
we can use our servers to negotiate calls through the app, video chats andre but in the future id like to be able to
use a P2P decentralized relay. Look up Satellite.im on google for information (look at github) for what this will
look like", "everything should habe the option for encryption", "At its core id also like to be able to send almost
all chat data and negotiate calls when both parties have sms enabled. The goal will be to have multiple sources to
feed data to eachother from wifi locally, p2p, internet, sms, etc".

What Satellite's Warp does that this takes: the parts are interfaces first, and what stands behind an interface can
be changed without the app above knowing (their messaging, identity and calls modules sit on IPFS and libp2p today
and were written so they need not). Here the interface is a **route**.

| Part | Where | What |
| --- | --- | --- |
| A route | `lib/net/carrier.dart` (`Carrier`) | One way of getting bytes to another install: start, stop, "do you reach them", send, what arrived, and what it is like (how long a packet, does it cost money, does it wake a closed app) |
| The switchboard | `lib/net/switchboard.dart` | Chooses a route for each thing sent, falls back, seals, opens, tells copies apart, answers |
| The relay server's hub | `relay/lib/hub.dart`, `lib/net/hub_carrier.dart` | The route through a server: names, held packets, who is here, rooms |
| The direct route | `lib/net/p2p/` (`P2pCarrier`, `P2p`, `DeviceCard`, `P2pNode`) | Straight between a person's own devices and their friends', with no server in between: the way through when the relay can't carry something ([OPEN_NETWORK.md](OPEN_NETWORK.md), section 2) |
| SMS | `lib/net/sms_carrier.dart`, `android/…/NetSms.kt` | The route through the phone network: data texts |
| The phone's keys | `android/…/Net.kt`, `E2e.kt` | Who this phone is, who it can reach, a signature for a hub |
| The app's hold on it all | `lib/net/net.dart` (`Net`), `lib/ui/network.dart` | Set up as the app opens; Settings › Network |

The **peer-to-peer** route this made room for is built: `p2p`, shown as "Direct" (Matt, 2026-11-22: "p2p delivery
with the relay as a primary source but have p2p as a secondary back up"). [OPEN_NETWORK.md](OPEN_NETWORK.md) is its
plan and its reference: device cards, who a device links with, when its node runs, link helpers. Its rules are all
Dart (`lib/net/p2p/`), tested against a stand-in node (`test/support/fake_p2p.dart`, `test/p2p_test.dart`); the
node itself is the core (`native/p2p/`, Rust on iroh), behind `lib/net/p2p/node.dart`. A build without the core has
no direct route at all (`Net.p2pNode` is null) and Settings › Routes shows none. Devices tell each other their cards
and where they are in envelopes of one more kind, `p2p`, which go by the other routes and never by a text.

**The direct route's limits** (the second review, 2026-11-23). The ones that count (meets, cards looked at, things
said, streams and frames) are kept in memory and start over each time the app starts: enough while each is small
against an hour, and an app started over and over is a cost of its own.

- **Who is a friend** to it is decided by account id from the records that say so, never by an address: friends by
  username in the state `yes` (by their id, where their key makes it) and friends by number whose record says so (by
  the id the key on that record makes, which android `E2e.state` gives Dart). On Android the people the routes reach
  include the members of every group, whose addresses are whatever the group's admin wrote; none of them is a friend
  for it.
- **A stream proves whose it is** with a nonce from each end and then `HMAC(link key, "ghost-p2p link v2\n" | from
  account | from node | to account | to node | the other's nonce | its own)`, the one that dialled first.
- **What is known of a dial** (failed, under way) is kept for each account at each node: a friend who names another
  friend's node as his costs only his own route. Up to two streams not yet proved and two proved are held with a node,
  and one not yet proved never takes the place of one proved.
- **A phone's node** is up only for a reason of its own (a send of its own, a meet it asked for or answered, the relay
  gone with the app in use) and stops two minutes after the last, whatever streams are open. Only a packet from the
  account a stream proved to be counts as something said on it.
- **Meets** are answered at most six times an hour for one friend and twelve for all; a phone with the app put away is
  not brought up for one, and tells where it is only while the app is in use. A computer's node stays up, as before.
- **What one stream may bring**: 100 frames at once and 10 a second after; an account's devices together, 150 and 15.
  At most ten streams a minute are taken from one node. A frame is given at least a second to go, and a stream slow to
  take one is not closed for it.
- **What is said to friends** (cards, asks, meets) goes only while the relay says one of their devices is connected
  (the hub's presence), the rest told when they come; someone who never answers is asked three times and no more.
  Switching "Only through link helpers" tells them at once, and anything newer that says nothing of where a device is
  clears the addresses held for it.
- **Cards**: one for another node that is older than the one held for that device is taken (a device whose clock went
  back), and the account asked at once in case it is a copy from before; a send dials no device of a friend's unheard
  from (card, meet, proved stream) in sixteen days while another of theirs has been, an install from before. Addresses
  that are loopback, unspecified, multicast, broadcast or link-local, in any form, are never taken or dialled.
- **What is kept**: the node key with the account it was made under, in the secret store; the cards held, with the
  app's choices, under a seal (an HMAC keyed from the node key) that spares checking their signatures again at each
  start; where friends' devices are, in the secret store (`p2p_where`), out of any backup. Choices restored from another
  device's backup (they name a node id with no node key here) give the device a name (`hub_device`) of its own.
- A core that fails to load costs the direct route alone; Settings › Routes says why. What the core itself must
  guarantee is written in `lib/net/p2p/node.dart`.

Not built yet: a **local network** route (`lan`: finds the other install on the same Wi-Fi and connects straight to
it). It is one more `Carrier` handed to `Switchboard.add`; `test/net_test.dart` takes the hub out and puts a
stand-in in its place to hold that true.

## Who is who

An install is a P-256 key pair. On a phone it is the pair its encryption already has (`E2e.kt`, private half under
the Android Keystore), so **the people the routes reach are the people encryption is on with**, and exchanging keys
by text is what introduces two phones. An install's **name** is the first 16 bytes of the SHA-256 of its public key,
in hex: a hub and a stranger learn no number from it.

Two installs seal with a key made from their conversation key and used for nothing else
(`HMAC(conversation key, "ghost-net pair" 01)`): AES-256-GCM, a random nonce, "ghost-net-v1" bound in. Kotlin makes
it on the phone and hands it to Dart; `lib/net/crypto.dart` makes the same in Dart for a computer and the tests
(`NetCryptoTest.kt` and `test/net_test.dart` hold both to the same bytes from the same two key pairs).

## What crosses

An **envelope** (`lib/net/packet.dart`): a name of 16 hex digits made by the sender, a kind (`text`, `read`,
`typing`, `call`, `room`, `hello`, `ping`, `ack`), when, a body, and whether an answer is wanted. JSON, so a newer
build can say more and an older one passes over what it does not know.

A **packet** is an envelope as a route carries it:

    [version and flags][from: 16 bytes][the envelope, sealed or not]
    [version and flags | part][from][which packet: 4 bytes][part number][how many][a piece of the above's last field]

A call's ring, sealed, is 123 bytes: one data text. Longer ones cross a short route in pieces.

## How the switchboard chooses

- The routes are tried in order: `hub`, `p2p`, `lan`, `sms` where the person has not said otherwise. The relay
  comes first: it is the fast path, and the one that keeps things for someone who is away. (Until 2026-11-22 the
  order was `lan`, `p2p`, `hub`, `sms`, with only `hub` and `sms` built; no install keeps an order of its own.)
- One is passed over when it is switched off, not up, does not reach that person, cannot hold the packet even in
  pieces, or costs money and this is not something allowed to (`metered`: only a ring, a greeting, a test).
- On a route where an answer comes at once the answer is waited for (4 s); with none the next is tried. The other
  end knows the second copy by the envelope's name and passes it on once, answering both.
- Kept by a hub for someone who is away is good enough, unless it is urgent (a call ringing): then the routes after
  are tried too, so the one that wakes a closed app gets its turn.
- Once a route has only kept it, a route that holds links of its own (`LiveLinks`: the direct route) is given it
  only where a link to one of their devices is open right now, by that link alone. Nothing is dialled and nothing
  started for someone who is away; where it was not urgent that copy is not waited for.
- The same where a route passed it on and no answer came in time (their app is slow, not away: nothing is started or
  dialled for that), and for something urgent while a route that wakes a closed app comes after the direct one (that
  one goes at once, not after a dial). With the relay down and no such route after it, the direct route dials as any
  route would.
- An answer (`ack`, `fsk`) goes back by the route the thing it answers came by, and on the direct route on the very
  stream it came on (`Arrived.line`, `LiveLinks.sendOn`), else by another stream open to them: never to every device
  of the sender, never by a dial.
- What a route of live links brings waits its turn with the rest, one at a time and in order, but no more than 128 of
  its arrivals wait at once; the rest are dropped and counted (`Switchboard.droppedArrivals`), so a flood from someone's
  device never holds the relay's arrivals up for long.
- Sealed unless the sender says not to. Nothing unsealed is taken from someone a key is held for; from a name no
  key is held for, only a `hello` in the clear is shown to the app.
- An answer never goes back by a route that costs money.

## The hub

`relay/` serves it at any address ending `/hub`, beside the pairings' relay (`/relay/<channel>`): on our server
that is `wss://ghost-sms.com/hub`, live since 2026-11-14 (`relay/README.md`, "On our server"). Anyone can run
one; Settings › Network takes its address.

1. The hub says `{"hello": <64 hex digits>}`. The app answers `{"id", "key", "sig"}`: its name, its public key
   (33 bytes, base64) and its signature over `"ghost-hub v1 "` and those 32 bytes (r then s, base64). The hub
   checks the name is that key's and the signature is that key's (`relay/lib/p256.dart`, Dart's BigInt and nothing
   else, held to RFC 6979's example), then `{"ok": true, "held": n}` and whatever was kept. Where the relay was
   given link helpers for the direct route (`GHOST_LINK_HELPERS`), the same answer names them: `"helpers":
   ["https://…"]`, four at most.

   **Bound to the relay (v2, since 2026-11-23).** A v1 signature says nothing of where it was made: a relay the app
   was pointed at, or asked a name of, could hand the app the number of the app's own relay and sign in there as the
   app with the answer (found in the review of relays that talk). A hub that knows the names it is reached at
   (`GHOST_HUB_NAMES`) says `"v2": true` in its hello, and the app answers `{"id", "key", "sig", "v": 2, "host"}`, the
   signature over `"ghost-hub v2 "`, the length of the host (one byte), the host the app dialled (lower case, its port
   only where it is not the scheme's own: `gogho.st`, `relay.example.com:8443`), then the 32 bytes. The hub takes it
   only for a host in its own names, and from a key that has signed in with v2 it takes no v1 again (kept across
   restarts), so a v1 signature an app of this build gives anywhere else is worth nothing at its own relay. A hub that
   says nothing of v2 is signed v1, as ever; Android's background check (`HubPeek.kt`) signs as the app does. A name
   looked up on another relay itself (`lib/net/relay_ask.dart`) signs in there under a key made for that one question,
   with no device's name, and takes nothing it is handed.
2. `[1][a number: 4 bytes][to: 16 bytes][packet]` goes to that name as `[1][from: 16 bytes][packet]`, answered
   `{"ack": number, "here": true}`; or is kept (200 packets or 1 MB a person, seven days, in memory) and answered
   `"here": false`; or refused, `{"nak": number, "err": "full"}`. For someone who lives on another relay (where this
   one talks to others: `relay/README.md`, "Other relays") the answer carries `"fed": true` and never says whether they
   are connected (`"here": false`, taken), `"waiting": true` where it waits on this relay for theirs, or `nak` with
   `home`, `busy`, `far` or `refused`, which the app says as the reason in the conversation.
3. `{"watch": [names]}` is answered `{"here": [those connected]}`, then `{"came": name}` and `{"went": name}`.
4. Rooms: `{"join": <32 hex>, "token": <64 hex>}`, both made by the members from a key only they hold; the first to
   name a room sets its token. `{"room", "ok", "members"}` to the one joining, `{"room", "came"}` to the rest;
   `[2][room: 16 bytes][packet]` goes to the others as `[2][room][from][packet]`; `{"leave": room}`, or the
   connection dropping, tells them `{"room", "went"}`. A room nobody is in is forgotten. Up to 64 in one.

It sees which names talk to which, when and how much. It holds no account, number or name, logs no address, and
cannot open a packet.

## SMS

A packet goes as a **data text**: an SMS addressed to a port (16962), which Android hands to the app that listens
there and to no other. It is never written to the phone's messages and no texting app shows it, so it works whether
or not Ghost Messaging is the phone's texting app. 133 bytes each, up to six for one packet, each a text on the
person's plan. One that comes with the app closed is kept (sixty, a day) and handed over when it opens.

## Trying it

`test/net_test.dart` (17 tests): the cryptography against fixed keys and against the hub's own arithmetic; a packet
in pieces; the switchboard's choosing with stand-in routes; and two installs through the real hub on this machine
(kept while away and handed over, a name only its key holder can use, a room joined and left).

On two throwaway emulators, 2026-11-14, with the release build:

    dart run relay/bin/relay.dart --port 8788 --verbose        # the hub, on the Mac
    emulator -avd ghostflutter2 -read-only -no-window -port 5590   # and another on 5592

Each app made its key pair as it opened. Each was then given the other's public key by writing a `peer:` entry
into its `shared_prefs/e2e.xml` as root (what turning encryption on does, without the taps), and
`net_hub = ws://10.0.2.2:8788/hub` into `ui.xml`. Both signed in to the hub with keys held by the Android Keystore
(`hub 1fd7b9 came`, `hub 06f920 came`); Settings › Network said "1 person · 2 routes ready"; "Send a test" from one
said "Reached them by Relay server in 12 ms" and the other listed "A test came from 5590 · Relay server". By SMS
only, the first emulator's modem took the data text (98 bytes, `SEND_SMS` answered without error), and a data text
handed to the second through Android's own telephony (`tool/mms/Inject.java`, port 16962) reached the app ("data
text in"). **Not seen:** a data text crossing between two phones. The emulators' modems do not pass them to each
other, and some carriers do not either; that needs two real phones.

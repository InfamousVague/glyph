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
| SMS | `lib/net/sms_carrier.dart`, `android/…/NetSms.kt` | The route through the phone network: data texts |
| The phone's keys | `android/…/Net.kt`, `E2e.kt` | Who this phone is, who it can reach, a signature for a hub |
| The app's hold on it all | `lib/net/net.dart` (`Net`), `lib/ui/network.dart` | Set up as the app opens; Settings › Network |

Not built yet, and what each would be: a **local network** route (`lan`: finds the other install on the same Wi-Fi
and connects straight to it), a **peer-to-peer** route (`p2p`: libp2p or the like, with no server of ours), and
**calls** on top (`lib/calls/`: a call is set up by envelopes over these routes; its sound and picture go phone to
phone). Each is one more `Carrier` handed to `Switchboard.add`; `test/net_test.dart` takes the hub out and puts a
stand-in `p2p` in its place to hold that true.

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

- The routes are tried in order: `lan`, `p2p`, `hub`, `sms` where the person has not said otherwise.
- One is passed over when it is switched off, not up, does not reach that person, cannot hold the packet even in
  pieces, or costs money and this is not something allowed to (`metered`: only a ring, a greeting, a test).
- On a route where an answer comes at once the answer is waited for (4 s); with none the next is tried. The other
  end knows the second copy by the envelope's name and passes it on once, answering both.
- Kept by a hub for someone who is away is good enough, unless it is urgent (a call ringing): then the routes after
  are tried too, so the one that wakes a closed app gets its turn.
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
   else, held to RFC 6979's example), then `{"ok": true, "held": n}` and whatever was kept.
2. `[1][a number: 4 bytes][to: 16 bytes][packet]` goes to that name as `[1][from: 16 bytes][packet]`, answered
   `{"ack": number, "here": true}`; or is kept (200 packets or 1 MB a person, seven days, in memory) and answered
   `"here": false`; or refused, `{"nak": number, "err": "full"}`.
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

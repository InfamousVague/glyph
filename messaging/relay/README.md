# Ghost Messaging's relay

Passes sealed frames between a phone and the computer it is paired with when they are on different networks
(Matt, 2026-11-13: "I'd like to support both a relay server and local networking"; [../docs/desktop.md](../docs/desktop.md)).
Dart's own library and nothing else. It is on our server since 2026-11-14 (Matt: "Deploy the relay"), behind
ghost-sms.com: `wss://ghost-sms.com/relay` and `wss://ghost-sms.com/hub`.

```sh
dart pub get                                   # the test package only; nothing the relay itself runs
dart run bin/relay.dart --port 8787 --verbose  # ws://127.0.0.1:8787
dart test                                      # the relay and its SHA-256
dart compile exe bin/relay.dart -o ghost-relay # one file to run on a server
```

Use the `dart` that comes with Flutter (`$(dirname $(which flutter))/dart`) where another is first on the path.

## The hub

The same program also serves **the hub** at any address ending `/hub`: where two people's apps find each other
through this server (Matt, 2026-11-14: "for right now we can use our servers to negotiate calls through the app").
It is `lib/hub.dart`, with its own signature checking in `lib/p256.dart`, and is described with the rest of the
app's routes in [../docs/network.md](../docs/network.md). Behind a web server it needs one more line beside the
relay's: in Caddy, `handle /hub { reverse_proxy 127.0.0.1:8787 }`. It keeps nothing on disk: at most 96 MB of
packets for people who are away, in memory, and 20,000 connections.

## What an end says to it

1. It opens a WebSocket at any address ending in the channel: `ws://host/relay/<32 hex digits>`.
2. Its first message, as text: `{"auth":"<64 hex digits>","role":"phone"|"desk"}`, with `"temp":true` for a channel
   made for pairing. The relay answers `{"ok":true,"peer":true|false}`, or `{"ok":false,"err":…}` and closes.
3. Binary messages go to the other end as they are. With the other end away the sender gets `{"dropped":true}`.
4. The relay says `{"peer":true}` and `{"peer":false}` as the other end comes and goes.
5. `{"delete":true}` removes the channel (unpairing). `{"ping":n}` is answered `{"pong":n}`.

## What it keeps, and what it can see

`relay-data/channels.json` holds, for each pairing, the channel, the SHA-256 of its token and the day it was last
used. No frame is written or held; no address is logged. It can see that two addresses share a channel, when, and
how much they send. A pairing's channel is removed by unpairing or after ninety days unused; a pairing-time channel
lives ten minutes and is never written.

## On our server

    node tool/deploy-relay.mjs --keep-connection && node tool/deploy-site.mjs --caddy   # the first time: one login
    node tool/deploy-relay.mjs                                                          # after that, when relay/ changes
    flutter test tool/net/live_hub_test.dart --dart-define=HUB=wss://ghost-sms.com/hub  # two made-up installs through it

`tool/deploy-relay.mjs` builds the relay for the box from the Mac (`dart compile exe --target-os linux
--target-arch x64`), and in one ssh session checks it arrived whole and runs there, that its port is its own or
nobody's, then installs it: a user of its own with no shell (`ghost-relay`), the program in `/opt/ghost-relay`,
what it keeps in `/var/lib/ghost-relay`, and a systemd service (`ghost-relay`) that restarts it, may write nowhere
else, and may use 300 MB and one processor. It listens on `127.0.0.1:18787`: 8787 is another site's on that box,
which the first deploy found and stopped at before changing anything. `tool/deploy-site.mjs --caddy` writes
`@relay path /hub /relay/*` and `reverse_proxy 127.0.0.1:18787` into ghost-sms.com's own block of the shared
Caddyfile, with that script's backup and its asking of every other site before and after.

Done 2026-11-14 04:35 UTC, in one login: the service up, every other site on the box answering as before, and
from outside `https://ghost-sms.com/relay/` and `/hub` answering "Ghost Messaging relay". The live check signed in
in 380 ms, had a packet held for someone away and handed over, one passed and answered in 164 ms, and a room
joined by two and left. A restart of the service drops whoever is connected (the apps connect again by
themselves) and loses what the hub held.

Elsewhere: listen on 127.0.0.1 and let the web server that holds the certificate pass `/relay/*` and `/hub` to it.
In Caddy: `handle /relay/* { reverse_proxy 127.0.0.1:8787 }`. It needs no other setup.
